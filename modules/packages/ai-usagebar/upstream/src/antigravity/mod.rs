//! Google Antigravity vendor — quota tracking via the local language server.

pub mod agy;
pub mod cloud;
pub mod credential;
pub mod fetch;
pub mod statusline;
pub mod vendor;

pub use fetch::fetch_snapshot;
