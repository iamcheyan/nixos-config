//! DeepInfra fetch for current prepaid balance and monthly usage.

use std::time::Duration;

use crate::cache::{Cache, acquire_lock_async};
use crate::error::{AppError, Result};
use crate::usage::DeepInfraSnapshot;

use super::types::{Checklist, UsageResponse, combine};

pub const BASE_URL: &str = "https://api.deepinfra.com";
const HTTP_TIMEOUT: Duration = Duration::from_secs(20);
const LOCK_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Clone)]
pub struct Endpoints {
    pub checklist: String,
    pub usage: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Self {
            checklist: format!("{BASE_URL}/payment/checklist"),
            usage: format!("{BASE_URL}/payment/usage?from=current"),
        }
    }
}

pub type FetchOutcome = crate::outcome::Outcome<DeepInfraSnapshot>;

pub async fn fetch_snapshot(
    client: &reqwest::Client,
    api_key: &str,
    cache: &Cache,
    endpoints: &Endpoints,
    cache_ttl: Duration,
) -> Result<FetchOutcome> {
    cache.ensure_dir()?;
    let _lock = acquire_lock_async(&cache.lock_path(), LOCK_TIMEOUT).await?;

    if let Some(bytes) = cache.fresh_payload(cache_ttl)?
        && let Ok(outcome) = reuse_cache(bytes, cache, false)
    {
        return Ok(outcome);
    }

    match fetch_live(client, endpoints, api_key)
        .await
        .and_then(|(checklist, usage)| combine(checklist, usage))
    {
        Ok(snapshot) => {
            let bytes = serde_json::to_vec(&serde_json::json!({
                "snapshot": serde_repr(&snapshot),
            }))?;
            cache.write_payload(&bytes)?;
            Ok(crate::outcome::Outcome::fresh(snapshot))
        }
        Err(error) if error.is_transient() => fallback_silent(cache, error),
        Err(AppError::Http { status, body }) => {
            cache.mark_stale();
            let last_error = Some(cache.write_last_error(status, &body));
            fallback_with_error(cache, last_error, AppError::Http { status, body })
        }
        Err(error) => {
            cache.mark_stale();
            let last_error = Some(cache.write_last_error(0, &error.to_string()));
            fallback_with_error(cache, last_error, error)
        }
    }
}

fn fallback_silent(cache: &Cache, original: AppError) -> Result<FetchOutcome> {
    crate::outcome::fallback(cache, None, original, parse_cache)
}

fn fallback_with_error(
    cache: &Cache,
    last_error: Option<(u16, String)>,
    original: AppError,
) -> Result<FetchOutcome> {
    crate::outcome::fallback(cache, last_error, original, parse_cache)
}

fn reuse_cache(bytes: Vec<u8>, cache: &Cache, stale: bool) -> Result<FetchOutcome> {
    let snapshot = parse_cache(&bytes)?;
    Ok(crate::outcome::Outcome::cached(snapshot, cache, stale))
}

fn parse_cache(bytes: &[u8]) -> Result<DeepInfraSnapshot> {
    let value: serde_json::Value = serde_json::from_slice(bytes)?;
    let snapshot = value
        .get("snapshot")
        .ok_or_else(|| AppError::Schema("deepinfra cache missing 'snapshot' field".into()))?;
    let money = |name: &str, nonnegative: bool| -> Result<f64> {
        let number = snapshot
            .get(name)
            .and_then(serde_json::Value::as_f64)
            .ok_or_else(|| AppError::Schema(format!("deepinfra cache missing '{name}'")))?;
        if number.is_finite() && (!nonnegative || number >= 0.0) {
            Ok(number)
        } else {
            Err(AppError::Schema(format!(
                "deepinfra cache '{name}' is outside its valid range"
            )))
        }
    };
    let monthly_limit = match snapshot.get("monthly_limit") {
        None | Some(serde_json::Value::Null) => None,
        Some(_) => Some(money("monthly_limit", true)?),
    };
    let period = snapshot
        .get("period")
        .and_then(serde_json::Value::as_str)
        .filter(|period| !period.trim().is_empty())
        .ok_or_else(|| AppError::Schema("deepinfra cache missing 'period'".into()))?;

    Ok(DeepInfraSnapshot {
        balance: money("balance", false)?,
        monthly_spend: money("monthly_spend", true)?,
        monthly_limit,
        period: period.to_string(),
    })
}

fn serde_repr(snapshot: &DeepInfraSnapshot) -> serde_json::Value {
    serde_json::json!({
        "balance": snapshot.balance,
        "monthly_spend": snapshot.monthly_spend,
        "monthly_limit": snapshot.monthly_limit,
        "period": snapshot.period,
    })
}

async fn fetch_live(
    client: &reqwest::Client,
    endpoints: &Endpoints,
    api_key: &str,
) -> Result<(Checklist, UsageResponse)> {
    let checklist = fetch_one::<Checklist>(client, &endpoints.checklist, api_key);
    let usage = fetch_one::<UsageResponse>(client, &endpoints.usage, api_key);
    let (checklist, usage) = tokio::join!(checklist, usage);
    Ok((checklist?, usage?))
}

async fn fetch_one<T: for<'de> serde::Deserialize<'de>>(
    client: &reqwest::Client,
    url: &str,
    api_key: &str,
) -> Result<T> {
    let response = tokio::time::timeout(HTTP_TIMEOUT, client.get(url).bearer_auth(api_key).send())
        .await
        .map_err(|_| AppError::Transport(format!("deepinfra timeout: {url}")))??;
    let status = response.status();
    let bytes = crate::vendor::read_body_capped(response, crate::vendor::MAX_BODY_BYTES).await?;

    if !status.is_success() {
        let body = String::from_utf8_lossy(&bytes).chars().take(200).collect();
        return Err(AppError::Http {
            status: status.as_u16(),
            body,
        });
    }

    serde_json::from_slice(&bytes)
        .map_err(|error| AppError::Schema(format!("deepinfra response: {error}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn cache_fixture() -> (TempDir, Cache) {
        let directory = TempDir::new().unwrap();
        let cache = Cache::at(directory.path().join("deepinfra"));
        cache.ensure_dir().unwrap();
        (directory, cache)
    }

    #[tokio::test]
    async fn live_fetch_combines_balance_and_usage() {
        let mut server = mockito::Server::new_async().await;
        let checklist = server
            .mock("GET", "/payment/checklist")
            .match_header("authorization", "Bearer test-key")
            .with_status(200)
            .with_body(r#"{"stripe_balance":-5.0,"recent":2.08,"limit":null}"#)
            .create_async()
            .await;
        let usage = server
            .mock("GET", "/payment/usage?from=current")
            .match_header("authorization", "Bearer test-key")
            .with_status(200)
            .with_body(r#"{"months":[{"period":"2026.09","total_cost":208}]}"#)
            .create_async()
            .await;

        let (_directory, cache) = cache_fixture();
        let endpoints = Endpoints {
            checklist: format!("{}/payment/checklist", server.url()),
            usage: format!("{}/payment/usage?from=current", server.url()),
        };
        let outcome = fetch_snapshot(
            &reqwest::Client::new(),
            "test-key",
            &cache,
            &endpoints,
            Duration::ZERO,
        )
        .await
        .unwrap();

        checklist.assert_async().await;
        usage.assert_async().await;
        assert!((outcome.snapshot.balance - 2.92).abs() < 1e-9);
        assert!((outcome.snapshot.monthly_spend - 2.08).abs() < 1e-9);
        assert!(!outcome.stale);
    }

    #[tokio::test]
    async fn an_http_error_falls_back_to_cache() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/payment/checklist")
            .with_status(401)
            .with_body(r#"{"detail":"unauthorized"}"#)
            .create_async()
            .await;

        let (_directory, cache) = cache_fixture();
        cache
            .write_payload(
                &serde_json::to_vec(&serde_json::json!({
                    "snapshot": {
                        "balance": 2.92,
                        "monthly_spend": 2.08,
                        "monthly_limit": null,
                        "period": "2026.09"
                    }
                }))
                .unwrap(),
            )
            .unwrap();
        let endpoints = Endpoints {
            checklist: format!("{}/payment/checklist", server.url()),
            usage: format!("{}/payment/usage?from=current", server.url()),
        };
        let outcome = fetch_snapshot(
            &reqwest::Client::new(),
            "revoked-key",
            &cache,
            &endpoints,
            Duration::ZERO,
        )
        .await
        .unwrap();

        assert!(outcome.stale);
        assert_eq!(outcome.last_error.as_ref().map(|error| error.0), Some(401));
        assert!((outcome.snapshot.balance - 2.92).abs() < 1e-9);
    }

    #[tokio::test]
    async fn fresh_cache_skips_both_endpoints() {
        let (_directory, cache) = cache_fixture();
        cache
            .write_payload(
                &serde_json::to_vec(&serde_json::json!({
                    "snapshot": {
                        "balance": 2.92,
                        "monthly_spend": 2.08,
                        "monthly_limit": null,
                        "period": "2026.09"
                    }
                }))
                .unwrap(),
            )
            .unwrap();
        let endpoints = Endpoints {
            checklist: "http://127.0.0.1:1/payment/checklist".into(),
            usage: "http://127.0.0.1:1/payment/usage?from=current".into(),
        };

        let outcome = fetch_snapshot(
            &reqwest::Client::new(),
            "test-key",
            &cache,
            &endpoints,
            Duration::from_secs(60),
        )
        .await
        .unwrap();

        assert!(!outcome.stale);
        assert!((outcome.snapshot.balance - 2.92).abs() < 1e-9);
    }
}
