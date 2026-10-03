//! Privacy-preserving cache scope for the Grok Build login.
//!
//! The billing ACP response intentionally contains no account identifier. To
//! avoid serving one login's cached usage after `grok login` switches users,
//! hash the auth and config files as opaque bytes. The digest is never shown;
//! no token, e-mail address, user id, or raw configuration is copied to the
//! ai-usagebar cache.

use std::ffi::OsString;
use std::fmt::Write as _;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::cache::home_dir;
use crate::error::Result;

const MAX_SCOPE_FILE_BYTES: u64 = 2 * 1024 * 1024;
const SCOPE_ENV: [&str; 8] = [
    "GROK_OIDC_ISSUER",
    "GROK_OIDC_CLIENT_ID",
    "GROK_AUTH_PROVIDER_COMMAND",
    "GROK_AUTH_TOKEN_TTL",
    "GROK_CLI_CHAT_PROXY_BASE_URL",
    "GROK_API_KEY",
    "XAI_API_KEY",
    "GROK_HOME",
];

#[derive(Debug, Clone)]
pub struct ScopePaths {
    pub auth: PathBuf,
    pub config: PathBuf,
}

impl ScopePaths {
    pub fn defaults() -> Result<Self> {
        Self::defaults_with(std::env::var_os("GROK_HOME"), home_dir)
    }

    fn defaults_with<F>(grok_home: Option<OsString>, fallback_home: F) -> Result<Self>
    where
        F: FnOnce() -> Result<PathBuf>,
    {
        let grok_dir = match grok_home.filter(|value| !value.is_empty()) {
            Some(path) => PathBuf::from(path),
            None => fallback_home()?.join(".grok"),
        };
        Ok(Self {
            auth: grok_dir.join("auth.json"),
            config: grok_dir.join("config.toml"),
        })
    }

    pub fn with_overrides(auth: Option<&Path>, config: Option<&Path>) -> Result<Self> {
        if let (Some(auth), Some(config)) = (auth, config) {
            return Ok(Self {
                auth: auth.to_path_buf(),
                config: config.to_path_buf(),
            });
        }
        let mut paths = Self::defaults()?;
        if let Some(auth) = auth {
            paths.auth = auth.to_path_buf();
        }
        if let Some(config) = config {
            paths.config = config.to_path_buf();
        }
        Ok(paths)
    }
}

/// Return a stable opaque cache scope, or `None` when the login state cannot
/// be read safely. `None` deliberately disables cache reuse rather than
/// risking data from another login.
pub fn fingerprint(paths: &ScopePaths) -> Option<String> {
    fingerprint_with(paths, |name| std::env::var_os(name))
}

fn fingerprint_with<F>(paths: &ScopePaths, read_env: F) -> Option<String>
where
    F: Fn(&str) -> Option<OsString>,
{
    let FileState::Present(auth) = read_bounded(&paths.auth) else {
        return None;
    };
    let config = read_bounded(&paths.config);

    let mut hasher = Sha256::new();
    hasher.update(b"ai-usagebar-supergrok-scope-v2\0auth\0");
    hasher.update(&auth);
    hasher.update(b"\0config\0");
    match config {
        FileState::Present(bytes) => {
            hasher.update(b"present\0");
            hasher.update(&bytes);
        }
        FileState::Missing => hasher.update(b"missing"),
        FileState::Unavailable => return None,
    }
    for name in SCOPE_ENV {
        hasher.update(b"\0env\0");
        hasher.update(name.as_bytes());
        match read_env(name) {
            Some(value) => {
                hasher.update(b"\0present\0");
                hasher.update(value.to_string_lossy().as_bytes());
            }
            None => hasher.update(b"\0missing"),
        }
    }
    let digest = hasher.finalize();
    let mut encoded = String::with_capacity(digest.len() * 2);
    for byte in digest {
        let _ = write!(encoded, "{byte:02x}");
    }
    Some(encoded)
}

enum FileState {
    Present(Vec<u8>),
    Missing,
    Unavailable,
}

fn read_bounded(path: &Path) -> FileState {
    // Refuse directories, devices, FIFOs, sockets, and symlinks before open.
    // Besides keeping the scope to ordinary credential/config files, this
    // prevents a configured or replaced path from blocking on a named pipe.
    let metadata = match path.symlink_metadata() {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return FileState::Missing;
        }
        Err(_) => return FileState::Unavailable,
    };
    if !metadata.file_type().is_file() || metadata.len() > MAX_SCOPE_FILE_BYTES {
        return FileState::Unavailable;
    }
    let file = match File::open(path) {
        Ok(file) => file,
        // A race after metadata lookup fails closed, including replacement
        // with a missing file. The bounded read below catches file growth.
        Err(_) => return FileState::Unavailable,
    };
    let mut bytes = Vec::new();
    if file
        .take(MAX_SCOPE_FILE_BYTES + 1)
        .read_to_end(&mut bytes)
        .is_err()
        || bytes.len() as u64 > MAX_SCOPE_FILE_BYTES
    {
        return FileState::Unavailable;
    }
    FileState::Present(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn paths(td: &TempDir) -> ScopePaths {
        ScopePaths {
            auth: td.path().join("auth.json"),
            config: td.path().join("config.toml"),
        }
    }

    fn fingerprint_without_env(paths: &ScopePaths) -> Option<String> {
        fingerprint_with(paths, |_| None)
    }

    #[test]
    fn grok_home_override_controls_default_scope_paths() {
        let paths = ScopePaths::defaults_with(Some(OsString::from("/custom/grok")), || {
            panic!("a GROK_HOME override must not consult the fallback home")
        })
        .unwrap();
        assert_eq!(paths.auth, PathBuf::from("/custom/grok/auth.json"));
        assert_eq!(paths.config, PathBuf::from("/custom/grok/config.toml"));
    }

    #[test]
    fn fingerprint_is_stable_and_contains_no_raw_identity() {
        let td = TempDir::new().unwrap();
        let paths = paths(&td);
        std::fs::write(
            &paths.auth,
            br#"{"key":"secret","user_id":"person@example.test"}"#,
        )
        .unwrap();
        std::fs::write(&paths.config, b"[grok_com_config]\n").unwrap();

        let one = fingerprint_without_env(&paths).unwrap();
        let two = fingerprint_without_env(&paths).unwrap();
        assert_eq!(one, two);
        assert_eq!(one.len(), 64);
        // Independently reproduced with `sha256sum` and OpenSSL. Keep cache
        // identities stable across hash-crate upgrades so an upgrade does not
        // silently invalidate every user's last-known-good usage snapshot.
        assert_eq!(
            one,
            "ed8be87685186d534763b874ed01adf912fddf2e929c1453c3362ca9f0d24308"
        );
        assert!(!one.contains("secret"));
        assert!(!one.contains("person"));
    }

    #[test]
    fn auth_or_config_changes_invalidate_the_scope() {
        let td = TempDir::new().unwrap();
        let paths = paths(&td);
        std::fs::write(&paths.auth, b"account-a").unwrap();
        let before = fingerprint_without_env(&paths).unwrap();

        std::fs::write(&paths.auth, b"account-b").unwrap();
        let after_login = fingerprint_without_env(&paths).unwrap();
        assert_ne!(before, after_login);

        std::fs::write(&paths.config, b"scope = 'team'").unwrap();
        assert_ne!(after_login, fingerprint_without_env(&paths).unwrap());

        let issuer_a = fingerprint_with(&paths, |name| {
            (name == "GROK_OIDC_ISSUER").then(|| OsString::from("https://idp-a.test"))
        })
        .unwrap();
        let issuer_b = fingerprint_with(&paths, |name| {
            (name == "GROK_OIDC_ISSUER").then(|| OsString::from("https://idp-b.test"))
        })
        .unwrap();
        assert_ne!(issuer_a, issuer_b);
    }

    #[test]
    fn missing_or_oversized_auth_disables_cache_reuse() {
        let td = TempDir::new().unwrap();
        let paths = paths(&td);
        assert!(fingerprint_without_env(&paths).is_none());

        let file = File::create(&paths.auth).unwrap();
        file.set_len(MAX_SCOPE_FILE_BYTES + 1).unwrap();
        assert!(fingerprint_without_env(&paths).is_none());

        std::fs::write(&paths.auth, b"valid-auth").unwrap();
        let file = File::create(&paths.config).unwrap();
        file.set_len(MAX_SCOPE_FILE_BYTES + 1).unwrap();
        assert!(fingerprint_without_env(&paths).is_none());
    }

    #[cfg(unix)]
    #[test]
    fn symlinked_scope_files_fail_closed() {
        use std::os::unix::fs::symlink;

        let td = TempDir::new().unwrap();
        let paths = paths(&td);
        let target = td.path().join("real-auth.json");
        std::fs::write(&target, b"valid-auth").unwrap();
        symlink(&target, &paths.auth).unwrap();
        assert!(fingerprint_without_env(&paths).is_none());
    }
}
