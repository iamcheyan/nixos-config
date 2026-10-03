//! Orchestrates a Kiro CLI snapshot: read kiro-cli's own cached AWS SSO OIDC
//! token (`db.rs`), refresh it if it's close to expiry (`oauth.rs` — kiro-cli's
//! own database is never written back to), persist the refreshed credential in
//! ai-usagebar's account-scoped cache, then call
//! `AmazonCodeWhispererService.GetUsageLimits` — the exact operation kiro-cli's
//! own `/usage` slash command invokes. Cache/stale/error-fallback shape
//! mirrors `cursor::fetch`.

use std::path::Path;
use std::time::Duration;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::cache::{Cache, acquire_lock_async, atomic_write};
use crate::error::{AppError, Result};
use crate::usage::KiroSnapshot;
use crate::vendor::{MAX_BODY_BYTES, read_body_capped};

use super::db::{self, KiroCredentials};
use super::oauth;
use super::types::{self, UsageLimitsResponse};

const HTTP_TIMEOUT: Duration = Duration::from_secs(10);
const REFRESH_TIMEOUT: Duration = Duration::from_secs(15);
const LOCK_TIMEOUT: Duration = Duration::from_secs(15);
const REQUEST_TARGET: &str = "AmazonCodeWhispererService.GetUsageLimits";
const OAUTH_CACHE_FILE: &str = "oauth.json";

#[derive(Debug, Clone)]
pub struct Endpoints {
    pub usage_limits: String,
    pub token: String,
}

impl Endpoints {
    /// AWS's regional convention for the public CodeWhisperer Runtime
    /// endpoint (`<service>.<region>.amazonaws.com`) — confirmed live against
    /// this account. Enterprise IAM Identity Center accounts may instead be
    /// proxied through `management.<region>.kiro.dev` (observed in kiro-cli's
    /// own request trace for the same operation); both speak the same
    /// request/response shape, so either is a config override away.
    pub fn for_region(region: &str) -> Result<Self> {
        oauth::validate_region(region)?;
        Ok(Self {
            usage_limits: format!("https://codewhisperer.{region}.amazonaws.com/"),
            token: oauth::token_endpoint(region)?,
        })
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct PersistedOAuth {
    account: String,
    access_token: String,
    refresh_token: String,
    expires_at: DateTime<Utc>,
}

/// This vendor's [`Outcome`](crate::outcome::Outcome) — the shared shape,
/// specialised to its snapshot.
pub type FetchOutcome = crate::outcome::Outcome<KiroSnapshot>;

/// Cache-aware fetch. `db_path` is kiro-cli's `data.sqlite3` — the caller
/// resolves `[kiro] db_path` (config override) vs [`db::default_db_path`],
/// the same override pattern as `cursor.db_path`.
pub async fn fetch_snapshot(
    client: &reqwest::Client,
    db_path: &Path,
    cache: &Cache,
    cache_ttl: Duration,
) -> Result<FetchOutcome> {
    fetch_snapshot_at(client, db_path, cache, cache_ttl, None, Utc::now()).await
}

/// Clock seam for cache rollover tests, mirroring `cursor::fetch::fetch_snapshot_at`.
///
/// `endpoints_override` exists only for tests: unlike every fixed-URL vendor
/// here, Kiro's real endpoint is derived from the account's own region (read
/// from `db_path`, not known until inside this function), so there is no
/// fixed default a test could point at mockito. Production always passes
/// `None` and gets `Endpoints::for_region(&creds.region)`.
async fn fetch_snapshot_at(
    client: &reqwest::Client,
    db_path: &Path,
    cache: &Cache,
    cache_ttl: Duration,
    endpoints_override: Option<&Endpoints>,
    now: DateTime<Utc>,
) -> Result<FetchOutcome> {
    cache.ensure_dir()?;
    let _lock = acquire_lock_async(&cache.lock_path(), LOCK_TIMEOUT).await?;

    // Resolve identity before accepting a cache hit — a `kiro-cli login`
    // switch mid-session must not keep serving the previous account's cache.
    let mut creds = db::read_credentials(db_path)?;

    if let Some(bytes) = cache.fresh_payload(cache_ttl)?
        && let Ok(outcome) = reuse_cache(&bytes, cache, false, &creds.account_key, now)
    {
        return Ok(outcome);
    }

    apply_persisted_oauth(cache, &mut creds)?;

    let derived;
    let endpoints = match endpoints_override {
        Some(e) => e,
        None => {
            derived = Endpoints::for_region(&creds.region)?;
            &derived
        }
    };
    match fetch_live(client, endpoints, cache, &creds, now).await {
        Ok(snap) => {
            let bytes = serde_json::to_vec(&snap_to_json(&snap, &creds.account_key))?;
            cache.write_payload(&bytes)?;
            Ok(crate::outcome::Outcome::fresh(snap))
        }
        Err(e) if e.is_transient() => fallback_silent(cache, &creds.account_key, now, e),
        Err(e) => {
            cache.mark_stale();
            if let Some((code, msg)) = error_to_pair(&e) {
                cache.write_last_error(code, &msg);
            }
            fallback_with_error(cache, &creds.account_key, now, e)
        }
    }
}

fn fallback_silent(
    cache: &Cache,
    account: &str,
    now: DateTime<Utc>,
    original: AppError,
) -> Result<FetchOutcome> {
    crate::outcome::fallback(cache, None, original, |bytes| {
        parse_cache_at(bytes, account, now)
    })
}

fn fallback_with_error(
    cache: &Cache,
    account: &str,
    now: DateTime<Utc>,
    original: AppError,
) -> Result<FetchOutcome> {
    let last_error = error_to_pair(&original);
    crate::outcome::fallback(cache, last_error, original, |bytes| {
        parse_cache_at(bytes, account, now)
    })
}

/// Never surface upstream bodies for auth failures: a 401/403 from an
/// internal Bearer-token endpoint is not guaranteed not to echo something
/// account-identifying back. Mirrors `cursor::fetch::error_to_pair`.
fn error_to_pair(e: &AppError) -> Option<(u16, String)> {
    match e {
        AppError::Http { status, .. } if matches!(status, 401 | 403) => {
            Some((*status, "Kiro CLI authentication failed".into()))
        }
        AppError::Http { status, body } => Some((*status, body.clone())),
        AppError::Credentials(msg) => Some((0, msg.clone())),
        e => Some((0, e.to_string())),
    }
}

fn reuse_cache(
    bytes: &[u8],
    cache: &Cache,
    stale: bool,
    account: &str,
    now: DateTime<Utc>,
) -> Result<FetchOutcome> {
    let snap = parse_cache_at(bytes, account, now)?;
    Ok(crate::outcome::Outcome::cached(snap, cache, stale))
}

fn parse_cache_at(bytes: &[u8], account: &str, now: DateTime<Utc>) -> Result<KiroSnapshot> {
    let v: serde_json::Value = serde_json::from_slice(bytes)?;
    if v.get("account").and_then(serde_json::Value::as_str) != Some(account) {
        return Err(AppError::Schema(
            "kiro cache belongs to a different account; refetching".into(),
        ));
    }
    let plan = v["plan"]
        .as_str()
        .filter(|plan| !plan.trim().is_empty())
        .ok_or_else(|| AppError::Schema("kiro cache: invalid plan".into()))?
        .to_string();
    let used = v["used"]
        .as_f64()
        .filter(|n| n.is_finite() && *n >= 0.0)
        .ok_or_else(|| AppError::Schema("kiro cache: invalid used".into()))?;
    let limit = v["limit"]
        .as_f64()
        .filter(|n| n.is_finite() && *n >= 0.0)
        .ok_or_else(|| AppError::Schema("kiro cache: invalid limit".into()))?;
    let reset_at = match &v["reset_at"] {
        serde_json::Value::Null => None,
        serde_json::Value::String(s) => Some(
            DateTime::parse_from_rfc3339(s)
                .map_err(|e| AppError::Schema(format!("kiro cache: invalid reset_at: {e}")))?
                .with_timezone(&Utc),
        ),
        _ => return Err(AppError::Schema("kiro cache: invalid reset_at".into())),
    };
    // Only reject a *known-past* reset — the cycle rolled over while cached.
    // A missing reset (None) is a legitimate shape, not staleness.
    if let Some(reset_at) = reset_at
        && reset_at <= now
    {
        return Err(AppError::Schema(
            "kiro cache is past its credit-cycle reset; refetching".into(),
        ));
    }
    Ok(KiroSnapshot {
        plan,
        used,
        limit,
        reset_at,
    })
}

fn snap_to_json(snap: &KiroSnapshot, account: &str) -> serde_json::Value {
    serde_json::json!({
        "account": account,
        "plan": snap.plan,
        "used": snap.used,
        "limit": snap.limit,
        "reset_at": snap.reset_at.map(|dt| dt.to_rfc3339()),
    })
}

fn oauth_cache_path(cache: &Cache) -> std::path::PathBuf {
    cache.dir().join(OAUTH_CACHE_FILE)
}

fn read_persisted_oauth(cache: &Cache, account: &str) -> Result<Option<PersistedOAuth>> {
    let path = oauth_cache_path(cache);
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(AppError::io_at(&path, e)),
    };
    let persisted: PersistedOAuth = serde_json::from_slice(&bytes).map_err(|e| {
        AppError::Credentials(format!(
            "ai-usagebar's cached Kiro credentials at {} are malformed ({e}); remove that file and try again",
            path.display()
        ))
    })?;
    if persisted.account != account {
        return Ok(None);
    }
    if persisted.access_token.trim().is_empty() || persisted.refresh_token.trim().is_empty() {
        return Err(AppError::Credentials(format!(
            "ai-usagebar's cached Kiro credentials at {} are incomplete; remove that file and try again",
            path.display()
        )));
    }
    Ok(Some(persisted))
}

fn apply_persisted_oauth(cache: &Cache, creds: &mut KiroCredentials) -> Result<()> {
    let Some(persisted) = read_persisted_oauth(cache, &creds.account_key)? else {
        return Ok(());
    };
    // Kiro may refresh its own database independently. Prefer whichever
    // account-matched credential has the later expiry.
    if persisted.expires_at > creds.expires_at {
        creds.access_token = persisted.access_token;
        creds.refresh_token = persisted.refresh_token;
        creds.expires_at = persisted.expires_at;
    }
    Ok(())
}

fn write_persisted_oauth(cache: &Cache, persisted: &PersistedOAuth) -> Result<()> {
    let path = oauth_cache_path(cache);
    let bytes = serde_json::to_vec_pretty(persisted)?;
    atomic_write(&path, &bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))
            .map_err(|e| AppError::io_at(&path, e))?;
    }
    Ok(())
}

async fn fetch_live(
    client: &reqwest::Client,
    endpoints: &Endpoints,
    cache: &Cache,
    creds: &KiroCredentials,
    now: DateTime<Utc>,
) -> Result<KiroSnapshot> {
    let access_token = if oauth::needs_refresh(creds.expires_at.timestamp(), now.timestamp()) {
        let refreshed = tokio::time::timeout(
            REFRESH_TIMEOUT,
            oauth::refresh(
                client,
                &endpoints.token,
                &creds.client_id,
                &creds.client_secret,
                &creds.refresh_token,
            ),
        )
        .await
        .map_err(|_| {
            AppError::Transport(format!("kiro token refresh timeout: {}", endpoints.token))
        })?
        .map_err(|e| {
            AppError::Credentials(format!(
                "Kiro CLI token refresh failed ({e}). Run `kiro-cli login` again."
            ))
        })?;
        let expires_in = i64::try_from(refreshed.expires_in)
            .map_err(|_| AppError::Schema("kiro token refresh expiry is out of range".into()))?;
        let expires_at_secs = now
            .timestamp()
            .checked_add(expires_in)
            .ok_or_else(|| AppError::Schema("kiro token refresh expiry overflowed".into()))?;
        let expires_at = DateTime::from_timestamp(expires_at_secs, 0)
            .ok_or_else(|| AppError::Schema("kiro token refresh expiry is out of range".into()))?;
        let persisted = PersistedOAuth {
            account: creds.account_key.clone(),
            access_token: refreshed.access_token,
            refresh_token: refreshed
                .refresh_token
                .unwrap_or_else(|| creds.refresh_token.clone()),
            expires_at,
        };
        write_persisted_oauth(cache, &persisted).map_err(|e| {
            AppError::Credentials(format!(
                "refreshed Kiro CLI credentials could not be saved ({e}); run `kiro-cli login` again if the refresh token was rotated"
            ))
        })?;
        persisted.access_token
    } else {
        creds.access_token.clone()
    };

    let body = serde_json::json!({
        "origin": "AI_EDITOR",
        "profileArn": creds.profile_arn,
        "resourceType": "AGENTIC_REQUEST",
    });

    let resp = tokio::time::timeout(
        HTTP_TIMEOUT,
        client
            .post(&endpoints.usage_limits)
            .header("Content-Type", "application/x-amz-json-1.0")
            .header("x-amz-target", REQUEST_TARGET)
            .header("Authorization", format!("Bearer {access_token}"))
            .json(&body)
            .send(),
    )
    .await
    .map_err(|_| AppError::Transport(format!("kiro timeout: {}", endpoints.usage_limits)))??;

    let status = resp.status();
    if !status.is_success() {
        let body = if matches!(status.as_u16(), 401 | 403) {
            "Kiro CLI authentication failed".into()
        } else {
            format!("Kiro CLI API returned HTTP {}", status.as_u16())
        };
        return Err(AppError::Http {
            status: status.as_u16(),
            body,
        });
    }

    let bytes = read_body_capped(resp, MAX_BODY_BYTES).await?;
    let parsed: UsageLimitsResponse = serde_json::from_slice(&bytes)
        .map_err(|e| AppError::Schema(format!("kiro usage-limits response: {e}")))?;
    types::to_snapshot(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use tempfile::TempDir;

    fn cache_fixture() -> (TempDir, Cache) {
        let td = TempDir::new().unwrap();
        let cache = Cache::at(td.path().join("kiro"));
        cache.ensure_dir().unwrap();
        (td, cache)
    }

    fn seed_db(dir: &TempDir, expires_at: &str) -> std::path::PathBuf {
        let path = dir.path().join("data.sqlite3");
        let conn = Connection::open(&path).unwrap();
        conn.execute("CREATE TABLE auth_kv (key TEXT, value TEXT)", [])
            .unwrap();
        conn.execute("CREATE TABLE state (key TEXT, value TEXT)", [])
            .unwrap();
        let token = serde_json::json!({
            "access_token": "AT", "refresh_token": "RT",
            "expires_at": expires_at, "region": "us-east-1",
        })
        .to_string();
        let device =
            serde_json::json!({"client_id": "CID", "client_secret": "CSECRET"}).to_string();
        let profile =
            serde_json::json!({"arn": "arn:aws:codewhisperer:us-east-1:1:profile/A"}).to_string();
        conn.execute(
            "INSERT INTO auth_kv (key, value) VALUES ('kirocli:odic:token', ?1)",
            [&token],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO auth_kv (key, value) VALUES ('kirocli:odic:device-registration', ?1)",
            [&device],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO state (key, value) VALUES ('api.codewhisperer.profile', ?1)",
            [&profile],
        )
        .unwrap();
        path
    }

    fn account_key(dir: &TempDir) -> String {
        let path = dir.path().join("data.sqlite3");
        db::read_credentials(&path).unwrap().account_key
    }

    fn usage_json() -> String {
        r#"{
            "nextDateReset": 4102444800.0,
            "subscriptionInfo": { "subscriptionTitle": "KIRO POWER" },
            "usageBreakdownList": [{
                "resourceType": "CREDIT",
                "currentUsageWithPrecision": 40.0,
                "usageLimitWithPrecision": 100.0
            }]
        }"#
        .to_string()
    }

    #[tokio::test]
    async fn live_fetch_reads_token_from_db_and_calls_get_usage_limits() {
        let mut server = mockito::Server::new_async().await;
        let m = server
            .mock("POST", "/")
            .match_header("x-amz-target", "AmazonCodeWhispererService.GetUsageLimits")
            .match_header("authorization", "Bearer AT")
            .with_status(200)
            .with_body(usage_json())
            .create_async()
            .await;

        let db_dir = TempDir::new().unwrap();
        // Far future — no refresh needed.
        let db_path = seed_db(&db_dir, "2099-01-01T00:00:00Z");
        let client = reqwest::Client::new();
        let endpoints_url = server.url();

        let creds = db::read_credentials(&db_path).unwrap();
        let (_cache_dir, cache) = cache_fixture();
        let out = fetch_live(
            &client,
            &Endpoints {
                usage_limits: endpoints_url,
                token: "unused".into(),
            },
            &cache,
            &creds,
            Utc::now(),
        )
        .await
        .unwrap();

        assert_eq!(out.plan, "KIRO POWER");
        assert_eq!(out.used, 40.0);
        assert_eq!(out.limit, 100.0);
        m.assert_async().await;
    }

    #[tokio::test]
    async fn expired_token_is_refreshed_before_the_usage_call() {
        let mut server = mockito::Server::new_async().await;
        let token_mock = server
            .mock("POST", "/token")
            .with_status(200)
            .with_body(r#"{"accessToken":"NEW-AT","expiresIn":3600}"#)
            .create_async()
            .await;
        let usage_mock = server
            .mock("POST", "/")
            .match_header("authorization", "Bearer NEW-AT")
            .with_status(200)
            .with_body(usage_json())
            .create_async()
            .await;

        let db_dir = TempDir::new().unwrap();
        // Already expired — must trigger a refresh.
        let db_path = seed_db(&db_dir, "2000-01-01T00:00:00Z");
        let creds = db::read_credentials(&db_path).unwrap();
        let (_cache_dir, cache) = cache_fixture();
        let client = reqwest::Client::new();

        let out = fetch_live(
            &client,
            &Endpoints {
                usage_limits: server.url(),
                token: format!("{}/token", server.url()),
            },
            &cache,
            &creds,
            Utc::now(),
        )
        .await
        .unwrap();

        assert_eq!(out.used, 40.0);
        token_mock.assert_async().await;
        usage_mock.assert_async().await;
    }

    #[tokio::test]
    async fn refreshed_credentials_are_reused_and_rotated_token_is_retained() {
        let mut server = mockito::Server::new_async().await;
        let token_mock = server
            .mock("POST", "/token")
            .match_body(mockito::Matcher::Json(serde_json::json!({
                "clientId": "CID",
                "clientSecret": "CSECRET",
                "grantType": "refresh_token",
                "refreshToken": "RT",
            })))
            .with_status(200)
            .with_body(r#"{"accessToken":"NEW-AT","refreshToken":"ROTATED-RT","expiresIn":3600}"#)
            .expect(1)
            .create_async()
            .await;
        let usage_mock = server
            .mock("POST", "/")
            .match_header("authorization", "Bearer NEW-AT")
            .with_status(200)
            .with_body(usage_json())
            .expect(2)
            .create_async()
            .await;

        let db_dir = TempDir::new().unwrap();
        let db_path = seed_db(&db_dir, "2000-01-01T00:00:00Z");
        let (_cache_dir, cache) = cache_fixture();
        let endpoints = Endpoints {
            usage_limits: server.url(),
            token: format!("{}/token", server.url()),
        };
        let now = DateTime::parse_from_rfc3339("2026-08-03T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);

        for _ in 0..2 {
            let out = fetch_snapshot_at(
                &reqwest::Client::new(),
                &db_path,
                &cache,
                Duration::ZERO,
                Some(&endpoints),
                now,
            )
            .await
            .unwrap();
            assert_eq!(out.snapshot.used, 40.0);
        }

        let persisted: serde_json::Value =
            serde_json::from_slice(&std::fs::read(oauth_cache_path(&cache)).unwrap()).unwrap();
        assert_eq!(persisted["access_token"], "NEW-AT");
        assert_eq!(persisted["refresh_token"], "ROTATED-RT");
        assert_eq!(persisted["account"], account_key(&db_dir));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(oauth_cache_path(&cache))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o077, 0);
        }

        token_mock.assert_async().await;
        usage_mock.assert_async().await;
    }

    #[test]
    fn persisted_credentials_from_another_account_are_ignored() {
        let db_dir = TempDir::new().unwrap();
        let db_path = seed_db(&db_dir, "2099-01-01T00:00:00Z");
        let mut creds = db::read_credentials(&db_path).unwrap();
        let (_cache_dir, cache) = cache_fixture();
        write_persisted_oauth(
            &cache,
            &PersistedOAuth {
                account: "another-account".into(),
                access_token: "OTHER-AT".into(),
                refresh_token: "OTHER-RT".into(),
                expires_at: DateTime::parse_from_rfc3339("2100-01-01T00:00:00Z")
                    .unwrap()
                    .with_timezone(&Utc),
            },
        )
        .unwrap();

        apply_persisted_oauth(&cache, &mut creds).unwrap();

        assert_eq!(creds.access_token, "AT");
        assert_eq!(creds.refresh_token, "RT");
    }

    #[tokio::test]
    async fn refresh_failure_is_a_credentials_error() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("POST", "/token")
            .with_status(400)
            .with_body(r#"{"error":"invalid_grant"}"#)
            .create_async()
            .await;

        let db_dir = TempDir::new().unwrap();
        let db_path = seed_db(&db_dir, "2000-01-01T00:00:00Z");
        let creds = db::read_credentials(&db_path).unwrap();
        let (_cache_dir, cache) = cache_fixture();
        let client = reqwest::Client::new();

        let err = fetch_live(
            &client,
            &Endpoints {
                usage_limits: server.url(),
                token: format!("{}/token", server.url()),
            },
            &cache,
            &creds,
            Utc::now(),
        )
        .await
        .unwrap_err();
        assert!(matches!(err, AppError::Credentials(_)));
    }

    #[tokio::test]
    async fn a_stale_cache_falls_back_when_the_live_call_fails() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("POST", "/")
            .with_status(500)
            .with_body("boom")
            .create_async()
            .await;

        let db_dir = TempDir::new().unwrap();
        let db_path = seed_db(&db_dir, "2099-01-01T00:00:00Z");
        let (_cache_dir, cache) = cache_fixture();
        let account = account_key(&db_dir);
        cache
            .write_payload(
                serde_json::to_vec(&serde_json::json!({
                    "account": account,
                    "plan": "KIRO POWER",
                    "used": 10.0,
                    "limit": 100.0,
                    "reset_at": null,
                }))
                .unwrap()
                .as_slice(),
            )
            .unwrap();
        // Force the cache to look old enough to require a live refetch.
        std::thread::sleep(std::time::Duration::from_millis(5));

        let client = reqwest::Client::new();
        let out = fetch_snapshot_at(
            &client,
            &db_path,
            &cache,
            Duration::from_millis(1),
            Some(&Endpoints {
                usage_limits: server.url(),
                token: format!("{}/token", server.url()),
            }),
            Utc::now(),
        )
        .await
        .unwrap();

        assert!(out.stale);
        assert_eq!(out.snapshot.used, 10.0);
        assert!(out.last_error.is_some());
    }

    #[tokio::test]
    async fn fresh_cache_is_served_without_a_network_call() {
        let db_dir = TempDir::new().unwrap();
        let db_path = seed_db(&db_dir, "2099-01-01T00:00:00Z");
        let (_cache_dir, cache) = cache_fixture();
        let account = account_key(&db_dir);
        cache
            .write_payload(
                serde_json::to_vec(&serde_json::json!({
                    "account": account,
                    "plan": "KIRO POWER",
                    "used": 10.0,
                    "limit": 100.0,
                    "reset_at": null,
                }))
                .unwrap()
                .as_slice(),
            )
            .unwrap();

        let client = reqwest::Client::new();
        // Deliberately no mock server configured: a fresh-cache hit must
        // never reach the network, so pointing the override at a bogus
        // "http://127.0.0.1:1" endpoint is a canary — the test would fail
        // with a transport error if the cache short-circuit stopped working.
        let out = fetch_snapshot_at(
            &client,
            &db_path,
            &cache,
            Duration::from_secs(60),
            Some(&Endpoints {
                usage_limits: "http://127.0.0.1:1".into(),
                token: "http://127.0.0.1:1".into(),
            }),
            Utc::now(),
        )
        .await
        .unwrap();

        assert!(!out.stale);
        assert_eq!(out.snapshot.used, 10.0);
    }

    #[tokio::test]
    async fn cache_from_a_different_account_is_not_reused() {
        let mut server = mockito::Server::new_async().await;
        let m = server
            .mock("POST", "/")
            .with_status(200)
            .with_body(usage_json())
            .create_async()
            .await;

        let db_dir = TempDir::new().unwrap();
        let db_path = seed_db(&db_dir, "2099-01-01T00:00:00Z");
        let (_cache_dir, cache) = cache_fixture();
        cache
            .write_payload(
                serde_json::to_vec(&serde_json::json!({
                    "account": "some-other-account",
                    "plan": "STALE PLAN",
                    "used": 10.0,
                    "limit": 100.0,
                    "reset_at": null,
                }))
                .unwrap()
                .as_slice(),
            )
            .unwrap();

        let client = reqwest::Client::new();
        let out = fetch_snapshot_at(
            &client,
            &db_path,
            &cache,
            Duration::from_secs(60),
            Some(&Endpoints {
                usage_limits: server.url(),
                token: format!("{}/token", server.url()),
            }),
            Utc::now(),
        )
        .await
        .unwrap();

        // The account-mismatched cache was rejected, so this came from the
        // live mock (used=40, plan="KIRO POWER"), not the stale cache entry.
        assert_eq!(out.snapshot.used, 40.0);
        assert_eq!(out.snapshot.plan, "KIRO POWER");
        assert!(!out.stale);
        m.assert_async().await;
    }

    /// The credit cycle rolled over while cached: serving that cache during
    /// an outage would show last cycle's usage as if it were current. The
    /// parse must reject it, surfacing the live error instead. Mirrors
    /// `cursor::fetch`'s `cache_past_its_billing_reset_is_not_served_during_an_outage`.
    #[tokio::test]
    async fn cache_past_its_credit_reset_is_not_served_during_an_outage() {
        let db_dir = TempDir::new().unwrap();
        let db_path = seed_db(&db_dir, "2099-01-01T00:00:00Z");
        let (_cache_dir, cache) = cache_fixture();
        let account = account_key(&db_dir);
        cache
            .write_payload(
                serde_json::to_vec(&serde_json::json!({
                    "account": account,
                    "plan": "KIRO POWER",
                    "used": 10.0,
                    "limit": 100.0,
                    "reset_at": "2026-08-04T00:00:00Z",
                }))
                .unwrap()
                .as_slice(),
            )
            .unwrap();

        let mut server = mockito::Server::new_async().await;
        server
            .mock("POST", "/")
            .with_status(503)
            .create_async()
            .await;
        let now = DateTime::parse_from_rfc3339("2026-08-05T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let err = fetch_snapshot_at(
            &reqwest::Client::new(),
            &db_path,
            &cache,
            Duration::from_secs(0),
            Some(&Endpoints {
                usage_limits: server.url(),
                token: format!("{}/token", server.url()),
            }),
            now,
        )
        .await
        .unwrap_err();
        assert!(matches!(err, AppError::Http { status: 503, .. }));
    }
}
