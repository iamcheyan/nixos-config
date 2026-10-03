//! Command Code (commandcode.ai) subscription usage integration.
//!
//! Command Code meters spend rather than tokens: two rolling windows priced in
//! dollars, drawn against a monthly credit allowance. Credentials come from
//! whichever agent harness on the machine is signed in — the official CLI or
//! pi — and are only ever read.

pub mod creds;
pub mod fetch;
pub mod types;
pub mod vendor;
