//! Wire types for DeepInfra billing endpoints.

use serde::Deserialize;

use crate::error::{AppError, Result};
use crate::usage::DeepInfraSnapshot;

#[derive(Debug, Clone, Deserialize)]
pub struct Checklist {
    #[serde(deserialize_with = "de_finite")]
    pub stripe_balance: f64,
    #[serde(deserialize_with = "de_nonnegative_finite")]
    pub recent: f64,
    #[serde(default, deserialize_with = "de_opt_finite")]
    pub limit: Option<f64>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UsageResponse {
    pub months: Vec<UsageMonth>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UsageMonth {
    pub period: String,
    #[serde(deserialize_with = "de_nonnegative_finite")]
    pub total_cost: f64,
}

fn checked_finite<E: serde::de::Error>(value: f64) -> std::result::Result<f64, E> {
    if value.is_finite() {
        Ok(value)
    } else {
        Err(E::custom("money value is not finite"))
    }
}

fn checked_nonnegative<E: serde::de::Error>(value: f64) -> std::result::Result<f64, E> {
    let value = checked_finite(value)?;
    if value >= 0.0 {
        Ok(value)
    } else {
        Err(E::custom("money value cannot be negative"))
    }
}

fn de_finite<'de, D>(deserializer: D) -> std::result::Result<f64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    checked_finite(f64::deserialize(deserializer)?)
}

fn de_nonnegative_finite<'de, D>(deserializer: D) -> std::result::Result<f64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    checked_nonnegative(f64::deserialize(deserializer)?)
}

fn de_opt_finite<'de, D>(deserializer: D) -> std::result::Result<Option<f64>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Option::<f64>::deserialize(deserializer)?
        .map(checked_finite)
        .transpose()
}

pub fn combine(checklist: Checklist, usage: UsageResponse) -> Result<DeepInfraSnapshot> {
    let month = usage
        .months
        .into_iter()
        .max_by(|left, right| left.period.cmp(&right.period))
        .ok_or_else(|| AppError::Schema("deepinfra usage response carried no months".into()))?;
    if !valid_period(&month.period) {
        return Err(AppError::Schema(
            "deepinfra usage response carried an invalid period".into(),
        ));
    }
    if !month.total_cost.is_finite() || month.total_cost < 0.0 {
        return Err(AppError::Schema(
            "deepinfra usage response carried an invalid total_cost".into(),
        ));
    }

    Ok(DeepInfraSnapshot {
        balance: -checklist.stripe_balance - checklist.recent,
        monthly_spend: month.total_cost / 100.0,
        monthly_limit: checklist.limit.filter(|limit| *limit >= 0.0),
        period: month.period,
    })
}

fn valid_period(period: &str) -> bool {
    let Some((year, month)) = period.split_once('.') else {
        return false;
    };
    year.len() == 4
        && year.bytes().all(|byte| byte.is_ascii_digit())
        && month.len() == 2
        && month.bytes().all(|byte| byte.is_ascii_digit())
        && month
            .parse::<u8>()
            .is_ok_and(|month| (1..=12).contains(&month))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn checklist() -> Checklist {
        Checklist {
            stripe_balance: -5.0,
            recent: 2.08,
            limit: None,
        }
    }

    fn usage(total_cost: f64) -> UsageResponse {
        UsageResponse {
            months: vec![UsageMonth {
                period: "2026.09".into(),
                total_cost,
            }],
        }
    }

    #[test]
    fn combines_prepaid_balance_and_cent_usage() {
        let snapshot = combine(checklist(), usage(208.0)).unwrap();
        assert!((snapshot.balance - 2.92).abs() < 1e-9);
        assert!((snapshot.monthly_spend - 2.08).abs() < 1e-9);
        assert_eq!(snapshot.period, "2026.09");
        assert_eq!(snapshot.monthly_limit, None);
    }

    #[test]
    fn normalizes_negative_limit_to_unlimited() {
        let snapshot = combine(
            Checklist {
                limit: Some(-1.0),
                ..checklist()
            },
            usage(0.0),
        )
        .unwrap();
        assert_eq!(snapshot.monthly_limit, None);
    }

    #[test]
    fn rejects_missing_month_and_negative_cost() {
        assert!(
            combine(checklist(), UsageResponse { months: vec![] })
                .unwrap_err()
                .to_string()
                .contains("no months")
        );
        assert!(combine(checklist(), usage(-1.0)).is_err());
    }

    #[test]
    fn selects_the_latest_period_and_accepts_fractional_cents() {
        let snapshot = combine(
            checklist(),
            UsageResponse {
                months: vec![
                    UsageMonth {
                        period: "2026.08".into(),
                        total_cost: 500.0,
                    },
                    UsageMonth {
                        period: "2026.09".into(),
                        total_cost: 208.5,
                    },
                ],
            },
        )
        .unwrap();
        assert!((snapshot.monthly_spend - 2.085).abs() < 1e-9);
        assert_eq!(snapshot.period, "2026.09");
    }

    #[test]
    fn rejects_invalid_money() {
        for raw in [
            r#"{"stripe_balance":1e400,"recent":0,"limit":null}"#,
            r#"{"stripe_balance":0,"recent":-1,"limit":null}"#,
            r#"{"stripe_balance":0,"recent":0,"limit":1e400}"#,
        ] {
            assert!(serde_json::from_str::<Checklist>(raw).is_err(), "{raw}");
        }
        assert!(
            serde_json::from_str::<UsageResponse>(
                r#"{"months":[{"period":"2026.09","total_cost":-1}]}"#
            )
            .is_err()
        );
    }
}
