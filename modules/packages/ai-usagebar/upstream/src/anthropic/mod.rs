//! Anthropic vendor — OAuth-based plan usage via the undocumented
//! `https://api.anthropic.com/api/oauth/usage` endpoint.
//!
//! Mirrors `~/Projects/claudebar/claudebar` line-for-line; see individual
//! submodule headers for the bash references.

pub mod cli_account;
pub mod creds;
pub mod desktop_creds;
pub mod fetch;
#[cfg(target_os = "macos")]
pub mod keychain;
pub mod oauth;
pub mod types;

pub use fetch::{FetchOutcome, fetch_snapshot};
