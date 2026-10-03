//! Kimi — weekly subscription quota + 5h rolling window from
//! `/coding/v1/usages`.
//!
//! Two credentials reach the same endpoint: an API key, or the Kimi Code CLI's
//! OAuth login — the one a subscriber already has locally, with no key to
//! create or paste. `oauth.rs` owns the CLI's token file and its refresh;
//! `lock.rs` keeps that refresh from racing the CLI's own.

pub mod fetch;
pub mod lock;
pub mod oauth;
pub mod types;
pub mod vendor;

use std::path::Path;

pub use fetch::fetch_snapshot;

use crate::config::KimiConfig;
use crate::error::{AppError, Result};

/// Pick the credential and the deployment for a configured Kimi vendor.
///
/// An API key wins when one is set: it is the explicit choice, it needs no
/// local CLI, and it is what every pre-subscription install already has
/// configured. Otherwise the Kimi Code CLI's login is used, and only if
/// neither exists does this fail — with both remedies named, since which one
/// applies depends on whether the user has a subscription or a platform
/// account.
pub fn resolve_auth(cfg: &KimiConfig) -> Result<(fetch::Auth, fetch::Endpoints)> {
    let home = oauth::default_home()?;
    let api_key = crate::config::optional_api_key(&cfg.api_key_env, cfg.api_key.as_deref());
    resolve_auth_in(cfg, &home, api_key)
}

/// Test seam for [`resolve_auth`]: the kimi-code home and the resolved API key
/// are injected, so no test reads a real `$HOME` or an ambient env var.
pub fn resolve_auth_in(
    cfg: &KimiConfig,
    home: &Path,
    api_key: Option<String>,
) -> Result<(fetch::Auth, fetch::Endpoints)> {
    let region = match oauth::Region::parse(&cfg.region) {
        Some(region) => region,
        // "auto" (and anything `validate` let through) follows the CLI's own
        // install marker, defaulting to mainland exactly as kimi-code does.
        None => oauth::read_region_marker(home).unwrap_or(oauth::Region::MainlandCn),
    };
    let endpoints = fetch::Endpoints::for_region(region);

    if let Some(key) = api_key {
        return Ok((fetch::Auth::ApiKey(key), endpoints));
    }

    let kimi_code = match cfg.credentials_path.clone() {
        Some(path) => fetch::KimiCodeAuth::with_credentials_path(home, path),
        None => fetch::KimiCodeAuth::in_home(home),
    };
    if oauth::is_logged_in(&kimi_code.credentials_path) {
        return Ok((fetch::Auth::KimiCode(kimi_code), endpoints));
    }

    // Name the file that was actually checked, not just the remedy: with
    // `credentials_path` or a relocated `KIMI_CODE_HOME` in play, "log in with
    // the CLI" is useless advice if the user logged in somewhere this build
    // never looked. Sanitized because the path can carry a configured value.
    Err(AppError::Credentials(format!(
        "Kimi: no credentials. Either log in with the Kimi Code CLI (`kimi`) — its login is \
         read from {} — or set an API key in {} or `api_key` under [kimi] in {}.",
        crate::display::sanitize_untrusted_path(&kimi_code.credentials_path),
        cfg.api_key_env,
        crate::config::config_path_hint()
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn logged_in_home(td: &TempDir) -> std::path::PathBuf {
        let home = td.path().join(".kimi-code");
        let path = oauth::credentials_path_in(&home);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(
            &path,
            r#"{"access_token":"at","refresh_token":"rt","expires_at":1,"expires_in":900,
                "scope":"kimi-code","token_type":"Bearer"}"#,
        )
        .unwrap();
        home
    }

    #[test]
    fn an_api_key_wins_over_a_cli_login() {
        let td = TempDir::new().unwrap();
        let home = logged_in_home(&td);
        let (auth, endpoints) =
            resolve_auth_in(&KimiConfig::default(), &home, Some("sk-test".into())).unwrap();
        assert!(matches!(auth, fetch::Auth::ApiKey(key) if key == "sk-test"));
        assert_eq!(endpoints.usages, "https://api.kimi.com/coding/v1/usages");
    }

    #[test]
    fn a_cli_login_is_used_when_no_api_key_is_set() {
        let td = TempDir::new().unwrap();
        let home = logged_in_home(&td);
        let (auth, _) = resolve_auth_in(&KimiConfig::default(), &home, None).unwrap();
        match auth {
            fetch::Auth::KimiCode(kimi_code) => {
                assert_eq!(
                    kimi_code.credentials_path,
                    oauth::credentials_path_in(&home)
                );
                assert_eq!(kimi_code.lock_target, oauth::lock_target_in(&home));
            }
            other => panic!("expected a Kimi Code login, got {other:?}"),
        }
    }

    #[test]
    fn no_key_and_no_login_names_both_remedies_and_the_path_checked() {
        let td = TempDir::new().unwrap();
        let err = resolve_auth_in(&KimiConfig::default(), td.path(), None).unwrap_err();
        let message = err.to_string();
        assert!(matches!(err, AppError::Credentials(_)), "{err:?}");
        assert!(message.contains("Kimi Code CLI"), "{message}");
        assert!(message.contains("KIMI_API_KEY"), "{message}");
        // The file that was actually consulted, so "log in with the CLI" can be
        // acted on when the home is not the default one.
        assert!(message.contains("kimi-code.json"), "{message}");
    }

    #[test]
    fn the_reported_path_follows_a_configured_credentials_path() {
        let td = TempDir::new().unwrap();
        let cfg = KimiConfig {
            credentials_path: Some(td.path().join("relocated").join("creds.json")),
            ..KimiConfig::default()
        };
        let message = resolve_auth_in(&cfg, td.path(), None)
            .unwrap_err()
            .to_string();
        assert!(message.contains("relocated"), "{message}");
        assert!(!message.contains("kimi-code.json"), "{message}");
    }

    #[test]
    fn a_logged_out_cli_is_not_a_credential() {
        let td = TempDir::new().unwrap();
        let home = logged_in_home(&td);
        std::fs::write(
            oauth::credentials_path_in(&home),
            r#"{"access_token":"","refresh_token":"","expires_at":0}"#,
        )
        .unwrap();
        assert!(resolve_auth_in(&KimiConfig::default(), &home, None).is_err());
    }

    #[test]
    fn the_region_marker_picks_the_deployment_and_config_overrides_it() {
        let td = TempDir::new().unwrap();
        let home = logged_in_home(&td);
        std::fs::write(home.join("region"), "global").unwrap();

        let (_, endpoints) = resolve_auth_in(&KimiConfig::default(), &home, None).unwrap();
        assert_eq!(endpoints.usages, "https://api.kimi.ai/coding/v1/usages");
        assert_eq!(endpoints.token, "https://auth.kimi.ai/api/oauth/token");

        let pinned = KimiConfig {
            region: "cn".into(),
            ..KimiConfig::default()
        };
        let (_, endpoints) = resolve_auth_in(&pinned, &home, None).unwrap();
        assert_eq!(endpoints.usages, "https://api.kimi.com/coding/v1/usages");
    }

    #[test]
    fn a_configured_credentials_path_is_honored() {
        let td = TempDir::new().unwrap();
        let home = logged_in_home(&td);
        let moved = td.path().join("elsewhere.json");
        std::fs::copy(oauth::credentials_path_in(&home), &moved).unwrap();

        let cfg = KimiConfig {
            credentials_path: Some(moved.clone()),
            ..KimiConfig::default()
        };
        let (auth, _) = resolve_auth_in(&cfg, &home, None).unwrap();
        match auth {
            fetch::Auth::KimiCode(kimi_code) => {
                assert_eq!(kimi_code.credentials_path, moved);
                assert_eq!(kimi_code.lock_target, oauth::lock_target_in(&home));
            }
            other => panic!("expected a Kimi Code login, got {other:?}"),
        }
    }
}
