//! Kimi Code CLI OAuth — the credential source for a *Kimi subscription*.
//!
//! `kimi` logs in through a device-code flow rather than an API key, and
//! stores the resulting token in its own credential file
//! (`~/.kimi-code/credentials/kimi-code.json`, mode 0600, snake_case wire
//! shape). The subscription's quota endpoint is the same
//! `/coding/v1/usages` this vendor already calls — only the bearer differs, so
//! everything here is about obtaining and keeping that bearer valid.
//!
//! **Why the refreshed pair is written back to the CLI's own file** (unlike
//! `kiro`, which keeps rotations in ai-usagebar's cache and never touches
//! kiro-cli's database): auth.kimi.com rotates the refresh token on *every*
//! grant. A private sidecar copy would therefore leave the CLI holding a
//! superseded refresh token after each widget tick, and the next `kimi` run
//! would find its session dead — ai-usagebar would be logging the user out of
//! their own CLI every five minutes. One store, written under the CLI's own
//! lock protocol (`lock.rs`), is the only shape that keeps both clients alive.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{AppError, Result};

/// kimi-code's public device-flow client id (`KIMI_CODE_FLOW_CONFIG.clientId`),
/// shared across regions. Not a secret: it identifies the CLI, and the refresh
/// grant is authorized by the user's own refresh token.
pub const CLIENT_ID: &str = "17e5f671-d194-4dfb-9706-5516cb48c098";

/// Refresh this far ahead of the cached expiry so a slow round-trip never
/// races the token's death. The access token only lives 15 minutes, so this is
/// tighter than `kiro`/`openai`'s 300 s: a wider buffer would refresh on every
/// single tick.
pub const REFRESH_BUFFER_SECS: i64 = 120;

pub const HOME_DIR_NAME: &str = ".kimi-code";
/// kimi-code's own storage name for this provider; it names both the
/// credential file and the lock target.
const PROVIDER_NAME: &str = "kimi-code";
const RE_LOGIN_HINT: &str = "run `kimi` and log in again";

/// The two Kimi Code deployments. The OAuth client id is shared; the hosts are
/// not, and a token minted by one is meaningless to the other.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Region {
    MainlandCn,
    Global,
}

impl Region {
    pub fn api_base(self) -> &'static str {
        match self {
            Region::MainlandCn => "https://api.kimi.com/coding/v1",
            Region::Global => "https://api.kimi.ai/coding/v1",
        }
    }

    pub fn oauth_host(self) -> &'static str {
        match self {
            Region::MainlandCn => "https://auth.kimi.com",
            Region::Global => "https://auth.kimi.ai",
        }
    }

    /// Accepts both this project's spelling (`cn`, as `[moonshot] region`
    /// uses) and kimi-code's own marker spelling (`mainland-cn`).
    pub fn parse(value: &str) -> Option<Self> {
        let value = value.trim();
        if value.eq_ignore_ascii_case("cn") || value.eq_ignore_ascii_case("mainland-cn") {
            Some(Region::MainlandCn)
        } else if value.eq_ignore_ascii_case("global") {
            Some(Region::Global)
        } else {
            None
        }
    }
}

pub fn default_home() -> Result<PathBuf> {
    Ok(crate::cache::home_dir()?.join(HOME_DIR_NAME))
}

pub fn credentials_path_in(home: &Path) -> PathBuf {
    home.join("credentials")
        .join(format!("{PROVIDER_NAME}.json"))
}

/// The path `proper-lockfile` locks against inside kimi-code (`lock.rs` derives
/// the actual `.lock` directory from it).
pub fn lock_target_in(home: &Path) -> PathBuf {
    home.join("oauth").join(PROVIDER_NAME)
}

/// kimi-code's install-channel marker (`<home>/region`), the CLI's own last
/// resort before defaulting to mainland. Unknown contents are ignored, exactly
/// as `readRegionMarker` does.
pub fn read_region_marker(home: &Path) -> Option<Region> {
    let raw = std::fs::read_to_string(home.join("region")).ok()?;
    match raw.trim() {
        "mainland-cn" => Some(Region::MainlandCn),
        "global" => Some(Region::Global),
        _ => None,
    }
}

/// A token as kimi-code stores it. `extra` preserves any field this version
/// does not know about, so writing a refreshed pair back never truncates the
/// CLI's own file.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
pub struct Credentials {
    pub access_token: String,
    pub refresh_token: String,
    /// Absolute unix seconds, the same field kimi-code persists.
    pub expires_at: i64,
    #[serde(default)]
    pub expires_in: u64,
    #[serde(default)]
    pub scope: String,
    #[serde(default = "default_token_type")]
    pub token_type: String,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

fn default_token_type() -> String {
    "Bearer".to_string()
}

/// True when kimi-code has a usable login here. A logged-out CLI leaves a
/// tombstone (empty access *and* refresh token) rather than deleting the file,
/// so a bare `path.exists()` would misread it as logged in.
pub fn is_logged_in(path: &Path) -> bool {
    matches!(read_from(path), Ok(creds) if !creds.refresh_token.trim().is_empty())
}

pub fn read_from(path: &Path) -> Result<Credentials> {
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Err(AppError::Credentials(format!(
                "Kimi: no Kimi Code CLI login at {} — {RE_LOGIN_HINT}, or set an API key",
                crate::display::sanitize_untrusted_path(path)
            )));
        }
        Err(e) => return Err(AppError::io_at(path, e)),
    };
    let creds: Credentials = serde_json::from_slice(&bytes).map_err(|e| {
        AppError::Credentials(format!(
            "Kimi: the Kimi Code CLI credentials at {} are malformed ({e}); {RE_LOGIN_HINT}",
            crate::display::sanitize_untrusted_path(path)
        ))
    })?;
    if creds.refresh_token.trim().is_empty() {
        return Err(AppError::Credentials(format!(
            "Kimi: the Kimi Code CLI is logged out ({}); {RE_LOGIN_HINT}",
            crate::display::sanitize_untrusted_path(path)
        )));
    }
    Ok(creds)
}

/// Replace kimi-code's credential file with `creds`, atomically and 0600 —
/// matching the CLI's own write semantics (tmp file → rename, mode 0600).
/// Callers must hold the lock from `lock.rs`.
pub fn write_to(path: &Path, creds: &Credentials) -> Result<()> {
    let mut bytes = serde_json::to_vec_pretty(creds)?;
    bytes.push(b'\n');
    crate::cache::atomic_write(path, &bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
            .map_err(|e| AppError::io_at(path, e))?;
    }
    Ok(())
}

pub fn needs_refresh(expires_at_secs: i64, now_secs: i64) -> bool {
    expires_at_secs < now_secs + REFRESH_BUFFER_SECS
}

pub fn token_endpoint(oauth_host: &str) -> String {
    format!("{}/api/oauth/token", oauth_host.trim_end_matches('/'))
}

#[derive(Debug, Deserialize)]
pub struct RefreshResponse {
    #[serde(deserialize_with = "de_nonempty_string")]
    pub access_token: String,
    /// auth.kimi.com always rotates and always returns one; the field stays
    /// optional so a server that stops rotating degrades to "keep the old one"
    /// instead of failing the whole refresh.
    #[serde(default, deserialize_with = "de_opt_nonempty_string")]
    pub refresh_token: Option<String>,
    #[serde(deserialize_with = "de_positive_u64")]
    pub expires_in: u64,
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub token_type: Option<String>,
}

fn de_nonempty_string<'de, D>(d: D) -> std::result::Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value = String::deserialize(d)?;
    if value.trim().is_empty() {
        Err(serde::de::Error::custom("access_token cannot be empty"))
    } else {
        Ok(value)
    }
}

fn de_opt_nonempty_string<'de, D>(d: D) -> std::result::Result<Option<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Option::<String>::deserialize(d)?
        .map(|value| {
            if value.trim().is_empty() {
                Err(serde::de::Error::custom("refresh_token cannot be empty"))
            } else {
                Ok(value)
            }
        })
        .transpose()
}

fn de_positive_u64<'de, D>(d: D) -> std::result::Result<u64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let v = serde_json::Value::deserialize(d)?;
    match v {
        serde_json::Value::Number(n) => {
            const MAX_SAFE: u64 = (i64::MAX as u64) / 2;
            if let Some(value) = n.as_u64().filter(|value| (1..=MAX_SAFE).contains(value)) {
                Ok(value)
            } else {
                Err(serde::de::Error::custom(
                    "expires_in must be a positive integer in range",
                ))
            }
        }
        _ => Err(serde::de::Error::custom("expires_in must be a number")),
    }
}

/// `POST <oauth host>/api/oauth/token`, form-encoded, exactly as kimi-code's
/// own `refreshAccessToken` does. Never echoes the upstream body: an OAuth
/// error response is not guaranteed to be free of account-identifying detail
/// (same reasoning as `kiro::oauth::refresh`).
pub async fn refresh(
    client: &reqwest::Client,
    endpoint: &str,
    client_id: &str,
    refresh_token: &str,
) -> Result<RefreshResponse> {
    let resp = client
        .post(endpoint)
        .header("Accept", "application/json")
        .form(&[
            ("client_id", client_id),
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh_token),
        ])
        .send()
        .await?;

    let status = resp.status();
    let body = crate::vendor::read_body_capped(resp, crate::vendor::MAX_BODY_BYTES).await?;
    if !status.is_success() {
        return Err(AppError::Http {
            status: status.as_u16(),
            body: "Kimi Code CLI token refresh failed".into(),
        });
    }
    serde_json::from_slice(&body)
        .map_err(|e| AppError::Schema(format!("kimi token refresh response: {e}")))
}

/// Fold a refresh response into the stored credential, keeping every field the
/// server did not restate (including unknown ones).
pub fn apply_refresh(
    prior: &Credentials,
    refreshed: RefreshResponse,
    now_secs: i64,
) -> Credentials {
    let expires_in = i64::try_from(refreshed.expires_in).unwrap_or(i64::MAX);
    Credentials {
        access_token: refreshed.access_token,
        refresh_token: refreshed
            .refresh_token
            .unwrap_or_else(|| prior.refresh_token.clone()),
        expires_at: now_secs.saturating_add(expires_in),
        expires_in: refreshed.expires_in,
        scope: refreshed.scope.unwrap_or_else(|| prior.scope.clone()),
        token_type: refreshed
            .token_type
            .unwrap_or_else(|| prior.token_type.clone()),
        extra: prior.extra.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn sample_file(dir: &TempDir, json: &str) -> PathBuf {
        let path = dir.path().join("kimi-code.json");
        std::fs::write(&path, json).unwrap();
        path
    }

    fn sample_creds() -> Credentials {
        Credentials {
            access_token: "at".into(),
            refresh_token: "rt".into(),
            expires_at: 1_000_000,
            expires_in: 900,
            scope: "kimi-code".into(),
            token_type: "Bearer".into(),
            extra: serde_json::Map::new(),
        }
    }

    #[test]
    fn reads_the_cli_wire_shape() {
        let td = TempDir::new().unwrap();
        let path = sample_file(
            &td,
            r#"{"access_token":"at","refresh_token":"rt","expires_at":1000000,
                "expires_in":900,"scope":"kimi-code","token_type":"Bearer"}"#,
        );
        let creds = read_from(&path).unwrap();
        assert_eq!(creds, sample_creds());
        assert!(is_logged_in(&path));
    }

    #[test]
    fn a_logged_out_tombstone_is_not_a_login() {
        let td = TempDir::new().unwrap();
        let path = sample_file(
            &td,
            r#"{"access_token":"","refresh_token":"","expires_at":0,"expires_in":0,
                "scope":"kimi-code","token_type":"Bearer"}"#,
        );
        assert!(!is_logged_in(&path));
        let err = read_from(&path).unwrap_err();
        assert!(matches!(err, AppError::Credentials(_)), "{err:?}");
    }

    #[test]
    fn a_missing_or_malformed_file_names_the_re_login_step() {
        let td = TempDir::new().unwrap();
        let missing = td.path().join("nope.json");
        assert!(!is_logged_in(&missing));
        let err = read_from(&missing).unwrap_err().to_string();
        assert!(err.contains("kimi"), "{err}");

        let path = sample_file(&td, "{ not json");
        let err = read_from(&path).unwrap_err().to_string();
        assert!(err.contains("malformed"), "{err}");
    }

    #[test]
    fn write_back_preserves_unknown_fields_and_stays_owner_only() {
        let td = TempDir::new().unwrap();
        let path = sample_file(
            &td,
            r#"{"access_token":"at","refresh_token":"rt","expires_at":1000000,
                "expires_in":900,"scope":"kimi-code","token_type":"Bearer",
                "future_field":{"kept":true}}"#,
        );
        let mut creds = read_from(&path).unwrap();
        assert!(creds.extra.contains_key("future_field"));
        creds.access_token = "at2".into();
        write_to(&path, &creds).unwrap();

        let reread: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(reread["access_token"], "at2");
        assert_eq!(reread["future_field"]["kept"], true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600, "credentials must stay owner-only");
        }
    }

    #[test]
    fn needs_refresh_uses_the_two_minute_buffer() {
        let now = 1_000_000;
        assert!(needs_refresh(now + 60, now));
        assert!(needs_refresh(now + REFRESH_BUFFER_SECS - 1, now));
        assert!(!needs_refresh(now + REFRESH_BUFFER_SECS + 1, now));
    }

    #[test]
    fn regions_map_to_their_own_hosts() {
        assert_eq!(Region::parse("cn"), Some(Region::MainlandCn));
        assert_eq!(Region::parse("mainland-cn"), Some(Region::MainlandCn));
        assert_eq!(Region::parse("GLOBAL"), Some(Region::Global));
        assert_eq!(Region::parse("us"), None);
        assert_eq!(
            Region::MainlandCn.api_base(),
            "https://api.kimi.com/coding/v1"
        );
        assert_eq!(Region::Global.api_base(), "https://api.kimi.ai/coding/v1");
        assert_eq!(
            token_endpoint(Region::Global.oauth_host()),
            "https://auth.kimi.ai/api/oauth/token"
        );
        assert_eq!(
            token_endpoint("https://auth.kimi.com/"),
            "https://auth.kimi.com/api/oauth/token"
        );
    }

    #[test]
    fn region_marker_is_read_and_unknown_values_ignored() {
        let td = TempDir::new().unwrap();
        assert_eq!(read_region_marker(td.path()), None);
        std::fs::write(td.path().join("region"), "global\n").unwrap();
        assert_eq!(read_region_marker(td.path()), Some(Region::Global));
        std::fs::write(td.path().join("region"), "mainland-cn").unwrap();
        assert_eq!(read_region_marker(td.path()), Some(Region::MainlandCn));
        std::fs::write(td.path().join("region"), "atlantis").unwrap();
        assert_eq!(read_region_marker(td.path()), None);
    }

    #[test]
    fn cli_paths_follow_kimi_codes_layout() {
        let home = Path::new("/home/u/.kimi-code");
        assert_eq!(
            credentials_path_in(home),
            PathBuf::from("/home/u/.kimi-code/credentials/kimi-code.json")
        );
        assert_eq!(
            lock_target_in(home),
            PathBuf::from("/home/u/.kimi-code/oauth/kimi-code")
        );
    }

    #[test]
    fn malformed_refresh_responses_are_rejected_not_defaulted() {
        for body in [
            r#"{"access_token":"","expires_in":900}"#,
            r#"{"access_token":"a","expires_in":"900"}"#,
            r#"{"access_token":"a","expires_in":0}"#,
            r#"{"access_token":"a","expires_in":-1}"#,
            r#"{"access_token":"a"}"#,
            r#"{"access_token":"a","refresh_token":" ","expires_in":900}"#,
        ] {
            assert!(
                serde_json::from_str::<RefreshResponse>(body).is_err(),
                "{body}"
            );
        }
    }

    #[test]
    fn apply_refresh_keeps_what_the_server_did_not_restate() {
        let mut prior = sample_creds();
        prior.extra.insert("future".into(), serde_json::json!(1));
        let refreshed: RefreshResponse =
            serde_json::from_str(r#"{"access_token":"at2","expires_in":900}"#).unwrap();
        let next = apply_refresh(&prior, refreshed, 5_000);
        assert_eq!(next.access_token, "at2");
        assert_eq!(next.refresh_token, "rt", "no rotation → keep the old one");
        assert_eq!(next.expires_at, 5_900);
        assert_eq!(next.scope, "kimi-code");
        assert_eq!(next.token_type, "Bearer");
        assert_eq!(next.extra["future"], serde_json::json!(1));
    }

    #[tokio::test]
    async fn refresh_posts_the_form_kimi_code_posts() {
        let mut server = mockito::Server::new_async().await;
        let m = server
            .mock("POST", "/api/oauth/token")
            .match_header("content-type", "application/x-www-form-urlencoded")
            .match_body(mockito::Matcher::AllOf(vec![
                mockito::Matcher::UrlEncoded("client_id".into(), CLIENT_ID.into()),
                mockito::Matcher::UrlEncoded("grant_type".into(), "refresh_token".into()),
                mockito::Matcher::UrlEncoded("refresh_token".into(), "old-rt".into()),
            ]))
            .with_status(200)
            .with_body(
                r#"{"access_token":"new-at","refresh_token":"new-rt","expires_in":900,
                    "scope":"kimi-code","token_type":"Bearer"}"#,
            )
            .create_async()
            .await;

        let out = refresh(
            &reqwest::Client::new(),
            &token_endpoint(&server.url()),
            CLIENT_ID,
            "old-rt",
        )
        .await
        .unwrap();
        m.assert_async().await;
        assert_eq!(out.access_token, "new-at");
        assert_eq!(out.refresh_token.as_deref(), Some("new-rt"));
        assert_eq!(out.expires_in, 900);
    }

    #[tokio::test]
    async fn a_rejected_refresh_does_not_echo_the_body() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("POST", "/api/oauth/token")
            .with_status(401)
            .with_body(r#"{"error":"invalid_grant","error_description":"sensitive detail"}"#)
            .create_async()
            .await;

        let err = refresh(
            &reqwest::Client::new(),
            &token_endpoint(&server.url()),
            CLIENT_ID,
            "old-rt",
        )
        .await
        .unwrap_err();
        match err {
            AppError::Http { status, body } => {
                assert_eq!(status, 401);
                assert!(!body.contains("sensitive detail"), "{body}");
            }
            other => panic!("expected Http, got {other:?}"),
        }
    }
}
