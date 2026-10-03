//! Read kiro-cli's own local SQLite state — `~/.local/share/kiro-cli/data.sqlite3`
//! — for the AWS SSO OIDC token and CodeWhisperer profile ARN it already
//! obtained via `kiro-cli login`. Opened read-only and never written back to:
//! it's kiro-cli's own live WAL-mode database (the `-wal`/`-shm` sidecar files
//! sit next to it), the same "not ours to lock for writing" treatment
//! `cursor::db` gives Cursor's `state.vscdb`.
//!
//! Two tables matter:
//! - `auth_kv` — `kirocli:odic:token` (access/refresh token pair, RFC3339
//!   expiry) and `kirocli:odic:device-registration` (the OAuth client
//!   id/secret kiro-cli registered for itself, needed to refresh the token —
//!   see `oauth.rs`).
//! - `state` — `api.codewhisperer.profile`, the resolved IAM Identity Center
//!   profile ARN. Empty for AWS Builder ID accounts with no IdC profile; the
//!   API accepts an empty `profileArn`.

use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use rusqlite::{Connection, OpenFlags};
use serde::Deserialize;
use sha1::{Digest, Sha1};

use crate::error::{AppError, Result};

const TOKEN_KEY: &str = "kirocli:odic:token";
const DEVICE_REGISTRATION_KEY: &str = "kirocli:odic:device-registration";
const PROFILE_STATE_KEY: &str = "api.codewhisperer.profile";
const LOGIN_HINT: &str = "kiro-cli login";

/// Default location of kiro-cli's local database. Verified on Linux
/// (`~/.local/share/kiro-cli/data.sqlite3`, i.e. `directories::BaseDirs::data_dir()`
/// joined with `kiro-cli/data.sqlite3`). macOS/Windows follow the same
/// `directories` convention every other local-file vendor here uses, but are
/// unverified against a real kiro-cli install on those platforms.
pub fn default_db_path() -> Result<PathBuf> {
    let base = directories::BaseDirs::new().ok_or_else(|| {
        AppError::Other("could not resolve the platform data directory (no HOME?)".into())
    })?;
    Ok(base.data_dir().join("kiro-cli").join("data.sqlite3"))
}

#[derive(Debug, Deserialize)]
struct TokenRow {
    access_token: String,
    refresh_token: String,
    expires_at: String,
    region: String,
}

#[derive(Debug, Deserialize)]
struct DeviceRegistrationRow {
    client_id: String,
    client_secret: String,
}

#[derive(Debug, Default, Deserialize)]
struct ProfileRow {
    #[serde(default)]
    arn: String,
}

/// Everything a `GetUsageLimits` call needs, read out of kiro-cli's own local
/// state in one pass.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KiroCredentials {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: DateTime<Utc>,
    pub region: String,
    pub client_id: String,
    pub client_secret: String,
    /// CodeWhisperer profile ARN; empty for accounts with no IdC profile.
    pub profile_arn: String,
    /// Non-plaintext cache identity for the signed-in account. Never
    /// displayed — exists so a cache written for one account is not served
    /// for another after a `kiro-cli login` switch.
    pub account_key: String,
}

pub fn read_credentials(path: &Path) -> Result<KiroCredentials> {
    if !path.exists() {
        return Err(AppError::Credentials(format!(
            "Kiro CLI database not found at {}. Run `{LOGIN_HINT}`, then try again.",
            path.display()
        )));
    }
    let conn =
        Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY).map_err(|e| {
            AppError::Credentials(format!(
                "could not open Kiro CLI database at {}: {e}",
                path.display()
            ))
        })?;

    let token: TokenRow = read_auth_kv(&conn, TOKEN_KEY)?;
    let device: DeviceRegistrationRow = read_auth_kv(&conn, DEVICE_REGISTRATION_KEY)?;
    let profile_arn = read_optional_state::<ProfileRow>(&conn, PROFILE_STATE_KEY)?
        .map(|p| p.arn)
        .unwrap_or_default();

    for (label, value) in [
        ("access token", token.access_token.as_str()),
        ("refresh token", token.refresh_token.as_str()),
        ("client id", device.client_id.as_str()),
        ("client secret", device.client_secret.as_str()),
    ] {
        if value.trim().is_empty() {
            return Err(AppError::Credentials(format!(
                "Kiro CLI {label} is empty. Run `{LOGIN_HINT}` again."
            )));
        }
    }
    super::oauth::validate_region(&token.region)?;

    let expires_at = DateTime::parse_from_rfc3339(&token.expires_at)
        .map_err(|e| {
            AppError::Credentials(format!(
                "Kiro CLI token has an unreadable expiry ({:?}): {e}. Run `{LOGIN_HINT}` again.",
                token.expires_at
            ))
        })?
        .with_timezone(&Utc);

    let account_key = account_key(&profile_arn, &token.region, &token.refresh_token);

    Ok(KiroCredentials {
        access_token: token.access_token,
        refresh_token: token.refresh_token,
        expires_at,
        region: token.region,
        client_id: device.client_id,
        client_secret: device.client_secret,
        profile_arn,
        account_key,
    })
}

fn read_auth_kv<T: for<'de> Deserialize<'de>>(conn: &Connection, key: &str) -> Result<T> {
    let raw: String =
        match conn.query_row("SELECT value FROM auth_kv WHERE key = ?1", [key], |row| {
            row.get(0)
        }) {
            Ok(raw) => raw,
            Err(rusqlite::Error::QueryReturnedNoRows) => {
                return Err(AppError::Credentials(format!(
                    "no Kiro CLI `{key}` entry found. Run `{LOGIN_HINT}`, then try again."
                )));
            }
            Err(e) => {
                return Err(AppError::Credentials(format!(
                    "could not read Kiro CLI `{key}` entry: {e}"
                )));
            }
        };
    serde_json::from_str(&raw)
        .map_err(|e| AppError::Credentials(format!("Kiro CLI `{key}` entry is malformed: {e}")))
}

fn read_optional_state<T: for<'de> Deserialize<'de>>(
    conn: &Connection,
    key: &str,
) -> Result<Option<T>> {
    let raw: String = match conn.query_row("SELECT value FROM state WHERE key = ?1", [key], |row| {
        row.get(0)
    }) {
        Ok(raw) => raw,
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok(None),
        Err(e) => {
            return Err(AppError::Credentials(format!(
                "could not read Kiro CLI `{key}` entry: {e}"
            )));
        }
    };
    serde_json::from_str(&raw)
        .map(Some)
        .map_err(|e| AppError::Credentials(format!("Kiro CLI `{key}` entry is malformed: {e}")))
}

fn account_key(profile_arn: &str, region: &str, refresh_token: &str) -> String {
    let mut digest = Sha1::new();
    if profile_arn.is_empty() {
        // Builder ID/social accounts have no profile ARN. The refresh token is
        // the only account-specific value available locally; fingerprint it so
        // two accounts in the same region cannot share cache state.
        digest.update(b"builder-id\0");
        digest.update(region.as_bytes());
        digest.update(b"\0");
        digest.update(refresh_token.as_bytes());
    } else {
        digest.update(b"profile\0");
        digest.update(profile_arn.as_bytes());
    }
    let digest = digest.finalize();
    let mut encoded = String::with_capacity(digest.len() * 2);
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for byte in digest {
        encoded.push(HEX[(byte >> 4) as usize] as char);
        encoded.push(HEX[(byte & 0x0f) as usize] as char);
    }
    encoded
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn seed_db(
        path: &Path,
        token: Option<&str>,
        device: Option<&str>,
        profile: Option<&str>,
    ) -> Connection {
        let conn = Connection::open(path).unwrap();
        conn.execute("CREATE TABLE auth_kv (key TEXT, value TEXT)", [])
            .unwrap();
        conn.execute("CREATE TABLE state (key TEXT, value TEXT)", [])
            .unwrap();
        if let Some(t) = token {
            conn.execute(
                "INSERT INTO auth_kv (key, value) VALUES (?1, ?2)",
                rusqlite::params![TOKEN_KEY, t],
            )
            .unwrap();
        }
        if let Some(d) = device {
            conn.execute(
                "INSERT INTO auth_kv (key, value) VALUES (?1, ?2)",
                rusqlite::params![DEVICE_REGISTRATION_KEY, d],
            )
            .unwrap();
        }
        if let Some(p) = profile {
            conn.execute(
                "INSERT INTO state (key, value) VALUES (?1, ?2)",
                rusqlite::params![PROFILE_STATE_KEY, p],
            )
            .unwrap();
        }
        conn
    }

    fn token_json() -> String {
        serde_json::json!({
            "access_token": "AT",
            "refresh_token": "RT",
            "expires_at": "2030-01-01T00:00:00Z",
            "region": "us-east-1",
        })
        .to_string()
    }

    fn device_json() -> String {
        serde_json::json!({"client_id": "CID", "client_secret": "CSECRET"}).to_string()
    }

    fn profile_json() -> String {
        serde_json::json!({"arn": "arn:aws:codewhisperer:us-east-1:123:profile/ABC"}).to_string()
    }

    #[test]
    fn default_db_path_ends_with_kiro_cli_data_sqlite3() {
        let p = default_db_path().unwrap();
        assert!(
            p.ends_with(std::path::Path::new("kiro-cli").join("data.sqlite3")),
            "{}",
            p.display()
        );
    }

    #[test]
    fn missing_file_is_a_credentials_error_naming_the_path() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        let err = read_credentials(&path).unwrap_err();
        match err {
            AppError::Credentials(m) => assert!(m.contains(&path.display().to_string())),
            other => panic!("expected Credentials error, got {other:?}"),
        }
    }

    #[test]
    fn reads_token_device_and_profile_out_of_the_db() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        seed_db(
            &path,
            Some(&token_json()),
            Some(&device_json()),
            Some(&profile_json()),
        );
        let creds = read_credentials(&path).unwrap();
        assert_eq!(creds.access_token, "AT");
        assert_eq!(creds.refresh_token, "RT");
        assert_eq!(creds.region, "us-east-1");
        assert_eq!(creds.client_id, "CID");
        assert_eq!(creds.client_secret, "CSECRET");
        assert_eq!(
            creds.profile_arn,
            "arn:aws:codewhisperer:us-east-1:123:profile/ABC"
        );
        assert_eq!(creds.expires_at.to_rfc3339(), "2030-01-01T00:00:00+00:00");
    }

    #[test]
    fn missing_profile_row_falls_back_to_empty_arn_not_an_error() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        seed_db(&path, Some(&token_json()), Some(&device_json()), None);
        let creds = read_credentials(&path).unwrap();
        assert_eq!(creds.profile_arn, "");
    }

    #[test]
    fn missing_token_row_is_a_credentials_error() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        seed_db(&path, None, Some(&device_json()), Some(&profile_json()));
        assert!(matches!(
            read_credentials(&path),
            Err(AppError::Credentials(_))
        ));
    }

    #[test]
    fn missing_device_registration_is_a_credentials_error() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        seed_db(&path, Some(&token_json()), None, Some(&profile_json()));
        assert!(matches!(
            read_credentials(&path),
            Err(AppError::Credentials(_))
        ));
    }

    #[test]
    fn malformed_token_json_is_a_credentials_error() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        seed_db(&path, Some("not json"), Some(&device_json()), None);
        assert!(matches!(
            read_credentials(&path),
            Err(AppError::Credentials(_))
        ));
    }

    #[test]
    fn malformed_profile_json_is_not_treated_as_a_builder_id_account() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        seed_db(
            &path,
            Some(&token_json()),
            Some(&device_json()),
            Some("not json"),
        );
        let err = read_credentials(&path).unwrap_err();
        assert!(matches!(err, AppError::Credentials(_)));
        assert!(err.to_string().contains(PROFILE_STATE_KEY));
    }

    #[test]
    fn unparseable_expiry_is_a_credentials_error() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        let bad_token = serde_json::json!({
            "access_token": "AT", "refresh_token": "RT",
            "expires_at": "not-a-date", "region": "us-east-1",
        })
        .to_string();
        seed_db(&path, Some(&bad_token), Some(&device_json()), None);
        assert!(matches!(
            read_credentials(&path),
            Err(AppError::Credentials(_))
        ));
    }

    #[test]
    fn account_key_is_stable_and_account_specific() {
        let dir = TempDir::new().unwrap();
        let path1 = dir.path().join("a.sqlite3");
        seed_db(
            &path1,
            Some(&token_json()),
            Some(&device_json()),
            Some(&profile_json()),
        );
        let one = read_credentials(&path1).unwrap();

        let path2 = dir.path().join("b.sqlite3");
        seed_db(
            &path2,
            Some(&token_json()),
            Some(&device_json()),
            Some(&profile_json()),
        );
        let one_again = read_credentials(&path2).unwrap();
        assert_eq!(one.account_key, one_again.account_key);
        assert_eq!(one.account_key, "8b4d254cee50ffb1116ee414d5b91b93239e7507");

        let other_profile =
            serde_json::json!({"arn": "arn:aws:codewhisperer:us-east-1:999:profile/XYZ"})
                .to_string();
        let path3 = dir.path().join("c.sqlite3");
        seed_db(
            &path3,
            Some(&token_json()),
            Some(&device_json()),
            Some(&other_profile),
        );
        let two = read_credentials(&path3).unwrap();
        assert_ne!(one.account_key, two.account_key);
        assert!(!one.account_key.contains("ABC"));
    }

    #[test]
    fn builder_id_accounts_in_the_same_region_have_distinct_keys() {
        let dir = TempDir::new().unwrap();
        let path1 = dir.path().join("a.sqlite3");
        seed_db(&path1, Some(&token_json()), Some(&device_json()), None);
        let one = read_credentials(&path1).unwrap();

        let path2 = dir.path().join("b.sqlite3");
        let other_token = serde_json::json!({
            "access_token": "AT2",
            "refresh_token": "OTHER-RT",
            "expires_at": "2030-01-01T00:00:00Z",
            "region": "us-east-1",
        })
        .to_string();
        seed_db(&path2, Some(&other_token), Some(&device_json()), None);
        let two = read_credentials(&path2).unwrap();

        assert_ne!(one.account_key, two.account_key);
        assert!(!one.account_key.contains("RT"));
        assert!(!two.account_key.contains("OTHER-RT"));
    }

    #[test]
    fn unsafe_region_is_rejected_before_endpoint_construction() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("data.sqlite3");
        let token = serde_json::json!({
            "access_token": "AT",
            "refresh_token": "RT",
            "expires_at": "2030-01-01T00:00:00Z",
            "region": "evil.example/#",
        })
        .to_string();
        seed_db(&path, Some(&token), Some(&device_json()), None);

        let err = read_credentials(&path).unwrap_err();
        assert!(matches!(err, AppError::Credentials(_)));
        assert!(err.to_string().contains("region"));
    }
}
