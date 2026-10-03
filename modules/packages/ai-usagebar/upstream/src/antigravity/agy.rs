//! Renew Antigravity's saved Google session by running the `agy` CLI itself.
//!
//! The saved session's access token lasts about an hour, and the only thing
//! that renews it is a running Antigravity. With the desktop app open that
//! happens in the background; with only the `agy` CLI installed nothing does
//! between the user's own runs, so the session sits expired and this program —
//! which does not ship Antigravity's OAuth client — cannot mint a new token.
//!
//! `agy models` is the lightest command that authenticates: it lists the
//! models, needs no TTY and no prompt, and rewrites the saved credential (the
//! OS keyring entry) with a fresh token as a side effect. This module runs it
//! once, bounded in time and in frequency, so the caller can read the
//! credential again. Nothing here parses `agy`'s output or touches a token.

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use chrono::{DateTime, Utc};
use tokio::process::Command;

use crate::cache::Cache;

/// `agy models` took about nine seconds on a cold start; well past that it is
/// asking for a login rather than renewing.
const RENEW_TIMEOUT: Duration = Duration::from_secs(25);
/// A refresh token that is itself dead makes every attempt fail, so failures
/// are remembered too: the widget polls every few seconds and must not spawn
/// `agy` on each poll.
const COOLDOWN_SECS: i64 = 600;
const ATTEMPT_FILE: &str = "agy_renew_attempt";

/// Where the renewal command comes from. Production discovers `agy`; a test
/// names a script of its own or turns the whole mechanism off so it can never
/// run the real CLI.
#[derive(Debug, Clone, Default)]
pub enum AgyCommand {
    /// Never run anything. What [`RemoteOverride::default`] means, so a test
    /// that does not mention `agy` is hermetic by construction.
    ///
    /// [`RemoteOverride::default`]: super::fetch::RemoteOverride
    #[default]
    Off,
    /// Look `agy` up on `PATH`, then in `~/.local/bin`.
    Discover,
    /// Run exactly this program.
    At(PathBuf),
}

impl AgyCommand {
    fn program(&self) -> Option<PathBuf> {
        match self {
            Self::Off => None,
            Self::Discover => discover(),
            Self::At(path) => Some(path.clone()),
        }
    }
}

/// `agy` on `PATH`, else `~/.local/bin/agy`: the installer's own target, which
/// a tray started by launchd or a desktop session does not have on `PATH`.
fn discover() -> Option<PathBuf> {
    let path = std::env::var_os("PATH").unwrap_or_default();
    let home = crate::cache::home_dir().ok();
    find_agy(&path, home.as_deref())
}

fn find_agy(path_var: &std::ffi::OsStr, home: Option<&Path>) -> Option<PathBuf> {
    let names: &[&str] = if cfg!(windows) {
        &["agy.exe", "agy.cmd", "agy.bat"]
    } else {
        &["agy"]
    };
    let mut dirs: Vec<PathBuf> = std::env::split_paths(path_var).collect();
    if let Some(home) = home {
        dirs.push(home.join(".local").join("bin"));
    }
    dirs.iter()
        .flat_map(|dir| names.iter().map(move |name| dir.join(name)))
        .find(|candidate| candidate.is_file())
}

/// Whether the last attempt is recent enough that another would be noise.
fn cooling_down(cache: &Cache, now: DateTime<Utc>) -> bool {
    std::fs::read_to_string(cache.dir().join(ATTEMPT_FILE))
        .ok()
        .and_then(|text| text.trim().parse::<i64>().ok())
        .is_some_and(|at| (0..COOLDOWN_SECS).contains(&(now.timestamp() - at)))
}

fn note_attempt(cache: &Cache, now: DateTime<Utc>) {
    // Best effort: failing to record only costs one more attempt next poll.
    let _ = crate::cache::atomic_write(
        &cache.dir().join(ATTEMPT_FILE),
        now.timestamp().to_string().as_bytes(),
    );
}

/// Run `agy models` so it renews the saved session. `true` means the command
/// ran and exited successfully — the caller then reads the credential again,
/// and is the only judge of whether that produced a usable token. `false`
/// covers everything else: no `agy`, cooling down, a spawn error, a nonzero
/// exit, the timeout.
pub async fn renew_session(command: &AgyCommand, cache: &Cache, now: DateTime<Utc>) -> bool {
    let Some(program) = command.program() else {
        return false;
    };
    if cooling_down(cache, now) {
        return false;
    }
    note_attempt(cache, now);

    let mut cmd = Command::new(program);
    cmd.arg("models")
        // `agy` otherwise launches its own `--bg-updater` at most every 15
        // minutes, and on Windows that child opens a console window of its
        // own that CREATE_NO_WINDOW on this spawn cannot reach. Only the
        // literal `true` is honored (`1` is ignored); this touches only this
        // run, never the user's own `agy` sessions.
        .env("AGY_CLI_DISABLE_AUTO_UPDATE", "true")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    // A vendor-CLI spawn must not inherit this process's provider keys —
    // the same discipline as running `claude` for account capture.
    for var in crate::vendor::vendor_secret_env_vars_to_remove(&[]) {
        cmd.env_remove(var);
    }
    #[cfg(windows)]
    cmd.creation_flags(crate::process::CREATE_NO_WINDOW);

    let Ok(mut child) = cmd.spawn() else {
        return false;
    };
    matches!(
        tokio::time::timeout(RENEW_TIMEOUT, child.wait()).await,
        Ok(Ok(status)) if status.success()
    )
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use tempfile::TempDir;

    fn script(dir: &Path, name: &str, body: &str) -> PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    fn cache(dir: &TempDir) -> Cache {
        let cache = Cache::at(dir.path().join("cache"));
        cache.ensure_dir().unwrap();
        cache
    }

    fn now() -> DateTime<Utc> {
        DateTime::from_timestamp(1_800_000_000, 0).unwrap()
    }

    #[tokio::test]
    async fn off_never_runs_anything() {
        let dir = TempDir::new().unwrap();
        assert!(!renew_session(&AgyCommand::Off, &cache(&dir), now()).await);
    }

    #[tokio::test]
    async fn runs_models_with_the_updater_off_and_reports_success() {
        let dir = TempDir::new().unwrap();
        let marker = dir.path().join("args");
        let agy = script(
            dir.path(),
            "agy",
            &format!(
                "echo \"$@ $AGY_CLI_DISABLE_AUTO_UPDATE\" > '{}'",
                marker.display()
            ),
        );
        assert!(renew_session(&AgyCommand::At(agy), &cache(&dir), now()).await);
        // `models`, with agy's own background updater switched off.
        assert_eq!(
            std::fs::read_to_string(marker).unwrap().trim(),
            "models true"
        );
    }

    #[tokio::test]
    async fn a_failing_command_reports_failure() {
        let dir = TempDir::new().unwrap();
        let agy = script(dir.path(), "agy", "exit 3");
        assert!(!renew_session(&AgyCommand::At(agy), &cache(&dir), now()).await);
    }

    #[tokio::test]
    async fn a_missing_program_reports_failure() {
        let dir = TempDir::new().unwrap();
        let missing = dir.path().join("no-such-agy");
        assert!(!renew_session(&AgyCommand::At(missing), &cache(&dir), now()).await);
    }

    #[tokio::test]
    async fn an_attempt_is_not_repeated_inside_the_cooldown_even_after_failure() {
        let dir = TempDir::new().unwrap();
        let cache = cache(&dir);
        let count = dir.path().join("count");
        let agy = script(
            dir.path(),
            "agy",
            &format!("echo x >> '{}'; exit 1", count.display()),
        );
        let command = AgyCommand::At(agy);
        assert!(!renew_session(&command, &cache, now()).await);
        assert!(!renew_session(&command, &cache, now() + chrono::Duration::seconds(30)).await);
        assert_eq!(std::fs::read_to_string(&count).unwrap().lines().count(), 1);
        // Past the cooldown it tries again.
        let later = now() + chrono::Duration::seconds(COOLDOWN_SECS + 1);
        assert!(!renew_session(&command, &cache, later).await);
        assert_eq!(std::fs::read_to_string(&count).unwrap().lines().count(), 2);
    }

    #[test]
    fn discovery_prefers_path_then_falls_back_to_local_bin() {
        let dir = TempDir::new().unwrap();
        let on_path = dir.path().join("bin");
        let home = dir.path().join("home");
        std::fs::create_dir_all(&on_path).unwrap();
        std::fs::create_dir_all(home.join(".local/bin")).unwrap();
        let fallback = script(&home.join(".local/bin"), "agy", "true");

        let path_var = std::env::join_paths([&on_path]).unwrap();
        assert_eq!(find_agy(&path_var, Some(&home)), Some(fallback.clone()));

        let first = script(&on_path, "agy", "true");
        assert_eq!(find_agy(&path_var, Some(&home)), Some(first));
        assert_eq!(find_agy("".as_ref(), None), None);
    }
}
