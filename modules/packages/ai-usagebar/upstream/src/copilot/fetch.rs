//! GitHub Copilot quota fetch with cache isolation and no credential storage.

use std::fmt::Write as _;
use std::time::Duration;

use sha2::{Digest, Sha256};

use crate::cache::{Cache, acquire_lock_async};
use crate::error::{AppError, Result};
use crate::vendor::{MAX_BODY_BYTES, read_body_capped};

use super::types::{Response, Snapshot, to_snapshot};

pub const USER_URL: &str = "https://api.github.com/copilot_internal/user";
const HTTP_TIMEOUT: Duration = Duration::from_secs(10);
const LOCK_TIMEOUT: Duration = Duration::from_secs(15);
const SCHEMA_ERROR: &str = "GitHub Copilot quota response schema mismatch";

#[derive(Debug, Clone)]
pub struct Endpoints {
    pub user: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Self {
            user: USER_URL.to_string(),
        }
    }
}

pub type FetchOutcome = crate::outcome::Outcome<Snapshot>;

pub async fn fetch_snapshot(
    client: &reqwest::Client,
    token: &str,
    cache: &Cache,
    endpoints: &Endpoints,
    ttl: Duration,
) -> Result<FetchOutcome> {
    cache.ensure_dir()?;
    let _lock = acquire_lock_async(&cache.lock_path(), LOCK_TIMEOUT).await?;
    let target = target_key(endpoints, token);
    if let Some(bytes) = cache.fresh_payload(ttl)?
        && let Ok(snapshot) = parse_cache(&bytes, &target)
    {
        return Ok(crate::outcome::Outcome::cached(snapshot, cache, false));
    }
    match fetch_live(client, token, endpoints).await {
        Ok(snapshot) => {
            let bytes = serde_json::to_vec(&serde_json::json!({
                "target": target,
                "snapshot": snapshot,
            }))?;
            cache.write_payload(&bytes)?;
            Ok(crate::outcome::Outcome::fresh(snapshot))
        }
        Err(error @ AppError::Transport(_)) => fallback_or_error(cache, None, &target, error),
        Err(AppError::Http { status, .. }) => {
            let message = status_message(status).to_string();
            cache.mark_stale();
            let diagnostic = cache.write_last_error(status, &message);
            fallback_or_error(
                cache,
                Some(diagnostic),
                &target,
                AppError::Http {
                    status,
                    body: message,
                },
            )
        }
        Err(AppError::Schema(_)) => {
            cache.mark_stale();
            let diagnostic = cache.write_last_error(0, SCHEMA_ERROR);
            fallback_or_error(
                cache,
                Some(diagnostic),
                &target,
                AppError::Schema(SCHEMA_ERROR.to_string()),
            )
        }
        Err(error) => fallback_or_error(cache, None, &target, error),
    }
}

async fn fetch_live(
    client: &reqwest::Client,
    token: &str,
    endpoints: &Endpoints,
) -> Result<Snapshot> {
    let response = tokio::time::timeout(
        HTTP_TIMEOUT,
        client
            .get(&endpoints.user)
            .header(reqwest::header::AUTHORIZATION, format!("token {token}"))
            .header(reqwest::header::ACCEPT, "application/json")
            .header("Editor-Version", "vscode/1.96.2")
            .header("Editor-Plugin-Version", "copilot-chat/0.26.7")
            .header(reqwest::header::USER_AGENT, "GitHubCopilotChat/0.26.7")
            .header("X-GitHub-Api-Version", "2025-04-01")
            .send(),
    )
    .await
    .map_err(|_| AppError::Transport("GitHub Copilot request timed out".into()))??;
    let status = response.status();
    let bytes = read_body_capped(response, MAX_BODY_BYTES).await?;
    if !status.is_success() {
        return Err(AppError::Http {
            status: status.as_u16(),
            body: status_message(status.as_u16()).into(),
        });
    }
    let response: Response =
        serde_json::from_slice(&bytes).map_err(|_| AppError::Schema(SCHEMA_ERROR.to_string()))?;
    to_snapshot(response)
}

/// Bind cache reuse to both endpoint and token without writing either raw
/// credential or the full response to disk.
fn target_key(endpoints: &Endpoints, token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    let mut fingerprint = String::with_capacity(digest.len() * 2);
    for byte in digest {
        let _ = write!(fingerprint, "{byte:02x}");
    }
    format!("{}|token:{fingerprint}", endpoints.user)
}

fn parse_cache(bytes: &[u8], target: &str) -> Result<Snapshot> {
    let value: serde_json::Value = serde_json::from_slice(bytes)
        .map_err(|_| AppError::Schema("GitHub Copilot cache is invalid".into()))?;
    if value.get("target").and_then(serde_json::Value::as_str) != Some(target) {
        return Err(AppError::Schema(
            "GitHub Copilot cache belongs to a different account".into(),
        ));
    }
    serde_json::from_value(
        value.get("snapshot").cloned().ok_or_else(|| {
            AppError::Schema("GitHub Copilot cache is missing its snapshot".into())
        })?,
    )
    .map_err(|_| AppError::Schema("GitHub Copilot cache has an invalid snapshot".into()))
}

fn fallback_or_error(
    cache: &Cache,
    diagnostic: Option<(u16, String)>,
    target: &str,
    error: AppError,
) -> Result<FetchOutcome> {
    crate::outcome::fallback(cache, diagnostic, error, |bytes| parse_cache(bytes, target))
}

fn status_message(status: u16) -> &'static str {
    match status {
        401 | 403 => crate::error::AUTH_FAILURE_MESSAGE,
        429 => "GitHub Copilot rate limited the quota request",
        500..=599 => "GitHub Copilot quota endpoint is unavailable",
        _ => "GitHub Copilot quota request failed",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::copilot::types::Quota;

    fn cache_in(dir: &std::path::Path) -> Cache {
        Cache::at(dir.join("copilot"))
    }

    #[tokio::test]
    async fn requests_vs_code_endpoint_with_only_copilot_token_and_normalizes_quotas() {
        let mut server = mockito::Server::new_async().await;
        let request = server
            .mock("GET", "/copilot_internal/user")
            .expect(1)
            .match_header("authorization", "token mock-oauth-token")
            .match_header("accept", "application/json")
            .match_header("editor-version", "vscode/1.96.2")
            .match_header("editor-plugin-version", "copilot-chat/0.26.7")
            .match_header("user-agent", "GitHubCopilotChat/0.26.7")
            .match_header("x-github-api-version", "2025-04-01")
            .with_status(200)
            .with_body(
                r#"{"copilot_plan":"pro","quota_reset_date":"2026-09-15","quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":45,"percent_remaining":15},"chat":{"entitlement":1000,"remaining":250},"completions":{"unlimited":true}}}"#,
            )
            .create_async()
            .await;
        let dir = tempfile::tempdir().unwrap();
        let cache = cache_in(dir.path());
        let endpoints = Endpoints {
            user: format!("{}/copilot_internal/user", server.url()),
        };
        let outcome = fetch_snapshot(
            &reqwest::Client::new(),
            "mock-oauth-token",
            &cache,
            &endpoints,
            Duration::from_secs(60),
        )
        .await
        .unwrap();
        let cached = fetch_snapshot(
            &reqwest::Client::new(),
            "mock-oauth-token",
            &cache,
            &endpoints,
            Duration::from_secs(60),
        )
        .await
        .unwrap();
        request.assert_async().await;
        assert_eq!(outcome.snapshot.premium.unwrap().used_pct(), 85);
        assert!(!cached.stale);
        assert!(cached.cache_age.is_some());
        assert_eq!(
            outcome.snapshot.chat.unwrap().used_and_entitlement(),
            Some((750, 1000))
        );
        assert!(outcome.snapshot.completions.unwrap().unlimited);
    }

    #[tokio::test]
    async fn rejected_refresh_uses_stale_cache_without_storing_token_or_response() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/copilot_internal/user")
            .with_status(401)
            .with_body(r#"{"message":"contains private account data"}"#)
            .create_async()
            .await;
        let dir = tempfile::tempdir().unwrap();
        let cache = cache_in(dir.path());
        let endpoints = Endpoints {
            user: format!("{}/copilot_internal/user", server.url()),
        };
        let target = target_key(&endpoints, "mock-oauth-token");
        let snapshot = Snapshot {
            plan: "pro".into(),
            premium: Some(Quota {
                percent_remaining: 80,
                entitlement: Some(300),
                remaining: Some(240),
                unlimited: false,
            }),
            chat: None,
            completions: None,
            reset_at: None,
        };
        cache
            .write_payload(
                serde_json::json!({"target": target, "snapshot": snapshot})
                    .to_string()
                    .as_bytes(),
            )
            .unwrap();

        let outcome = fetch_snapshot(
            &reqwest::Client::new(),
            "mock-oauth-token",
            &cache,
            &endpoints,
            Duration::ZERO,
        )
        .await
        .unwrap();
        assert!(outcome.stale);
        assert_eq!(outcome.last_error.unwrap().0, 401);
        assert_eq!(outcome.snapshot.premium.unwrap().used_pct(), 20);
        let cached = std::fs::read_to_string(cache.payload_path()).unwrap();
        assert!(!cached.contains("mock-oauth-token"));
        assert!(!cached.contains("private account data"));
    }

    #[tokio::test]
    async fn invalid_success_body_is_schema_error_on_a_cold_cache() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/copilot_internal/user")
            .with_status(200)
            .with_body(r#"{"quota_snapshots":{}}"#)
            .create_async()
            .await;
        let dir = tempfile::tempdir().unwrap();
        let error = fetch_snapshot(
            &reqwest::Client::new(),
            "mock-oauth-token",
            &cache_in(dir.path()),
            &Endpoints {
                user: format!("{}/copilot_internal/user", server.url()),
            },
            Duration::ZERO,
        )
        .await
        .unwrap_err();
        assert!(matches!(error, AppError::Schema(message) if message == SCHEMA_ERROR));
    }
}
