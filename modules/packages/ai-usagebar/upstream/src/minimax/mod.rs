//! MiniMax Token Plan vendor — subscription quota from
//! `/v1/token_plan/remains` over an API key. The key is instance-scoped:
//! `api.minimax.io` (global) and `api.minimaxi.com` (CN) reject each other's
//! keys, so the region is configured rather than probed.

pub mod fetch;
pub mod types;
pub mod vendor;

pub use fetch::{FetchOutcome, fetch_snapshot};
