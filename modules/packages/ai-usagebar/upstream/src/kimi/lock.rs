//! Cross-process lock around a Kimi Code CLI credential refresh, speaking the
//! CLI's own lock protocol.
//!
//! Unlike every other lock in this codebase (which guards a file ai-usagebar
//! owns and therefore uses `flock` via `cache::acquire_lock_async`), this one
//! guards a file **another program** owns and refreshes on its own schedule.
//! kimi-code locks its credential store with `proper-lockfile`, whose contract
//! is a *directory*: `lock(target)` succeeds by `mkdir`ing `<target>.lock`, an
//! existing lock directory whose mtime is older than `stale` may be stolen, and
//! the holder keeps refreshing that mtime while it works. `flock` here would be
//! invisible to the CLI and both processes would rotate the same refresh token
//! at once, so this speaks the protocol the other side actually implements.
//!
//! Windows is deliberately unlocked: kimi-code disables its own lock there
//! (`if (process.platform === "win32") return undefined`), so taking one would
//! only be a lock against ourselves.

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use crate::error::{AppError, Result};

/// proper-lockfile's default `stale` for kimi-code's OAuth lock (5 s), after
/// which an abandoned lock directory may be taken over.
pub const STALE: Duration = Duration::from_secs(5);
/// How often the holder touches the lock directory. proper-lockfile refreshes
/// at `stale / 2`; matching that keeps a slow refresh from looking abandoned.
const HEARTBEAT: Duration = Duration::from_millis(2_500);
const POLL: Duration = Duration::from_millis(250);
/// Long enough to outlast a peer's refresh round-trip, short enough that a
/// widget tick never hangs on it.
pub const ACQUIRE_TIMEOUT: Duration = Duration::from_secs(20);

/// The directory `proper-lockfile` actually creates for `target`.
pub fn lock_dir_for(target: &Path) -> PathBuf {
    let mut dir = target.as_os_str().to_os_string();
    dir.push(".lock");
    PathBuf::from(dir)
}

/// Held lock. Dropping it releases the lock and stops the heartbeat.
#[derive(Debug)]
pub struct OauthLock {
    dir: PathBuf,
    heartbeat: Option<tokio::task::JoinHandle<()>>,
}

impl Drop for OauthLock {
    fn drop(&mut self) {
        if let Some(handle) = self.heartbeat.take() {
            handle.abort();
        }
        // `remove_dir_all`, not `remove_dir`: an aborted heartbeat can leave
        // its sentinel behind, and a lock directory we fail to remove would
        // block the CLI for `STALE` on every one of its own refreshes.
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// Acquire the lock for `target` (kimi-code's `<home>/oauth/kimi-code`),
/// stealing it only once it has been abandoned for [`STALE`].
pub async fn acquire(target: &Path) -> Result<OauthLock> {
    acquire_with(target, ACQUIRE_TIMEOUT, STALE, POLL).await
}

/// Seam for tests: they pass a tiny `stale`/`poll` so the steal path does not
/// need a five-second wall-clock wait.
pub async fn acquire_with(
    target: &Path,
    timeout: Duration,
    stale: Duration,
    poll: Duration,
) -> Result<OauthLock> {
    let dir = lock_dir_for(target);
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent).map_err(|e| AppError::io_at(parent, e))?;
    }

    let deadline = tokio::time::Instant::now() + timeout;
    loop {
        match std::fs::create_dir(&dir) {
            Ok(()) => return Ok(hold(dir)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                if is_stale(&dir, stale) {
                    // Best-effort steal: losing the race just means another
                    // process took it over first, and the next loop waits.
                    let _ = std::fs::remove_dir_all(&dir);
                }
            }
            Err(e) => return Err(AppError::io_at(&dir, e)),
        }
        if tokio::time::Instant::now() >= deadline {
            return Err(AppError::Transport(format!(
                "timed out waiting for the Kimi Code CLI credential lock at {}",
                crate::display::sanitize_untrusted_path(&dir)
            )));
        }
        tokio::time::sleep(poll).await;
    }
}

fn hold(dir: PathBuf) -> OauthLock {
    let beat_dir = dir.clone();
    let heartbeat = tokio::runtime::Handle::try_current().ok().map(|_| {
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(HEARTBEAT).await;
                touch(&beat_dir);
            }
        })
    });
    OauthLock { dir, heartbeat }
}

/// Bump the lock directory's mtime, which is what proper-lockfile reads to
/// decide whether a lock was abandoned. Adding and removing an entry is how a
/// POSIX directory's mtime moves — there is no `utimes` in `std`, and pulling a
/// crate in for one syscall is not worth a dependency.
fn touch(dir: &Path) {
    let sentinel = dir.join(".ai-usagebar-heartbeat");
    if std::fs::write(&sentinel, b"").is_ok() {
        let _ = std::fs::remove_file(&sentinel);
    }
}

fn is_stale(dir: &Path, stale: Duration) -> bool {
    let Ok(modified) = std::fs::metadata(dir).and_then(|m| m.modified()) else {
        // No mtime to trust: leave the lock alone rather than steal blindly.
        return false;
    };
    SystemTime::now()
        .duration_since(modified)
        .is_ok_and(|age| age > stale)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn target(td: &TempDir) -> PathBuf {
        td.path().join("oauth").join("kimi-code")
    }

    #[test]
    fn lock_dir_matches_proper_lockfile_naming() {
        assert_eq!(
            lock_dir_for(Path::new("/home/u/.kimi-code/oauth/kimi-code")),
            PathBuf::from("/home/u/.kimi-code/oauth/kimi-code.lock")
        );
    }

    #[tokio::test]
    async fn acquire_creates_the_lock_directory_and_drop_removes_it() {
        let td = TempDir::new().unwrap();
        let target = target(&td);
        let dir = lock_dir_for(&target);
        {
            let _lock = acquire_with(&target, Duration::from_secs(1), STALE, POLL)
                .await
                .unwrap();
            assert!(dir.is_dir());
        }
        assert!(!dir.exists());
    }

    #[tokio::test]
    async fn a_fresh_foreign_lock_is_waited_out_not_stolen() {
        let td = TempDir::new().unwrap();
        let target = target(&td);
        let dir = lock_dir_for(&target);
        std::fs::create_dir_all(&dir).unwrap();

        let err = acquire_with(
            &target,
            Duration::from_millis(60),
            Duration::from_secs(3_600),
            Duration::from_millis(10),
        )
        .await
        .unwrap_err();
        assert!(matches!(err, AppError::Transport(_)), "{err:?}");
        assert!(dir.is_dir(), "a live peer's lock must survive");
    }

    #[tokio::test]
    async fn an_abandoned_lock_is_stolen_once_stale() {
        let td = TempDir::new().unwrap();
        let target = target(&td);
        let dir = lock_dir_for(&target);
        std::fs::create_dir_all(&dir).unwrap();

        let lock = acquire_with(
            &target,
            Duration::from_secs(2),
            Duration::ZERO,
            Duration::from_millis(10),
        )
        .await
        .unwrap();
        assert!(dir.is_dir());
        drop(lock);
        assert!(!dir.exists());
    }

    #[tokio::test]
    async fn a_leftover_heartbeat_sentinel_does_not_block_release() {
        let td = TempDir::new().unwrap();
        let target = target(&td);
        let dir = lock_dir_for(&target);
        {
            let _lock = acquire_with(&target, Duration::from_secs(1), STALE, POLL)
                .await
                .unwrap();
            std::fs::write(dir.join(".ai-usagebar-heartbeat"), b"").unwrap();
        }
        assert!(!dir.exists());
    }

    #[test]
    fn touch_moves_the_directory_mtime_forward() {
        let td = TempDir::new().unwrap();
        let dir = td.path().join("kimi-code.lock");
        std::fs::create_dir(&dir).unwrap();
        let before = std::fs::metadata(&dir).unwrap().modified().unwrap();
        // Filesystem mtime granularity can be coarse; assert the touch is not
        // *older*, and that the sentinel never outlives the call.
        touch(&dir);
        let after = std::fs::metadata(&dir).unwrap().modified().unwrap();
        assert!(after >= before);
        assert!(!dir.join(".ai-usagebar-heartbeat").exists());
    }
}
