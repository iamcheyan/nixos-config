//! Secure, versioned Nous credential storage.
//!
//! The store is independent from every other provider's credentials.  It uses
//! a sibling lock and same-directory atomic replacement so a refresh either
//! leaves the old complete document or exposes the new complete document.

use std::collections::BTreeMap;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;

use chrono::{DateTime, Utc};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use tempfile::Builder;
use thiserror::Error;

pub const CREDENTIAL_STORE_VERSION: u32 = 1;
pub const DEFAULT_CREDENTIALS_FILE: &str = "credentials.json";
pub const CREDENTIALS_DIR_MODE: u32 = 0o700;
pub const CREDENTIALS_FILE_MODE: u32 = 0o600;

#[derive(Debug, Error)]
pub enum CredentialError {
    #[error("credential I/O error at {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
    #[error("credential document is invalid: {0}")]
    Invalid(String),
    #[error("credential document is unsafe at {path}: {reason}")]
    Unsafe { path: PathBuf, reason: &'static str },
    #[error("credential document could not be decoded")]
    Decode,
    #[error("credential lock could not be acquired at {path}: {source}")]
    Lock {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
}

pub type Result<T> = std::result::Result<T, CredentialError>;

/// A secret-bearing Nous credential.  Do not derive `Debug` for this type.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NousCredential {
    pub client_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: DateTime<Utc>,
}

impl fmt::Debug for NousCredential {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("NousCredential")
            .field("client_id", &self.client_id)
            .field("access_token", &"<redacted>")
            .field("refresh_token", &"<redacted>")
            .field("expires_at", &self.expires_at)
            .finish()
    }
}

impl NousCredential {
    pub fn validate(&self) -> Result<()> {
        if self.client_id.trim().is_empty() {
            return Err(CredentialError::Invalid("client_id is empty".into()));
        }
        if self.access_token.trim().is_empty() {
            return Err(CredentialError::Invalid("access token is empty".into()));
        }
        if self.refresh_token.trim().is_empty() {
            return Err(CredentialError::Invalid("refresh token is empty".into()));
        }
        if self.expires_at.timestamp() < 0 {
            return Err(CredentialError::Invalid("expiration is invalid".into()));
        }
        Ok(())
    }
}

/// Versioned top-level credential document.  Unknown top-level values are
/// preserved so logout does not erase future unrelated credential entries.
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct CredentialDocument {
    pub version: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nous: Option<NousCredential>,
    #[serde(flatten)]
    other: BTreeMap<String, serde_json::Value>,
}

impl fmt::Debug for CredentialDocument {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CredentialDocument")
            .field("version", &self.version)
            .field("nous", &self.nous.as_ref().map(|_| "<present>"))
            .field("other_keys", &self.other.keys().collect::<Vec<_>>())
            .finish()
    }
}

impl CredentialDocument {
    pub fn new(nous: Option<NousCredential>) -> Self {
        Self {
            version: CREDENTIAL_STORE_VERSION,
            nous,
            other: BTreeMap::new(),
        }
    }

    pub fn validate(&self) -> Result<()> {
        if self.version != CREDENTIAL_STORE_VERSION {
            return Err(CredentialError::Invalid(format!(
                "unsupported credential document version {}",
                self.version
            )));
        }
        if let Some(nous) = &self.nous {
            nous.validate()?;
        }
        Ok(())
    }

    /// Test seam for proving that writes preserve unrelated future entries.
    /// Gated like the `tests` module below, which is `unix`-only because every
    /// assertion in it turns on file modes.
    #[cfg(all(test, unix))]
    fn insert_other(&mut self, key: impl Into<String>, value: serde_json::Value) {
        self.other.insert(key.into(), value);
    }
}

/// Injectable current-owner lookup.  The trait keeps the UID source separate
/// from store logic and lets tests/coordinators provide a deterministic UID.
pub trait OwnerIdProvider: Send + Sync {
    fn current_uid(&self) -> io::Result<u32>;
}

#[derive(Debug, Default)]
pub struct ProcessOwner;

impl OwnerIdProvider for ProcessOwner {
    fn current_uid(&self) -> io::Result<u32> {
        #[cfg(unix)]
        {
            // Unlike `/proc/self`, this is available on every supported Unix,
            // including macOS, without introducing an unsafe FFI call here.
            Ok(rustix::process::geteuid().as_raw())
        }
        #[cfg(not(unix))]
        {
            Ok(0)
        }
    }
}

/// A file-backed credential store with an injectable path and owner policy.
pub struct CredentialStore {
    path: PathBuf,
    owner: Arc<dyn OwnerIdProvider>,
}

impl fmt::Debug for CredentialStore {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CredentialStore")
            .field("path", &self.path)
            .finish()
    }
}

impl Clone for CredentialStore {
    fn clone(&self) -> Self {
        Self {
            path: self.path.clone(),
            owner: Arc::clone(&self.owner),
        }
    }
}

impl CredentialStore {
    pub fn at(path: impl Into<PathBuf>) -> Self {
        Self {
            path: path.into(),
            owner: Arc::new(ProcessOwner),
        }
    }

    pub fn with_owner_provider(path: impl Into<PathBuf>, owner: Arc<dyn OwnerIdProvider>) -> Self {
        Self {
            path: path.into(),
            owner,
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn lock_path(&self) -> PathBuf {
        let name = self
            .path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(DEFAULT_CREDENTIALS_FILE);
        self.path.with_file_name(format!("{name}.lock"))
    }

    pub fn acquire_lock(&self) -> Result<CredentialLock> {
        ensure_private_parent(self.parent(), &self.owner)?;
        let path = self.lock_path();
        reject_symlink(&path)?;
        let file = open_private_lock_file(&path).map_err(|source| io_at(&path, source))?;
        validate_file_metadata(&path, &file, &self.owner)?;
        file.lock_exclusive()
            .map_err(|source| CredentialError::Lock {
                path: path.clone(),
                source,
            })?;
        Ok(CredentialLock { file, path })
    }

    pub fn read(&self) -> Result<Option<CredentialDocument>> {
        let _lock = self.acquire_lock()?;
        self.read_unlocked()
    }

    pub fn write(&self, document: &CredentialDocument) -> Result<()> {
        document.validate()?;
        let _lock = self.acquire_lock()?;
        self.write_unlocked(document)
    }

    /// Replace a document while the caller holds this store's exclusive lock.
    /// This is the seam used by the async refresh flow; it never performs an
    /// exchange after releasing the lock.
    pub fn write_locked(&self, lock: &CredentialLock, document: &CredentialDocument) -> Result<()> {
        if lock.path != self.lock_path() {
            return Err(CredentialError::Lock {
                path: self.lock_path(),
                source: io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "lock belongs to another store",
                ),
            });
        }
        document.validate()?;
        self.write_unlocked(document)
    }

    pub fn logout(&self) -> Result<()> {
        let _lock = self.acquire_lock()?;
        let Some(mut document) = self.read_unlocked()? else {
            return Ok(());
        };
        if document.nous.is_none() {
            return Ok(());
        }
        document.nous = None;
        if document.other.is_empty() {
            reject_symlink(&self.path)?;
            fs::remove_file(&self.path).map_err(|source| io_at(&self.path, source))?;
            sync_parent(self.parent())?;
        } else {
            self.write_unlocked(&document)?;
        }
        Ok(())
    }

    pub fn read_unlocked(&self) -> Result<Option<CredentialDocument>> {
        reject_symlink(&self.path)?;
        let metadata = match fs::symlink_metadata(&self.path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(source) => return Err(io_at(&self.path, source)),
        };
        if !metadata.is_file() {
            return Err(CredentialError::Unsafe {
                path: self.path.clone(),
                reason: "credential path is not a regular file",
            });
        }
        validate_metadata(&self.path, &metadata, &self.owner)?;
        let bytes = fs::read(&self.path).map_err(|source| io_at(&self.path, source))?;
        let document: CredentialDocument =
            serde_json::from_slice(&bytes).map_err(|_| CredentialError::Decode)?;
        document.validate()?;
        Ok(Some(document))
    }

    fn write_unlocked(&self, document: &CredentialDocument) -> Result<()> {
        ensure_private_parent(self.parent(), &self.owner)?;
        reject_symlink(&self.path)?;
        if let Ok(metadata) = fs::symlink_metadata(&self.path) {
            validate_metadata(&self.path, &metadata, &self.owner)?;
        }

        let mut temporary = Builder::new()
            .prefix(".credentials.json.")
            .tempfile_in(self.parent())
            .map_err(|source| io_at(self.parent(), source))?;
        set_private_permissions(temporary.as_file(), CREDENTIALS_FILE_MODE)
            .map_err(|source| io_at(temporary.path(), source))?;
        let bytes = serde_json::to_vec_pretty(document).map_err(|_| {
            CredentialError::Invalid("credential document could not be encoded".into())
        })?;
        temporary
            .as_file_mut()
            .write_all(&bytes)
            .map_err(|source| io_at(temporary.path(), source))?;
        temporary
            .as_file()
            .sync_all()
            .map_err(|source| io_at(temporary.path(), source))?;

        // Recheck immediately before replacing the destination.  The caller
        // holds the sibling lock; a symlink is never intentionally replaced.
        reject_symlink(&self.path)?;
        temporary
            .persist(&self.path)
            .map_err(|error| io_at(&self.path, error.error))?;
        sync_parent(self.parent())?;

        let metadata =
            fs::symlink_metadata(&self.path).map_err(|source| io_at(&self.path, source))?;
        validate_metadata(&self.path, &metadata, &self.owner)
    }

    fn parent(&self) -> &Path {
        self.path.parent().unwrap_or_else(|| Path::new("."))
    }
}

/// An exclusive sibling lock.  Dropping it releases the lock before any
/// caller can observe a subsequent refresh/write operation.
pub struct CredentialLock {
    file: File,
    path: PathBuf,
}

impl fmt::Debug for CredentialLock {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CredentialLock")
            .field("path", &self.path)
            .finish()
    }
}

impl Drop for CredentialLock {
    fn drop(&mut self) {
        let _ = FileExt::unlock(&self.file);
    }
}

impl Default for CredentialStore {
    fn default() -> Self {
        Self::at(default_credentials_path())
    }
}

pub fn default_credentials_path() -> PathBuf {
    directories::ProjectDirs::from("", "", "ai-usagebar")
        .map(|project| project.config_dir().join(DEFAULT_CREDENTIALS_FILE))
        .unwrap_or_else(|| PathBuf::from(".config/ai-usagebar/credentials.json"))
}

fn ensure_private_parent(path: &Path, owner: &Arc<dyn OwnerIdProvider>) -> Result<()> {
    let created = !path.exists();
    if created {
        fs::create_dir_all(path).map_err(|source| io_at(path, source))?;
    }
    let metadata = fs::symlink_metadata(path).map_err(|source| io_at(path, source))?;
    if !metadata.is_dir() {
        return Err(CredentialError::Unsafe {
            path: path.to_path_buf(),
            reason: "credential parent is not a directory",
        });
    }
    validate_owner(path, &metadata, owner)?;
    #[cfg(unix)]
    {
        let mode = file_mode(&metadata);
        if created {
            set_private_permissions_path(path, CREDENTIALS_DIR_MODE)
                .map_err(|source| io_at(path, source))?;
            let after = fs::symlink_metadata(path).map_err(|source| io_at(path, source))?;
            if file_mode(&after) != CREDENTIALS_DIR_MODE {
                return Err(CredentialError::Unsafe {
                    path: path.to_path_buf(),
                    reason: "new credential parent must be mode 0700",
                });
            }
        } else if mode & 0o022 != 0 {
            // `~/.config/ai-usagebar` predates this credential store and is
            // normally 0755. A current-user-owned, non-writable parent is safe
            // with the credential and lock files themselves fixed at 0600.
            return Err(CredentialError::Unsafe {
                path: path.to_path_buf(),
                reason: "credential parent must not be group- or world-writable",
            });
        }
    }
    Ok(())
}

fn open_private_lock_file(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.create(true).read(true).write(true);
    #[cfg(unix)]
    options.mode(CREDENTIALS_FILE_MODE);
    options.open(path)
}

fn validate_metadata(
    path: &Path,
    metadata: &fs::Metadata,
    owner: &Arc<dyn OwnerIdProvider>,
) -> Result<()> {
    if metadata.file_type().is_symlink() {
        return Err(CredentialError::Unsafe {
            path: path.to_path_buf(),
            reason: "credential path is a symlink",
        });
    }
    if !metadata.is_file() {
        return Err(CredentialError::Unsafe {
            path: path.to_path_buf(),
            reason: "credential path is not a regular file",
        });
    }
    validate_owner(path, metadata, owner)?;
    #[cfg(unix)]
    {
        if file_mode(metadata) != CREDENTIALS_FILE_MODE {
            return Err(CredentialError::Unsafe {
                path: path.to_path_buf(),
                reason: "credential file must be mode 0600",
            });
        }
    }
    Ok(())
}

fn validate_file_metadata(
    path: &Path,
    file: &File,
    owner: &Arc<dyn OwnerIdProvider>,
) -> Result<()> {
    let metadata = file.metadata().map_err(|source| io_at(path, source))?;
    validate_metadata(path, &metadata, owner)
}

fn validate_owner(
    path: &Path,
    metadata: &fs::Metadata,
    owner: &Arc<dyn OwnerIdProvider>,
) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let uid = owner.current_uid().map_err(|source| io_at(path, source))?;
        if metadata.uid() != uid {
            return Err(CredentialError::Unsafe {
                path: path.to_path_buf(),
                reason: "credential path is not owned by the current user",
            });
        }
    }
    #[cfg(not(unix))]
    let _ = (path, metadata, owner);
    Ok(())
}

fn reject_symlink(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() {
                return Err(CredentialError::Unsafe {
                    path: path.to_path_buf(),
                    reason: "credential path is a symlink",
                });
            }
            Ok(())
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(source) => Err(io_at(path, source)),
    }
}

/// `unix`-only: a permission bit has no meaning elsewhere, and every caller is
/// already inside a `#[cfg(unix)]` block, so a non-unix arm here would be a
/// branch nothing can reach.
#[cfg(unix)]
fn file_mode(metadata: &fs::Metadata) -> u32 {
    use std::os::unix::fs::MetadataExt;
    metadata.mode() & 0o777
}

fn set_private_permissions(file: &File, mode: u32) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(fs::Permissions::from_mode(mode))
    }
    #[cfg(not(unix))]
    {
        let _ = (file, mode);
        Ok(())
    }
}

/// `unix`-only for the same reason as [`file_mode`]. Its sibling
/// [`set_private_permissions`] is *not* gated: that one is called
/// unconditionally, so its non-unix no-op arm is live.
#[cfg(unix)]
fn set_private_permissions_path(path: &Path, mode: u32) -> io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
}

fn sync_parent(parent: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(|source| io_at(parent, source))
    }
    #[cfg(not(unix))]
    {
        let _ = parent;
        Ok(())
    }
}

fn io_at(path: impl Into<PathBuf>, source: io::Error) -> CredentialError {
    CredentialError::Io {
        path: path.into(),
        source,
    }
}

#[cfg(all(test, unix))]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    use chrono::{TimeZone, Utc};
    use tempfile::TempDir;

    use super::*;

    fn credential() -> NousCredential {
        NousCredential {
            client_id: "hermes-cli".into(),
            access_token: "test-access-token".into(),
            refresh_token: "test-refresh-token".into(),
            expires_at: Utc.with_ymd_and_hms(2026, 8, 16, 12, 0, 0).unwrap(),
        }
    }

    fn document() -> CredentialDocument {
        CredentialDocument::new(Some(credential()))
    }

    fn private_path(root: &TempDir) -> std::path::PathBuf {
        let parent = root.path().join("config");
        fs::create_dir(&parent).unwrap();
        fs::set_permissions(&parent, fs::Permissions::from_mode(0o700)).unwrap();
        parent.join("credentials.json")
    }

    #[test]
    fn write_creates_private_directory_and_file() {
        let root = TempDir::new().unwrap();
        let path = root.path().join("config").join("credentials.json");
        let store = CredentialStore::at(&path);

        store.write(&document()).unwrap();

        assert_eq!(
            fs::metadata(path.parent().unwrap())
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
        assert_eq!(
            fs::symlink_metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(store.read().unwrap().unwrap().nous.is_some());
    }

    #[test]
    fn atomic_replacement_leaves_complete_private_json_without_temp_files() {
        let root = TempDir::new().unwrap();
        let path = private_path(&root);
        let store = CredentialStore::at(&path);
        store.write(&document()).unwrap();

        let mut replacement = document();
        replacement.nous.as_mut().unwrap().access_token = "test-new-access".into();
        store.write(&replacement).unwrap();

        let bytes = fs::read(&path).unwrap();
        let text = String::from_utf8(bytes).unwrap();
        assert!(text.contains("test-new-access"));
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(!fs::read_dir(path.parent().unwrap()).unwrap().any(|entry| {
            entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".credentials.json.")
        }));
    }

    #[test]
    fn unsafe_existing_file_is_rejected_without_chmodifying_it() {
        let root = TempDir::new().unwrap();
        let path = private_path(&root);
        fs::write(&path, b"{}").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        let store = CredentialStore::at(&path);

        assert!(store.read().is_err());
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o644
        );
    }

    #[test]
    fn symlink_credential_path_is_rejected() {
        let root = TempDir::new().unwrap();
        let target = root.path().join("target.json");
        let path = private_path(&root);
        fs::write(&target, b"{}").unwrap();
        std::os::unix::fs::symlink(&target, &path).unwrap();

        assert!(CredentialStore::at(&path).read().is_err());
        assert!(CredentialStore::at(&path).write(&document()).is_err());
    }

    #[test]
    fn malformed_or_wrong_version_documents_fail_closed_and_logout_preserves_other_fields() {
        let root = TempDir::new().unwrap();
        let path = private_path(&root);
        let store = CredentialStore::at(&path);
        fs::write(&path, br#"{"version":2,"other":{"keep":true}}"#).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        assert!(store.read().is_err());
        assert!(store.logout().is_err());

        let mut doc = document();
        doc.insert_other("future", serde_json::json!({"keep": true}));
        store.write(&doc).unwrap();
        store.logout().unwrap();
        let json: serde_json::Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert!(json.get("nous").is_none());
        assert_eq!(json["future"]["keep"], true);
    }

    #[test]
    fn lock_blocks_a_second_holder_until_the_first_is_released() {
        let root = TempDir::new().unwrap();
        let store = CredentialStore::at(private_path(&root));
        let first = store.acquire_lock().unwrap();
        let (started_tx, started_rx) = mpsc::channel();
        let (finished_tx, finished_rx) = mpsc::channel();
        let path = store.path().to_path_buf();
        let handle = thread::spawn(move || {
            let other = CredentialStore::at(path);
            started_tx.send(()).unwrap();
            let _second = other.acquire_lock().unwrap();
            finished_tx.send(()).unwrap();
        });
        started_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        assert!(
            finished_rx
                .recv_timeout(Duration::from_millis(100))
                .is_err()
        );
        drop(first);
        finished_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn existing_owner_directory_with_standard_config_mode_is_accepted() {
        let root = TempDir::new().unwrap();
        let parent = root.path().join("config");
        fs::create_dir(&parent).unwrap();
        fs::set_permissions(&parent, fs::Permissions::from_mode(0o755)).unwrap();
        let store = CredentialStore::at(parent.join("credentials.json"));

        store.write(&document()).unwrap();
        assert_eq!(
            fs::metadata(&parent).unwrap().permissions().mode() & 0o777,
            0o755
        );
        assert!(store.read().unwrap().unwrap().nous.is_some());
    }

    #[test]
    fn group_or_world_writable_parent_is_rejected_without_chmodifying_it() {
        let root = TempDir::new().unwrap();
        let parent = root.path().join("config");
        fs::create_dir(&parent).unwrap();
        fs::set_permissions(&parent, fs::Permissions::from_mode(0o770)).unwrap();
        let store = CredentialStore::at(parent.join("credentials.json"));

        assert!(store.write(&document()).is_err());
        assert_eq!(
            fs::metadata(&parent).unwrap().permissions().mode() & 0o777,
            0o770
        );
    }

    #[test]
    fn process_owner_matches_files_created_by_the_effective_user() {
        use std::os::unix::fs::MetadataExt;

        let file = tempfile::tempfile().unwrap();
        assert_eq!(
            ProcessOwner.current_uid().unwrap(),
            file.metadata().unwrap().uid()
        );
    }

    #[test]
    fn secret_bearing_debug_output_contains_no_tokens() {
        let output = format!("{:?}", credential());
        assert!(!output.contains("test-access-token"));
        assert!(!output.contains("test-refresh-token"));
    }
}

#[cfg(all(test, not(unix)))]
mod non_unix_tests {
    use chrono::{TimeZone, Utc};
    use tempfile::TempDir;

    use super::*;

    fn document(access_token: &str) -> CredentialDocument {
        CredentialDocument::new(Some(NousCredential {
            client_id: "hermes-cli".into(),
            access_token: access_token.into(),
            refresh_token: "test-refresh-token".into(),
            expires_at: Utc.with_ymd_and_hms(2026, 8, 16, 12, 0, 0).unwrap(),
        }))
    }

    #[test]
    fn credential_store_writes_replaces_reads_and_logs_out() {
        let root = TempDir::new().unwrap();
        let store = CredentialStore::at(root.path().join("config").join("credentials.json"));

        store.write(&document("first-access-token")).unwrap();
        store.write(&document("second-access-token")).unwrap();
        let stored = store.read().unwrap().unwrap().nous.unwrap();
        assert_eq!(stored.access_token, "second-access-token");

        store.logout().unwrap();
        assert!(store.read().unwrap().is_none());
    }
}
