//! The only part of a Claude Desktop switch that touches the outside world:
//! stopping the app, restarting it, and writing the rollback archive.
//!
//! It sits behind a trait so the switch orchestration can be exercised against
//! a recorder — the step *ordering* is the dangerous part (snapshotting the
//! outgoing account must happen before `config.json` is rewritten, and the
//! relaunch must happen even when an earlier step failed), and ordering is
//! exactly what a test can pin down without a Mac.

use std::cell::RefCell;
use std::path::Path;
use std::process::Command;
use std::time::Duration;

use crate::display::{sanitize_untrusted_line, sanitize_untrusted_path};
use crate::error::{AppError, Result};

/// Host-level effects of a switch.
pub trait AppControl {
    /// Stop the Claude Desktop app. Must return only once it is really gone —
    /// its SQLite and LevelDB stores cannot be copied while it is writing them.
    fn quit(&self) -> Result<()>;
    /// Start it again.
    fn relaunch(&self) -> Result<()>;
    /// Write `members` (relative to `root`) into a gzipped tar at `archive`.
    fn archive(&self, archive: &Path, root: &Path, members: &[&str]) -> Result<()>;
    /// Restore a rollback archive after removing every path the attempted
    /// identity swap could have created.
    fn restore(&self, archive: &Path, root: &Path, cleanup_members: &[&str]) -> Result<()>;
}

/// The real thing. Every command is a macOS system binary at a fixed path, the
/// same approach `anthropic::keychain` takes with `security(1)` and `shasum(1)`
/// — no extra dependency, and nothing to resolve off `PATH`. On any other
/// platform these simply fail, which is harmless: there is no Claude Desktop
/// app to find there in the first place, so a switch never gets this far.
pub struct DesktopApp;

/// How long to give the app to shut down cleanly before insisting.
const QUIT_GRACE: Duration = Duration::from_secs(2);
const QUIT_POLL: Duration = Duration::from_millis(100);
const QUIT_POLLS: usize = 20;

#[cfg(unix)]
fn set_private_mode(path: &Path, mode: u32) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;

    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
        .map_err(|error| AppError::io_at(path, error))
}

#[cfg(not(unix))]
fn set_private_mode(_path: &Path, _mode: u32) -> Result<()> {
    Ok(())
}

/// Whether Claude Desktop is up.
///
/// **Not** `pgrep -x Claude`: that matches nothing while the app is running
/// (verified against a live install — `ps` lists
/// `/Applications/Claude.app/Contents/MacOS/Claude`, but neither `pgrep -x
/// Claude` nor `pgrep -f <full path>` finds it). Every liveness check therefore
/// answered "stopped" instantly, so [`AppControl::quit`] reported success
/// without ever confirming the app had exited — and would then let a switch
/// copy live SQLite and LevelDB stores, the exact corruption this guards
/// against.
///
/// AppleScript answers correctly, and asking whether an application `is
/// running` does not launch it.
///
/// Also gates the *active* account's usage read: while the app runs it owns and
/// refreshes `config.json`'s token, so ai-usagebar must read it but never
/// refresh it (that would rotate the app's live credential out from under it).
fn query_running_with(program: &Path) -> Result<bool> {
    let output = Command::new(program)
        .args(["-e", "application \"Claude\" is running"])
        .output()
        .map_err(|error| {
            AppError::Other(format!(
                "could not determine whether Claude Desktop is running: {error}"
            ))
        })?;
    parse_running_output(
        output.status.success(),
        output.status.code(),
        &output.stdout,
    )
}

fn parse_running_output(success: bool, code: Option<i32>, stdout: &[u8]) -> Result<bool> {
    if !success {
        return Err(AppError::Other(format!(
            "could not determine whether Claude Desktop is running (osascript exited {})",
            code.unwrap_or(-1)
        )));
    }
    match String::from_utf8_lossy(stdout).trim() {
        "true" => Ok(true),
        "false" => Ok(false),
        value => Err(AppError::Other(format!(
            "could not determine whether Claude Desktop is running (unexpected response {value:?})"
        ))),
    }
}

pub fn is_running() -> Result<bool> {
    query_running_with(Path::new("/usr/bin/osascript"))
}

/// The app's main process id, for the force-quit fallbacks. `pkill -x Claude`
/// misses it for the same reason `pgrep` does, so match the executable path
/// out of `ps` instead — the helper processes have distinct paths and are
/// deliberately left alone, since quitting the main process takes them with it.
fn main_pid() -> Option<String> {
    const MAIN_EXECUTABLE: &str = "/Claude.app/Contents/MacOS/Claude";

    let output = Command::new("/bin/ps")
        .args(["-Ao", "pid=,comm="])
        .output()
        .ok()?;
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .find_map(|line| {
            let (pid, command) = line.trim().split_once(char::is_whitespace)?;
            command
                .trim()
                .ends_with(MAIN_EXECUTABLE)
                .then(|| pid.to_string())
        })
}

fn signal_main(signal: &str) {
    if let Some(pid) = main_pid() {
        let _ = Command::new("/bin/kill").args([signal, &pid]).output();
    }
}

fn wait_until_stopped_with(
    mut probe: impl FnMut() -> Result<bool>,
    mut pause: impl FnMut(),
) -> Result<bool> {
    for _ in 0..QUIT_POLLS {
        if !probe()? {
            return Ok(true);
        }
        pause();
    }
    Ok(!probe()?)
}

fn wait_until_stopped() -> Result<bool> {
    wait_until_stopped_with(is_running, || std::thread::sleep(QUIT_POLL))
}

impl AppControl for DesktopApp {
    fn quit(&self) -> Result<()> {
        // Graceful first so the app tears down its own child processes; the
        // signals are the fallback for a hung app. Neither touches a `claude`
        // CLI process: the AppleScript targets the Claude application, and the
        // signals go to one pid matched on the app bundle's executable path.
        let _ = Command::new("/usr/bin/osascript")
            .args(["-e", "tell application \"Claude\" to quit"])
            .output();
        std::thread::sleep(QUIT_GRACE);
        if wait_until_stopped()? {
            return Ok(());
        }
        signal_main("-TERM");
        if wait_until_stopped()? {
            return Ok(());
        }
        signal_main("-KILL");
        if wait_until_stopped()? {
            Ok(())
        } else {
            Err(AppError::Other(
                "Claude Desktop did not stop; no account data was changed".into(),
            ))
        }
    }

    fn relaunch(&self) -> Result<()> {
        let output = Command::new("/usr/bin/open")
            .args(["-a", "Claude"])
            .output()
            .map_err(|e| AppError::Other(format!("could not relaunch Claude Desktop: {e}")))?;
        if output.status.success() {
            Ok(())
        } else {
            Err(AppError::Other(format!(
                "could not relaunch Claude Desktop (open exited {})",
                output.status.code().unwrap_or(-1)
            )))
        }
    }

    fn archive(&self, archive: &Path, root: &Path, members: &[&str]) -> Result<()> {
        if let Some(parent) = archive.parent() {
            std::fs::create_dir_all(parent).map_err(|e| AppError::io_at(parent, e))?;
            // The archive contains cookies, credentials, and browser state.
            // Restrict the directory before tar creates the file so even the
            // brief pre-chmod window is contained on Unix hosts.
            set_private_mode(parent, 0o700)?;
        }
        let output = Command::new("/usr/bin/tar")
            .arg("-czf")
            .arg(archive)
            .arg("-C")
            .arg(root)
            .arg("--")
            .args(members)
            .output()
            .map_err(|e| AppError::Other(format!("could not run `tar`: {e}")))?;
        if output.status.success() {
            set_private_mode(archive, 0o600)?;
            return Ok(());
        }
        // `tar` names the member it failed on, and members are paths from the
        // account tree rather than literals in this program.
        let detail = sanitize_untrusted_line(&String::from_utf8_lossy(&output.stderr));
        Err(AppError::Other(format!(
            "could not write the rollback archive {} (tar exited {}): {}",
            sanitize_untrusted_path(archive),
            output.status.code().unwrap_or(-1),
            detail.trim()
        )))
    }

    fn restore(&self, archive: &Path, root: &Path, cleanup_members: &[&str]) -> Result<()> {
        for member in cleanup_members {
            let path = root.join(member);
            match std::fs::symlink_metadata(&path) {
                Ok(metadata) if metadata.is_dir() => {
                    std::fs::remove_dir_all(&path).map_err(|e| AppError::io_at(&path, e))?;
                }
                Ok(_) => {
                    std::fs::remove_file(&path).map_err(|e| AppError::io_at(&path, e))?;
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(AppError::io_at(&path, error)),
            }
        }
        let output = Command::new("/usr/bin/tar")
            .arg("-xzf")
            .arg(archive)
            .arg("-C")
            .arg(root)
            .output()
            .map_err(|e| AppError::Other(format!("could not run `tar` for rollback: {e}")))?;
        if output.status.success() {
            Ok(())
        } else {
            Err(AppError::Other(format!(
                "could not restore {} (tar exited {})",
                sanitize_untrusted_path(archive),
                output.status.code().unwrap_or(-1)
            )))
        }
    }
}

/// Records what *would* happen instead of doing it. Backs `--dry-run`, and is
/// the fixture the ordering tests assert against.
#[derive(Debug, Default)]
pub struct Recorder {
    steps: RefCell<Vec<String>>,
}

impl Recorder {
    pub fn steps(&self) -> Vec<String> {
        self.steps.borrow().clone()
    }

    pub fn record(&self, step: impl Into<String>) {
        self.steps.borrow_mut().push(step.into());
    }
}

impl AppControl for Recorder {
    fn quit(&self) -> Result<()> {
        self.record("quit");
        Ok(())
    }

    fn relaunch(&self) -> Result<()> {
        self.record("relaunch");
        Ok(())
    }

    fn archive(&self, archive: &Path, _root: &Path, members: &[&str]) -> Result<()> {
        self.record(format!(
            "archive {} [{}]",
            archive.display(),
            members.join(", ")
        ));
        Ok(())
    }

    fn restore(&self, archive: &Path, _root: &Path, members: &[&str]) -> Result<()> {
        self.record(format!(
            "restore {} [{}]",
            archive.display(),
            members.join(", ")
        ));
        Ok(())
    }
}

#[cfg(test)]
mod liveness_tests {
    use super::*;

    #[test]
    fn liveness_accepts_only_explicit_boolean_output() {
        assert!(parse_running_output(true, Some(0), b"true\n").unwrap());
        assert!(!parse_running_output(true, Some(0), b"false\n").unwrap());
        assert!(parse_running_output(true, Some(0), b"unknown\n").is_err());
        assert!(parse_running_output(false, Some(1), b"false\n").is_err());
    }

    #[test]
    fn a_probe_launch_failure_is_not_treated_as_stopped() {
        let missing = Path::new("/definitely/not/an/osascript/binary");
        assert!(query_running_with(missing).is_err());
    }

    #[test]
    fn wait_aborts_on_an_unknown_liveness_state() {
        let result = wait_until_stopped_with(
            || Err(AppError::Other("probe failed".into())),
            || panic!("an unknown state must abort before sleeping"),
        );
        assert!(result.is_err());
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn rollback_archives_and_their_directory_are_private() {
        let temp = tempfile::TempDir::new().unwrap();
        let root = temp.path().join("Claude");
        let backup_dir = temp.path().join("backups");
        let archive = backup_dir.join("rollback.tar.gz");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("config.json"), b"secret state").unwrap();

        DesktopApp
            .archive(&archive, &root, &["config.json"])
            .unwrap();

        let dir_mode = std::fs::metadata(&backup_dir).unwrap().permissions().mode() & 0o777;
        let archive_mode = std::fs::metadata(&archive).unwrap().permissions().mode() & 0o777;
        assert_eq!(dir_mode, 0o700);
        assert_eq!(archive_mode, 0o600);
    }

    /// The rollback archive's path reaches this message from the account tree,
    /// not from a literal, so an escape sequence in it would repaint the line
    /// the user is reading. `tar` fails here because the archive does not
    /// exist, which reaches the failure branch without needing a subprocess
    /// seam — the same route the archive test above already takes.
    #[test]
    fn a_failed_restore_does_not_carry_a_terminal_escape_out_of_the_archive_path() {
        let temp = tempfile::TempDir::new().unwrap();
        let root = temp.path().join("Claude");
        std::fs::create_dir_all(&root).unwrap();
        let archive = temp.path().join("\x1b[2Kabsent.tar.gz");

        let error = DesktopApp
            .restore(&archive, &root, &["config.json"])
            .expect_err("tar cannot restore an archive that does not exist")
            .to_string();

        assert!(!error.contains('\u{1b}'), "{error:?}");
        assert!(
            !error.contains('\n'),
            "an embedded newline forges a line: {error:?}"
        );
        assert!(error.contains("could not restore"), "{error}");
    }
}
