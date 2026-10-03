//! Fetch DeepSeek usage from `/user/balance`.

use std::time::Duration;

use crate::cache::{Cache, acquire_lock_async};
use crate::error::{AppError, Result};
use crate::usage::DeepseekSnapshot;

use super::types::BalanceResponse;

pub const BASE_URL: &str = "https://api.deepseek.com";
const HTTP_TIMEOUT: Duration = Duration::from_secs(10);
const LOCK_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Clone)]
pub struct Endpoints {
    pub balance: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Self {
            balance: format!("{BASE_URL}/user/balance"),
        }
    }
}

/// This vendor's [`Outcome`](crate::outcome::Outcome) — the shared shape,
/// specialised to its snapshot.
pub type FetchOutcome = crate::outcome::Outcome<DeepseekSnapshot>;

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
    // Corrupt fresh cache: fall through to live fetch rather than return a
    // fabricated zero balance.

    match fetch_live(client, &endpoints.balance, api_key).await {
        Ok(snap) => {
            let bytes = serde_json::to_vec(&snap_to_json(&snap))?;
            cache.write_payload(&bytes)?;
            Ok(crate::outcome::Outcome::fresh(snap))
        }
        Err(e) if e.is_transient() => fallback_silent(cache, e),
        Err(AppError::Http { status, body }) => {
            cache.mark_stale();
            let last_error = Some(cache.write_last_error(status, &body));
            fallback_with_error(cache, last_error, AppError::Http { status, body })
        }
        Err(e) => {
            cache.mark_stale();
            let last_error = Some(cache.write_last_error(0, &e.to_string()));
            fallback_with_error(cache, last_error, e)
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
    let snap = parse_cache(&bytes)?;
    Ok(crate::outcome::Outcome::cached(snap, cache, stale))
}

/// Cached money is required, not optional: a truncated or half-written payload
/// must be refetched rather than rendered as a $0.00 balance.
fn parse_cache(bytes: &[u8]) -> Result<DeepseekSnapshot> {
    let v: serde_json::Value = serde_json::from_slice(bytes)?;
    let money = |name: &str| -> Result<f64> {
        let n = v[name]
            .as_f64()
            .ok_or_else(|| AppError::Schema(format!("deepseek cache missing '{name}'")))?;
        if n.is_finite() {
            Ok(n)
        } else {
            Err(AppError::Schema(format!(
                "deepseek cache '{name}' is not finite"
            )))
        }
    };
    let currency = v["currency"]
        .as_str()
        .ok_or_else(|| AppError::Schema("deepseek cache missing 'currency'".into()))?;
    if !matches!(currency, "USD" | "CNY") {
        return Err(AppError::Schema(format!(
            "deepseek cache has unsupported currency {currency:?}"
        )));
    }
    Ok(DeepseekSnapshot {
        is_available: v["is_available"]
            .as_bool()
            .ok_or_else(|| AppError::Schema("deepseek cache missing 'is_available'".into()))?,
        balance: money("balance")?,
        granted: money("granted")?,
        topped_up: money("topped_up")?,
        currency: currency.to_string(),
    })
}

fn snap_to_json(snap: &DeepseekSnapshot) -> serde_json::Value {
    serde_json::json!({
        "is_available": snap.is_available,
        "balance": snap.balance,
        "granted": snap.granted,
        "topped_up": snap.topped_up,
        "currency": snap.currency,
    })
}

async fn fetch_live(
    client: &reqwest::Client,
    url: &str,
    api_key: &str,
) -> Result<DeepseekSnapshot> {
    let resp = tokio::time::timeout(
        HTTP_TIMEOUT,
        client
            .get(url)
            .header("Authorization", format!("Bearer {api_key}"))
            .header("Accept", "application/json")
            .send(),
    )
    .await
    .map_err(|_| AppError::Transport(format!("deepseek timeout: {url}")))??;

    let status = resp.status();
    let bytes = crate::vendor::read_body_capped(resp, crate::vendor::MAX_BODY_BYTES).await?;

    if !status.is_success() {
        let body = String::from_utf8_lossy(&bytes).chars().take(200).collect();
        return Err(AppError::Http {
            status: status.as_u16(),
            body,
        });
    }

    let r: BalanceResponse = serde_json::from_slice(&bytes)
        .map_err(|e| AppError::Schema(format!("deepseek balance response: {e}")))?;
    r.into_snapshot()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn cache_fixture() -> (TempDir, Cache) {
        let td = TempDir::new().unwrap();
        let cache = Cache::at(td.path().join("deepseek"));
        cache.ensure_dir().unwrap();
        (td, cache)
    }

    #[test]
    fn cached_unknown_currency_is_rejected_like_a_live_response() {
        let cache = serde_json::json!({
            "is_available": true,
            "balance": 10.0,
            "granted": 10.0,
            "topped_up": 0.0,
            "currency": "EUR"
        });
        let error = parse_cache(cache.to_string().as_bytes()).unwrap_err();
        assert!(
            error.to_string().contains("unsupported currency"),
            "{error}"
        );
    }

    #[tokio::test]
    async fn live_200_returns_snapshot() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/user/balance")
            .with_status(200)
            .with_body(r#"{
                "is_available": true,
                "balance_infos": [
                    {"currency": "USD", "total_balance": "5.00", "granted_balance": "5.00", "topped_up_balance": "0.00"}
                ]
            }"#)
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let client = reqwest::Client::new();
        let endpoints = Endpoints {
            balance: format!("{}/user/balance", server.url()),
        };
        let out = fetch_snapshot(
            &client,
            "sk-test",
            &cache,
            &endpoints,
            Duration::from_secs(0),
        )
        .await
        .unwrap();
        assert!(out.snapshot.is_available);
        assert!((out.snapshot.balance - 5.0).abs() < 1e-9);
        assert_eq!(out.snapshot.currency, "USD");
        assert!(!out.stale);
    }

    /// The whole bug in one path. `reuse_cache` already puts the *redacted*
    /// message in the outcome — it reads it back from disk — and
    /// `fallback_with_error` then overwrote it with a pair built from the raw
    /// body. So the run that hit the `401` displayed the body and every run
    /// after it displayed the neutral message.
    ///
    /// Written against Deepseek because it is the smallest harness that reaches
    /// the shared path; the same two lines were repeated in five other vendors.
    #[tokio::test]
    async fn a_401_body_does_not_reach_the_outcome_when_a_cache_is_warm() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/user/balance")
            .with_status(401)
            .with_body("PANCEA user@example.test <credential>&token")
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let warm = serde_json::json!({
            "is_available": true,
            "balance": 5.0,
            "granted": 5.0,
            "topped_up": 0.0,
            "currency": "USD"
        });
        cache.write_payload(warm.to_string().as_bytes()).unwrap();

        let endpoints = Endpoints {
            balance: format!("{}/user/balance", server.url()),
        };
        let out = fetch_snapshot(
            &reqwest::Client::new(),
            "sk-test",
            &cache,
            &endpoints,
            Duration::from_secs(0),
        )
        .await
        .unwrap();

        let (code, msg) = out.last_error.expect("the 401 must still be reported");
        assert_eq!(code, 401);
        assert_eq!(msg, crate::error::AUTH_FAILURE_MESSAGE);
        assert!(!msg.contains("PANCEA"), "{msg}");
        assert!(!msg.contains("<credential>"), "{msg}");
        assert!(out.stale);
    }

    #[tokio::test]
    async fn http_401_falls_back_to_cache() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/user/balance")
            .with_status(401)
            .with_body(r#"{"error": "invalid api key"}"#)
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let seed = serde_json::json!({
            "is_available": true,
            "balance": 3.0,
            "granted": 3.0,
            "topped_up": 0.0,
            "currency": "USD"
        });
        cache.write_payload(seed.to_string().as_bytes()).unwrap();

        let client = reqwest::Client::new();
        let endpoints = Endpoints {
            balance: format!("{}/user/balance", server.url()),
        };
        let out = fetch_snapshot(
            &client,
            "bad-key",
            &cache,
            &endpoints,
            Duration::from_secs(0),
        )
        .await
        .unwrap();
        assert!(out.stale);
        assert!((out.snapshot.balance - 3.0).abs() < 1e-9);
        assert_eq!(out.last_error.as_ref().map(|(c, _)| *c), Some(401));
    }
}
