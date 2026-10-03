//! Wire schema for `AmazonCodeWhispererService.GetUsageLimits` — the exact
//! call kiro-cli's own `/usage` slash command makes (confirmed by tracing
//! `kiro-cli chat --no-interactive -vvv "/usage"`, which logs the operation
//! name and the `management.<region>.kiro.dev` endpoint it resolves to for an
//! IAM Identity Center account). Verified live against
//! `https://codewhisperer.us-east-1.amazonaws.com/` with `x-amz-target:
//! AmazonCodeWhispererService.GetUsageLimits` and the account's own cached
//! bearer token:
//!
//! ```json
//! {
//!   "nextDateReset": 1785542400.0,
//!   "subscriptionInfo": { "subscriptionTitle": "KIRO POWER" },
//!   "usageBreakdownList": [{
//!     "resourceType": "CREDIT",
//!     "displayName": "Credit",
//!     "currentUsageWithPrecision": 9943.38,
//!     "usageLimitWithPrecision": 10000.0
//!   }]
//! }
//! ```
//!
//! **Reverse-engineered, not documented** — CodeWhisperer/Q Developer has no
//! public API reference (AWS's own docs say as much). Community reference
//! implementations exist (`Finesssee/ProxyPilot`, `HsnSaboor/CLIProxyAPIPlus`)
//! confirming the same request/response shape against `codewhisperer.*.amazonaws.com`.

use chrono::{DateTime, Utc};
use serde::Deserialize;

use crate::error::{AppError, Result};
use crate::usage::KiroSnapshot;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageLimitsResponse {
    #[serde(default)]
    pub subscription_info: Option<SubscriptionInfo>,
    #[serde(default)]
    pub usage_breakdown_list: Vec<UsageBreakdown>,
    #[serde(default)]
    pub next_date_reset: Option<f64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionInfo {
    #[serde(default)]
    pub subscription_title: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageBreakdown {
    #[serde(default)]
    pub resource_type: Option<String>,
    #[serde(default)]
    pub current_usage_with_precision: Option<f64>,
    #[serde(default)]
    pub usage_limit_with_precision: Option<f64>,
}

/// The list can carry more than one resource bucket; the credit pool
/// (`resourceType: "CREDIT"`) is what kiro-cli's own `/usage` renders, so it
/// wins when present. A single-entry list with no `resourceType` (seen on
/// some plans) is accepted as-is rather than rejected on a technicality.
fn credit_breakdown(list: &[UsageBreakdown]) -> Result<&UsageBreakdown> {
    if let Some(credit) = list
        .iter()
        .find(|b| b.resource_type.as_deref() == Some("CREDIT"))
    {
        return Ok(credit);
    }
    if let [only] = list
        && only.resource_type.is_none()
    {
        return Ok(only);
    }
    if list.is_empty() {
        Err(AppError::Schema(
            "kiro: `usageBreakdownList` is empty".into(),
        ))
    } else {
        Err(AppError::Schema(
            "kiro: no unambiguous `CREDIT` usage bucket".into(),
        ))
    }
}

pub fn to_snapshot(resp: UsageLimitsResponse) -> Result<KiroSnapshot> {
    let plan = resp
        .subscription_info
        .as_ref()
        .and_then(|s| s.subscription_title.as_deref())
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| {
            AppError::Schema("kiro: missing `subscriptionInfo.subscriptionTitle`".into())
        })?
        .to_string();

    let breakdown = credit_breakdown(&resp.usage_breakdown_list)?;

    let used = finite(
        "currentUsageWithPrecision",
        breakdown.current_usage_with_precision,
    )?;
    let limit = finite(
        "usageLimitWithPrecision",
        breakdown.usage_limit_with_precision,
    )?;

    let reset_at = resp
        .next_date_reset
        .map(|secs| seconds_to_datetime("nextDateReset", secs))
        .transpose()?;

    Ok(KiroSnapshot {
        plan,
        used,
        limit,
        reset_at,
    })
}

fn finite(field: &str, v: Option<f64>) -> Result<f64> {
    let v = v.ok_or_else(|| AppError::Schema(format!("kiro: missing `{field}`")))?;
    if !v.is_finite() || v < 0.0 {
        return Err(AppError::Schema(format!(
            "kiro: `{field}` is not a non-negative finite number ({v})"
        )));
    }
    Ok(v)
}

fn seconds_to_datetime(field: &str, secs: f64) -> Result<DateTime<Utc>> {
    if !secs.is_finite() || secs < 0.0 {
        return Err(AppError::Schema(format!(
            "kiro: `{field}` is not a valid Unix timestamp ({secs})"
        )));
    }
    DateTime::from_timestamp(secs as i64, 0)
        .ok_or_else(|| AppError::Schema(format!("kiro: `{field}` is out of range ({secs})")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> UsageLimitsResponse {
        serde_json::from_str(
            r#"{
                "daysUntilReset": 0,
                "nextDateReset": 1785542400.0,
                "subscriptionInfo": { "subscriptionTitle": "KIRO POWER" },
                "usageBreakdownList": [{
                    "resourceType": "CREDIT",
                    "displayName": "Credit",
                    "currentUsageWithPrecision": 9943.38,
                    "usageLimitWithPrecision": 10000.0
                }]
            }"#,
        )
        .unwrap()
    }

    #[test]
    fn parses_the_verified_live_shape() {
        let snap = to_snapshot(sample()).unwrap();
        assert_eq!(snap.plan, "KIRO POWER");
        assert_eq!(snap.used, 9943.38);
        assert_eq!(snap.limit, 10000.0);
        assert_eq!(
            snap.reset_at,
            Some(DateTime::from_timestamp(1785542400, 0).unwrap())
        );
    }

    #[test]
    fn picks_the_credit_bucket_when_multiple_are_present() {
        let mut resp = sample();
        resp.usage_breakdown_list.insert(
            0,
            UsageBreakdown {
                resource_type: Some("OTHER".into()),
                current_usage_with_precision: Some(1.0),
                usage_limit_with_precision: Some(2.0),
            },
        );
        let snap = to_snapshot(resp).unwrap();
        assert_eq!(snap.used, 9943.38);
    }

    #[test]
    fn falls_back_to_the_first_entry_with_no_resource_type() {
        let resp: UsageLimitsResponse = serde_json::from_str(
            r#"{
                "subscriptionInfo": { "subscriptionTitle": "KIRO POWER" },
                "usageBreakdownList": [{
                    "currentUsageWithPrecision": 5.0,
                    "usageLimitWithPrecision": 10.0
                }]
            }"#,
        )
        .unwrap();
        let snap = to_snapshot(resp).unwrap();
        assert_eq!(snap.used, 5.0);
        assert_eq!(snap.limit, 10.0);
    }

    #[test]
    fn explicit_non_credit_single_bucket_is_schema_drift() {
        let mut resp = sample();
        resp.usage_breakdown_list[0].resource_type = Some("OTHER".into());
        assert!(matches!(to_snapshot(resp), Err(AppError::Schema(_))));
    }

    #[test]
    fn multiple_unknown_buckets_are_schema_drift() {
        let mut resp = sample();
        resp.usage_breakdown_list = vec![
            UsageBreakdown {
                resource_type: None,
                current_usage_with_precision: Some(1.0),
                usage_limit_with_precision: Some(2.0),
            },
            UsageBreakdown {
                resource_type: Some("OTHER".into()),
                current_usage_with_precision: Some(3.0),
                usage_limit_with_precision: Some(4.0),
            },
        ];
        assert!(matches!(to_snapshot(resp), Err(AppError::Schema(_))));
    }

    #[test]
    fn missing_reset_is_none_not_an_error() {
        let mut resp = sample();
        resp.next_date_reset = None;
        let snap = to_snapshot(resp).unwrap();
        assert_eq!(snap.reset_at, None);
    }

    #[test]
    fn missing_plan_is_schema_drift() {
        let mut resp = sample();
        resp.subscription_info = None;
        assert!(matches!(to_snapshot(resp), Err(AppError::Schema(_))));
    }

    #[test]
    fn empty_breakdown_list_is_schema_drift() {
        let mut resp = sample();
        resp.usage_breakdown_list.clear();
        assert!(matches!(to_snapshot(resp), Err(AppError::Schema(_))));
    }

    #[test]
    fn non_finite_usage_is_schema_drift() {
        let mut resp = sample();
        resp.usage_breakdown_list[0].current_usage_with_precision = Some(f64::NAN);
        assert!(matches!(to_snapshot(resp), Err(AppError::Schema(_))));
    }

    #[test]
    fn negative_usage_is_schema_drift() {
        let mut resp = sample();
        resp.usage_breakdown_list[0].current_usage_with_precision = Some(-1.0);
        assert!(matches!(to_snapshot(resp), Err(AppError::Schema(_))));
    }
}
