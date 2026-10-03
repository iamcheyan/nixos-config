use std::fmt::Write as _;
use std::time::Duration;

use sha2::{Digest, Sha256};

use crate::cache::{Cache, acquire_lock_async};
use crate::error::{AUTH_FAILURE_MESSAGE, AppError, Result};
use crate::vendor::{MAX_BODY_BYTES, read_body_capped};

use super::types::{Usage, parse_usage};

pub const BASE_URL: &str = "https://opencode.ai/zen/go/v1/usage";

const HTTP_TIMEOUT: Duration = Duration::from_secs(10);
const LOCK_TIMEOUT: Duration = Duration::from_secs(15);
const SCHEMA_ERROR: &str = "OpenCode Go usage response schema mismatch";

#[derive(Debug, Clone)]
pub struct Endpoints {
    pub usage: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Self {
            usage: BASE_URL.to_string(),
        }
    }
}

/// This vendor's [`Outcome`](crate::outcome::Outcome) — the shared shape,
/// specialised to its snapshot.
pub type FetchOutcome = crate::outcome::Outcome<Usage>;

pub async fn fetch_snapshot(
    client: &reqwest::Client,
    api_key: &str,
    cache: &Cache,
    endpoints: &Endpoints,
    ttl: Duration,
) -> Result<FetchOutcome> {
    cache.ensure_dir()?;
    let _lock = acquire_lock_async(&cache.lock_path(), LOCK_TIMEOUT).await?;
    let target = target_key(endpoints, api_key);

    if let Some(bytes) = cache.fresh_payload(ttl)?
        && let Ok(snapshot) = parse_cache(&bytes, &target)
    {
        return Ok(crate::outcome::Outcome::cached(snapshot, cache, false));
    }

    match fetch_live(client, &endpoints.usage, api_key).await {
        Ok(snapshot) => {
            let body = serde_json::to_vec(&serde_json::json!({
                "target": target,
                "response": usage_repr(&snapshot),
            }))?;
            cache.write_payload(&body)?;
            Ok(crate::outcome::Outcome::fresh(snapshot))
        }
        Err(error @ AppError::Transport(_)) => fallback_or_error(cache, None, &target, error),
        Err(AppError::Http { status, .. }) => {
            let message = status_message(status).to_string();
            cache.mark_stale();
            cache.write_last_error(status, &message);
            fallback_or_error(
                cache,
                Some((status, message.clone())),
                &target,
                AppError::Http {
                    status,
                    body: message,
                },
            )
        }
        Err(AppError::Schema(_)) => {
            let message = SCHEMA_ERROR.to_string();
            cache.mark_stale();
            cache.write_last_error(0, &message);
            fallback_or_error(
                cache,
                Some((0, message.clone())),
                &target,
                AppError::Schema(message),
            )
        }
        Err(error) => fallback_or_error(cache, None, &target, error),
    }
}

async fn fetch_live(client: &reqwest::Client, url: &str, api_key: &str) -> Result<Usage> {
    let response = tokio::time::timeout(
        HTTP_TIMEOUT,
        client
            .get(url)
            .bearer_auth(api_key)
            .header(reqwest::header::ACCEPT, "application/json")
            .send(),
    )
    .await
    .map_err(|_| AppError::Transport("OpenCode Go request timed out".to_string()))??;

    let status = response.status();
    let body = read_body_capped(response, MAX_BODY_BYTES).await?;
    if !status.is_success() {
        return Err(AppError::Http {
            status: status.as_u16(),
            body: status_message(status.as_u16()).to_string(),
        });
    }

    let snapshot = parse_payload(&body)?;
    Ok(snapshot)
}

/// Stable, non-secret identity for the endpoint and account selected by the
/// API key. The usage endpoint resolves the key to a user/workspace, so cache
/// reuse must fail closed when either input changes.
fn target_key(endpoints: &Endpoints, api_key: &str) -> String {
    let digest = Sha256::digest(api_key.as_bytes());
    let mut fingerprint = String::with_capacity(digest.len() * 2);
    for byte in digest {
        let _ = write!(fingerprint, "{byte:02x}");
    }
    format!("{}|key:{fingerprint}", endpoints.usage)
}

fn usage_repr(usage: &Usage) -> serde_json::Value {
    let window = |window: &super::types::Window| {
        serde_json::json!({
            "status": window.status,
            "percent": window.percent,
            "resetsAt": window.resets_at.to_rfc3339(),
        })
    };
    let mut windows = serde_json::Map::new();
    for (name, value) in [
        ("rolling", usage.rolling.as_ref()),
        ("weekly", usage.weekly.as_ref()),
        ("monthly", usage.monthly.as_ref()),
    ] {
        if let Some(value) = value {
            windows.insert(name.into(), window(value));
        }
    }
    serde_json::json!({ "usage": windows })
}

fn parse_payload(body: &[u8]) -> Result<Usage> {
    let value: serde_json::Value =
        serde_json::from_slice(body).map_err(|_| AppError::Schema(SCHEMA_ERROR.to_string()))?;
    parse_usage(&value).map_err(|_| AppError::Schema(SCHEMA_ERROR.to_string()))
}

fn status_message(status: u16) -> &'static str {
    match status {
        401 | 403 => AUTH_FAILURE_MESSAGE,
        429 => "OpenCode Go request was rate limited",
        500..=599 => "OpenCode Go service is temporarily unavailable",
        _ => "OpenCode Go request failed",
    }
}

fn fallback_or_error(
    cache: &Cache,
    last_error: Option<(u16, String)>,
    target: &str,
    error: AppError,
) -> Result<FetchOutcome> {
    crate::outcome::fallback(cache, last_error, error, |body| parse_cache(body, target))
}

fn parse_cache(body: &[u8], target: &str) -> Result<Usage> {
    let value: serde_json::Value = serde_json::from_slice(body)
        .map_err(|_| AppError::Schema("OpenCode Go cache is invalid".into()))?;
    if value.get("target").and_then(serde_json::Value::as_str) != Some(target) {
        return Err(AppError::Schema(
            "OpenCode Go cache belongs to a different account".into(),
        ));
    }
    let response = value
        .get("response")
        .ok_or_else(|| AppError::Schema("OpenCode Go cache is missing its response".into()))?;
    parse_usage(response).map_err(|_| AppError::Schema("OpenCode Go cache is invalid".into()))
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use tempfile::TempDir;

    use super::*;
    use crate::cache::Cache;

    const GOOD_BODY: &str = r#"{
        "usage": {
            "rolling": {"status":"ok","percent":12.3,"resetsAt":"2026-08-16T20:00:00Z"},
            "weekly": {"status":"ok","percent":45.6,"resetsAt":"2026-08-20T00:00:00Z"},
            "monthly": {"status":"ok","percent":78.9,"resetsAt":"2026-09-01T00:00:00Z"}
        }
    }"#;

    fn cache_fixture() -> (TempDir, Cache) {
        let dir = TempDir::new().expect("temporary cache directory");
        let cache = Cache::at(dir.path().join("opencode-go"));
        cache.ensure_dir().expect("cache directory");
        (dir, cache)
    }

    #[tokio::test]
    async fn fetches_usage_with_bearer_and_accept_headers() {
        let mut server = mockito::Server::new_async().await;
        let mock = server
            .mock("GET", "/zen/go/v1/usage")
            .match_header("authorization", "Bearer test-key")
            .match_header("accept", "application/json")
            .with_status(200)
            .with_body(GOOD_BODY)
            .create_async()
            .await;
        let (_dir, cache) = cache_fixture();
        let endpoints = Endpoints {
            usage: format!("{}/zen/go/v1/usage", server.url()),
        };

        let output = fetch_snapshot(
            &reqwest::Client::new(),
            "test-key",
            &cache,
            &endpoints,
            Duration::from_secs(60),
        )
        .await
        .expect("successful usage response");

        assert_eq!(output.snapshot.rolling.expect("rolling").percent, 12.3);
        assert!(!output.stale);
        assert!(output.last_error.is_none());
        mock.assert_async().await;
    }

    #[tokio::test]
    async fn unauthorized_without_cache_returns_redacted_error() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/usage")
            .with_status(401)
            .with_body("secret-token should never be returned")
            .create_async()
            .await;
        let (_dir, cache) = cache_fixture();
        let endpoints = Endpoints {
            usage: format!("{}/usage", server.url()),
        };

        let error = fetch_snapshot(
            &reqwest::Client::new(),
            "test-key",
            &cache,
            &endpoints,
            Duration::ZERO,
        )
        .await
        .expect_err("401 without a cache must fail");

        let rendered = error.to_string();
        assert!(rendered.contains("401"));
        assert!(!rendered.contains("secret-token"));
        assert!(!rendered.contains("test-key"));
    }

    #[tokio::test]
    async fn schema_error_does_not_include_response_body() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/usage")
            .with_status(200)
            .with_body(
                r#"{"error":"schema-secret", "usage":{"rolling":{"status":"ok","percent":"schema-secret","resetsAt":"2026-08-16T20:00:00Z"}}}"#,
            )
            .create_async()
            .await;
        let (_dir, cache) = cache_fixture();
        let endpoints = Endpoints {
            usage: format!("{}/usage", server.url()),
        };

        let error = fetch_snapshot(
            &reqwest::Client::new(),
            "test-key",
            &cache,
            &endpoints,
            Duration::ZERO,
        )
        .await
        .expect_err("schema mismatch must fail");

        let rendered = error.to_string();
        assert!(rendered.to_ascii_lowercase().contains("schema"));
        assert!(!rendered.contains("schema-secret"));
        assert!(!rendered.contains("test-key"));
    }

    #[tokio::test]
    async fn status_errors_are_redacted_for_403_429_and_server_errors() {
        for status in [403, 429, 500, 503] {
            let mut server = mockito::Server::new_async().await;
            server
                .mock("GET", "/usage")
                .with_status(status)
                .with_body("body-secret")
                .create_async()
                .await;
            let (_dir, cache) = cache_fixture();
            let endpoints = Endpoints {
                usage: format!("{}/usage", server.url()),
            };

            let error = fetch_snapshot(
                &reqwest::Client::new(),
                "test-key",
                &cache,
                &endpoints,
                Duration::ZERO,
            )
            .await
            .expect_err("status without cache must fail");
            let rendered = error.to_string();
            assert!(rendered.contains(&status.to_string()));
            assert!(!rendered.contains("body-secret"));
            assert!(!rendered.contains("test-key"));
        }
    }

    #[tokio::test]
    async fn changing_api_keys_never_reuses_another_accounts_fresh_cache() {
        let mut server = mockito::Server::new_async().await;
        let first = server
            .mock("GET", "/usage")
            .match_header("authorization", "Bearer first-key")
            .with_status(200)
            .with_body(GOOD_BODY)
            .expect(1)
            .create_async()
            .await;
        let second_body = GOOD_BODY.replace("12.3", "91.2");
        let second = server
            .mock("GET", "/usage")
            .match_header("authorization", "Bearer second-key")
            .with_status(200)
            .with_body(second_body)
            .expect(1)
            .create_async()
            .await;
        let (_dir, cache) = cache_fixture();
        let endpoints = Endpoints {
            usage: format!("{}/usage", server.url()),
        };

        fetch_snapshot(
            &reqwest::Client::new(),
            "first-key",
            &cache,
            &endpoints,
            Duration::from_secs(60),
        )
        .await
        .unwrap();
        let second_output = fetch_snapshot(
            &reqwest::Client::new(),
            "second-key",
            &cache,
            &endpoints,
            Duration::from_secs(60),
        )
        .await
        .unwrap();

        assert_eq!(second_output.snapshot.rolling.unwrap().percent, 91.2);
        let persisted = String::from_utf8(cache.maybe_payload().unwrap().unwrap()).unwrap();
        assert!(!persisted.contains("first-key"));
        assert!(!persisted.contains("second-key"));
        first.assert_async().await;
        second.assert_async().await;
    }

    #[tokio::test]
    async fn changing_api_keys_rejects_another_accounts_stale_fallback() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/usage")
            .match_header("authorization", "Bearer first-key")
            .with_status(200)
            .with_body(GOOD_BODY)
            .create_async()
            .await;
        server
            .mock("GET", "/usage")
            .match_header("authorization", "Bearer second-key")
            .with_status(503)
            .create_async()
            .await;
        let (_dir, cache) = cache_fixture();
        let endpoints = Endpoints {
            usage: format!("{}/usage", server.url()),
        };
        fetch_snapshot(
            &reqwest::Client::new(),
            "first-key",
            &cache,
            &endpoints,
            Duration::ZERO,
        )
        .await
        .unwrap();

        let error = fetch_snapshot(
            &reqwest::Client::new(),
            "second-key",
            &cache,
            &endpoints,
            Duration::ZERO,
        )
        .await
        .expect_err("a cache for another endpoint/account must not be served");
        assert!(matches!(error, AppError::Http { status: 503, .. }));
    }
}
