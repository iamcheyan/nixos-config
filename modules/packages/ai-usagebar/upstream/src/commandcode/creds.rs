//! Locate the Command Code OAuth credential a local harness already holds.
//!
//! Command Code is reachable through several agent harnesses, and each files
//! the same OAuth credential under its own key in its own file. This module
//! reads them; it never writes. Refreshing an expired token belongs to the
//! CLI that owns the file, and racing it here would corrupt state shared by
//! every harness on the machine.

use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::cache::home_dir;
use crate::error::{AppError, Result};

/// Files searched in order; the first holding a live credential wins.
pub const AUTH_FILES: &[&str] = &[OFFICIAL_AUTH_FILE, ".pi/agent/auth.json"];

/// The Command Code CLI's own file — the only one whose whole contents belong
/// to Command Code. The others are shared harness keystores, which is why the
/// unkeyed `apiKey` fallback below is scoped to this one.
const OFFICIAL_AUTH_FILE: &str = ".commandcode/auth.json";

/// Keys a harness may file the credential under.
const CREDENTIAL_KEYS: &[&str] = &["command-code", "commandcode"];

pub const SIGNED_OUT: &str =
    "Command Code is not signed in. Run `commandcode` and sign in, or set COMMANDCODE_API_KEY.";
pub const EXPIRED: &str = "Command Code sign-in expired. Run `commandcode` to sign in again.";

/// A credential and where it came from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Credential {
    pub token: String,
    pub source: String,
}

/// One candidate found on disk, before expiry is considered.
struct Candidate {
    token: String,
    expires_ms: Option<i64>,
}

/// Default search paths, resolved against the OS home convention.
pub fn default_paths() -> Result<Vec<PathBuf>> {
    let home = home_dir()?;
    Ok(AUTH_FILES.iter().map(|rel| home.join(rel)).collect())
}

/// Read whichever credential shape a harness wrote into `path`.
///
/// A missing or malformed file yields `None` rather than an error: one broken
/// harness must not mask a working one further down the list.
pub fn read_from(path: &Path) -> Option<Credential> {
    let text = std::fs::read_to_string(path).ok()?;
    let value: Value = serde_json::from_str(&text).ok()?;
    let object = value.as_object()?;

    // `apiKey` is unkeyed, so it is only consulted in Command Code's own file,
    // where the whole document is Command Code's. A harness keystore holds
    // every provider the user has signed into — pi's `auth.json` is typed
    // `Record<providerId, Credential>` and carries their Anthropic, OpenAI and
    // OpenRouter credentials — so a key that names no provider must not be
    // read out of one, whatever shape a future version gives it.
    let generic = path
        .ends_with(OFFICIAL_AUTH_FILE)
        .then(|| object.get("apiKey"))
        .flatten();
    let candidates = CREDENTIAL_KEYS
        .iter()
        .filter_map(|key| object.get(*key))
        .chain(generic)
        .filter_map(candidate);

    for found in candidates {
        if found.expires_ms.is_some_and(is_past) {
            continue;
        }
        return Some(Credential {
            token: found.token,
            source: path.display().to_string(),
        });
    }
    None
}

/// Production resolver: the env override, then configured paths, then the
/// platform defaults. Tests use [`resolve_from`], which takes both as inputs.
pub fn resolve(configured: Option<&[PathBuf]>) -> Result<Credential> {
    let paths = effective_paths(configured)?;
    resolve_from(std::env::var("COMMANDCODE_API_KEY").ok().as_deref(), &paths)
}

/// The effective search list: a configured override when it names at least one
/// path, else the platform defaults.
pub fn effective_paths(configured: Option<&[PathBuf]>) -> Result<Vec<PathBuf>> {
    match configured {
        Some(paths) if !paths.is_empty() => Ok(paths.to_vec()),
        _ => default_paths(),
    }
}

/// Resolve one credential from the environment, then each path in turn.
pub fn resolve_from(env_key: Option<&str>, paths: &[PathBuf]) -> Result<Credential> {
    if let Some(key) = env_key.map(str::trim).filter(|key| !key.is_empty()) {
        return Ok(Credential {
            token: key.to_string(),
            source: "COMMANDCODE_API_KEY".to_string(),
        });
    }
    for path in paths {
        if let Some(credential) = read_from(path) {
            return Ok(credential);
        }
    }
    Err(AppError::Credentials(message_for(paths)))
}

/// Distinguish "never signed in" from "signed in, but the token lapsed" so the
/// tooltip can tell the user which one to fix.
fn message_for(paths: &[PathBuf]) -> String {
    let any_expired = paths.iter().any(|path| {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str::<Value>(&text).ok())
            .and_then(|value| {
                let object = value.as_object()?;
                let generic = path
                    .ends_with(OFFICIAL_AUTH_FILE)
                    .then(|| object.get("apiKey"))
                    .flatten();
                let found = CREDENTIAL_KEYS
                    .iter()
                    .filter_map(|key| object.get(*key))
                    .chain(generic)
                    .filter_map(candidate)
                    .any(|found| found.expires_ms.is_some_and(is_past));
                Some(found)
            })
            .unwrap_or(false)
    });
    if any_expired { EXPIRED } else { SIGNED_OUT }.to_string()
}

fn candidate(value: &Value) -> Option<Candidate> {
    if let Some(token) = value.as_str() {
        let token = token.trim();
        return (!token.is_empty()).then(|| Candidate {
            token: token.to_string(),
            expires_ms: None,
        });
    }
    let object = value.as_object()?;
    let token = ["access", "apiKey", "key"]
        .iter()
        .filter_map(|field| object.get(*field))
        .filter_map(Value::as_str)
        .map(str::trim)
        .find(|token| !token.is_empty())?;
    Some(Candidate {
        token: token.to_string(),
        expires_ms: object.get("expires").and_then(Value::as_i64),
    })
}

fn is_past(expires_ms: i64) -> bool {
    expires_ms > 0 && expires_ms <= chrono::Utc::now().timestamp_millis()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(dir: &Path, name: &str, value: Value) -> PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, serde_json::to_vec(&value).unwrap()).unwrap();
        path
    }

    fn future_ms() -> i64 {
        chrono::Utc::now().timestamp_millis() + 86_400_000
    }

    fn past_ms() -> i64 {
        chrono::Utc::now().timestamp_millis() - 86_400_000
    }

    #[test]
    fn reads_the_official_cli_oauth_shape() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(
            dir.path(),
            "auth.json",
            serde_json::json!({
                "command-code": {"type": "oauth", "access": "tok", "expires": future_ms()}
            }),
        );

        assert_eq!(read_from(&path).unwrap().token, "tok");
    }

    /// A harness keystore holds every provider the user signed into — pi types
    /// its `auth.json` as `Record<providerId, Credential>` and carries their
    /// Anthropic, OpenAI and OpenRouter credentials there. A key that names no
    /// provider therefore must not be read out of one: only the provider-keyed
    /// lookup applies, and only Command Code's own file may fall back to the
    /// unkeyed `apiKey`.
    #[test]
    fn the_unkeyed_apikey_is_only_read_from_command_codes_own_file() {
        let dir = tempfile::tempdir().unwrap();
        let body = serde_json::json!({ "apiKey": "another-providers-secret" });

        let shared = dir.path().join(".pi/agent");
        std::fs::create_dir_all(&shared).unwrap();
        let shared = write(&shared, "auth.json", body.clone());
        assert_eq!(
            read_from(&shared),
            None,
            "an unkeyed apiKey in a shared harness keystore is not ours to read"
        );

        let own = dir.path().join(".commandcode");
        std::fs::create_dir_all(&own).unwrap();
        let own = write(&own, "auth.json", body);
        assert_eq!(
            read_from(&own).map(|c| c.token),
            Some("another-providers-secret".to_string()),
            "Command Code's own file still accepts a pasted key"
        );
    }

    #[test]
    fn reads_the_pi_oauth_shape() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(
            dir.path(),
            "auth.json",
            serde_json::json!({
                "openai-codex": {"type": "oauth", "access": "other"},
                "commandcode": {"type": "oauth", "access": "tok", "expires": future_ms()}
            }),
        );

        assert_eq!(read_from(&path).unwrap().token, "tok");
    }

    #[test]
    fn reads_a_legacy_plain_string_credential() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(
            dir.path(),
            "auth.json",
            serde_json::json!({"commandcode": "plain-token"}),
        );

        assert_eq!(read_from(&path).unwrap().token, "plain-token");
    }

    #[test]
    fn an_expired_token_is_not_offered() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(
            dir.path(),
            "auth.json",
            serde_json::json!({
                "command-code": {"type": "oauth", "access": "tok", "expires": past_ms()}
            }),
        );

        assert!(read_from(&path).is_none());
    }

    #[test]
    fn malformed_and_missing_files_are_skipped_not_fatal() {
        let dir = tempfile::tempdir().unwrap();
        let broken = dir.path().join("broken.json");
        std::fs::write(&broken, "{not json").unwrap();

        assert!(read_from(&broken).is_none());
        assert!(read_from(&dir.path().join("absent.json")).is_none());
    }

    #[test]
    fn env_key_outranks_every_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(
            dir.path(),
            "auth.json",
            serde_json::json!({"commandcode": {"access": "from-file"}}),
        );

        let credential = resolve_from(Some("from-env"), &[path]).unwrap();

        assert_eq!(credential.token, "from-env");
        assert_eq!(credential.source, "COMMANDCODE_API_KEY");
    }

    #[test]
    fn a_stale_harness_does_not_mask_a_live_one() {
        let dir = tempfile::tempdir().unwrap();
        let stale = write(
            dir.path(),
            "stale.json",
            serde_json::json!({
                "command-code": {"access": "stale", "expires": past_ms()}
            }),
        );
        let live = write(
            dir.path(),
            "live.json",
            serde_json::json!({
                "commandcode": {"access": "live", "expires": future_ms()}
            }),
        );

        assert_eq!(resolve_from(None, &[stale, live]).unwrap().token, "live");
    }

    #[test]
    fn all_expired_reports_expiry_and_nothing_reports_signed_out() {
        let dir = tempfile::tempdir().unwrap();
        let stale = write(
            dir.path(),
            "stale.json",
            serde_json::json!({
                "command-code": {"access": "stale", "expires": past_ms()}
            }),
        );

        let expired = resolve_from(None, std::slice::from_ref(&stale)).unwrap_err();
        assert!(expired.to_string().contains("expired"), "{expired}");

        let absent = resolve_from(None, &[dir.path().join("absent.json")]).unwrap_err();
        assert!(absent.to_string().contains("not signed in"), "{absent}");

        let shared_dir = dir.path().join(".pi/agent");
        std::fs::create_dir_all(&shared_dir).unwrap();
        let unrelated = write(
            &shared_dir,
            "auth.json",
            serde_json::json!({
                "apiKey": {"access": "other", "expires": past_ms()}
            }),
        );
        let signed_out = resolve_from(None, &[unrelated]).unwrap_err();
        assert!(
            signed_out.to_string().contains("not signed in"),
            "an unrelated expired apiKey must not be treated as Command Code: {signed_out}"
        );
    }

    #[test]
    fn default_paths_only_include_verified_credential_files() {
        let paths = default_paths().unwrap();

        assert_eq!(
            AUTH_FILES,
            &[".commandcode/auth.json", ".pi/agent/auth.json"]
        );
        assert_eq!(paths.len(), AUTH_FILES.len());
        assert!(paths[0].ends_with(AUTH_FILES[0]));
        assert!(paths[1].ends_with(AUTH_FILES[1]));
    }
}
