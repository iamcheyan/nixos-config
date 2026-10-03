//! GitHub Copilot quota via the private endpoint used by VS Code.

pub mod credentials;
pub mod fetch;
pub mod types;
pub mod vendor;

pub use fetch::{FetchOutcome, fetch_snapshot};
