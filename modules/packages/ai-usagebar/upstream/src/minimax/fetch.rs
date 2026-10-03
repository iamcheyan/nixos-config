//! MiniMax fetch — reads Token Plan quota from `/v1/token_plan/remains` under
//! the shared cache + flock primitives.
//!
//! The host is region-dependent (`api.minimax.io` global, `api.minimaxi.com`
//! CN) and, unlike Moonshot's regions, the two are *separate instances*: a key
//! issued for one is rejected by the other. That makes a cached figure from the
//! other region not merely stale but wrong, so the endpoint is recorded in the
//! payload and a mismatched cache is discarded.

use std::time::Duration;

use crate::cache::{Cache, acquire_lock_async};
use crate::error::{AppError, Result};
use crate::usage::{MinimaxSnapshot, UsageWindow};
use crate::vendor::{MAX_BODY_BYTES, read_body_capped};

use super::types::{RemainsEnvelope, is_auth_failure, to_snapshot};

pub const BASE_GLOBAL: &str = "https://api.minimax.io";
pub const BASE_CN: &str = "https://api.minimaxi.com";
const HTTP_TIMEOUT: Duration = Duration::from_secs(10);
const LOCK_TIMEOUT: Duration = Duration::from_secs(15);

/// Label shown as the plan name. The quota endpoint doesn't name the plan, and
/// inventing a tier from the numbers would be a guess, so the product name is
/// used as-is.
pub const PLAN_LABEL: &str = "MiniMax Token Plan";

#[derive(Debug, Clone)]
pub struct Endpoints {
    pub remains: String,
}

impl Endpoints {
    /// Pick the host by region. `cn` → `api.minimaxi.com`, anything else →
    /// `api.minimax.io`. No currency is implied: MiniMax reports quota as
    /// percentages, not money.
    pub fn for_region(region: &str) -> Self {
        let base = if region.eq_ignore_ascii_case("cn") {
            BASE_CN
        } else {
            BASE_GLOBAL
        };
        Self {
            remains: format!("{base}/v1/token_plan/remains"),
        }
    }
}

impl Default for Endpoints {
    fn default() -> Self {
        Self::for_region("global")
    }
}

/// This vendor's [`Outcome`](crate::outcome::Outcome) — the shared shape,
/// specialised to its snapshot.
pub type FetchOutcome = crate::outcome::Outcome<MinimaxSnapshot>;

pub async fn fetch_snapshot(
    client: &reqwest::Client,
    api_key: &str,
    cache: &Cache,
    endpoints: &Endpoints,
    cache_ttl: Duration,
) -> Result<FetchOutcome> {
    cache.ensure_dir()?;
    let _lock = acquire_lock_async(&cache.lock_path(), LOCK_TIMEOUT).await?;

    let target = target_key(endpoints, api_key);

    if let Some(bytes) = cache.fresh_payload(cache_ttl)?
        && let Ok(outcome) = reuse_cache(&bytes, cache, false, &target)
    {
        return Ok(outcome);
    }

    match fetch_live(client, endpoints, api_key).await {
        Ok(snap) => {
            let bytes = serde_json::to_vec(
                &serde_json::json!({ "target": target, "snapshot": serde_repr(&snap) }),
            )?;
            cache.write_payload(&bytes)?;
            Ok(crate::outcome::Outcome::fresh(snap))
        }
        Err(e) if e.is_transient() => fallback_silent(cache, &target, e),
        Err(AppError::Http { status, body }) => {
            cache.mark_stale();
            let diag = cache.write_last_error(status, &body);
            fallback_with_error(cache, Some(diag), &target, AppError::Http { status, body })
        }
        Err(e) => {
            cache.mark_stale();
            let diag = cache.write_last_error(0, &e.to_string());
            fallback_with_error(cache, Some(diag), &target, e)
        }
    }
}

/// Identity of the account and instance the cached quota belongs to. Global
/// and CN are separate deployments, and changing the Token Plan key on the
/// same deployment can change accounts. Store only a fingerprint of the key:
/// it is a cache change detector, not an authentication secret.
fn target_key(endpoints: &Endpoints, api_key: &str) -> String {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    api_key.hash(&mut hasher);
    format!("{}|key:{:016x}", endpoints.remains, hasher.finish())
}

fn fallback_silent(cache: &Cache, target: &str, original: AppError) -> Result<FetchOutcome> {
    crate::outcome::fallback(cache, None, original, |bytes| parse_cache(bytes, target))
}

fn fallback_with_error(
    cache: &Cache,
    last_error: Option<(u16, String)>,
    target: &str,
    original: AppError,
) -> Result<FetchOutcome> {
    crate::outcome::fallback(cache, last_error, original, |bytes| {
        parse_cache(bytes, target)
    })
}

fn reuse_cache(bytes: &[u8], cache: &Cache, stale: bool, target: &str) -> Result<FetchOutcome> {
    let snap = parse_cache(bytes, target)?;
    Ok(crate::outcome::Outcome::cached(snap, cache, stale))
}

fn window_repr(w: &UsageWindow) -> serde_json::Value {
    serde_json::json!({
        "pct": w.utilization_pct,
        "resets_at": w.resets_at.map(|t| t.to_rfc3339()),
        "window_secs": w.window_duration.num_seconds(),
    })
}

fn serde_repr(snap: &MinimaxSnapshot) -> serde_json::Value {
    serde_json::json!({
        "plan": snap.plan,
        "session": window_repr(&snap.session),
        "weekly": window_repr(&snap.weekly),
        "video_session": snap.video_session.as_ref().map(window_repr),
        "video_weekly": snap.video_weekly.as_ref().map(window_repr),
    })
}

fn parse_window(v: &serde_json::Value, what: &str) -> Result<UsageWindow> {
    let pct = v["pct"]
        .as_i64()
        .ok_or_else(|| AppError::Schema(format!("minimax cache missing '{what}.pct'")))?;
    let resets_at = match v["resets_at"].as_str() {
        Some(s) => Some(
            chrono::DateTime::parse_from_rfc3339(s)
                .map_err(|e| AppError::Schema(format!("minimax cache '{what}.resets_at': {e}")))?
                .with_timezone(&chrono::Utc),
        ),
        None => None,
    };
    let secs = v["window_secs"]
        .as_i64()
        .ok_or_else(|| AppError::Schema(format!("minimax cache missing '{what}.window_secs'")))?;
    if secs <= 0 {
        return Err(AppError::Schema(format!(
            "minimax cache '{what}.window_secs' must be greater than zero"
        )));
    }
    Ok(UsageWindow {
        utilization_pct: pct.clamp(0, 100) as i32,
        resets_at,
        window_duration: chrono::Duration::seconds(secs),
    })
}

fn parse_cache(bytes: &[u8], target: &str) -> Result<MinimaxSnapshot> {
    let v: serde_json::Value = serde_json::from_slice(bytes)?;
    let cached_target = v.get("target").and_then(serde_json::Value::as_str);
    if cached_target != Some(target) {
        return Err(AppError::Schema(format!(
            "minimax cache belongs to a different instance ({}); refetching",
            cached_target.unwrap_or("unknown")
        )));
    }
    let s = v
        .get("snapshot")
        .ok_or_else(|| AppError::Schema("minimax cache missing 'snapshot' field".into()))?;
    let optional = |name: &str| -> Result<Option<UsageWindow>> {
        match s.get(name) {
            None | Some(serde_json::Value::Null) => Ok(None),
            Some(w) => parse_window(w, name).map(Some),
        }
    };
    Ok(MinimaxSnapshot {
        plan: s["plan"].as_str().unwrap_or(PLAN_LABEL).to_string(),
        session: parse_window(&s["session"], "session")?,
        weekly: parse_window(&s["weekly"], "weekly")?,
        video_session: optional("video_session")?,
        video_weekly: optional("video_weekly")?,
    })
}

async fn fetch_live(
    client: &reqwest::Client,
    endpoints: &Endpoints,
    api_key: &str,
) -> Result<MinimaxSnapshot> {
    let resp = tokio::time::timeout(
        HTTP_TIMEOUT,
        client
            .get(&endpoints.remains)
            .header("Authorization", format!("Bearer {api_key}"))
            .send(),
    )
    .await
    .map_err(|_| AppError::Transport(format!("minimax timeout: {}", endpoints.remains)))??;

    let status = resp.status();
    let bytes = read_body_capped(resp, MAX_BODY_BYTES).await?;

    if !status.is_success() {
        // Never surface upstream/proxy bodies: they can carry credentials or
        // arbitrary markup. Keep the cached diagnostic useful but generic.
        let body = if matches!(status.as_u16(), 401 | 403) {
            "MiniMax authentication failed".to_string()
        } else {
            format!("MiniMax API returned HTTP {}", status.as_u16())
        };
        return Err(AppError::Http {
            status: status.as_u16(),
            body,
        });
    }

    let env: RemainsEnvelope = serde_json::from_slice(&bytes)
        .map_err(|e| AppError::Schema(format!("minimax {}: {e}", endpoints.remains)))?;

    // MiniMax answers auth failures with HTTP 200 and the real status in the
    // envelope. Those are reported as HTTP 401 so the UI says "authentication
    // failed" instead of filing a wrong key under schema drift.
    if is_auth_failure(env.base_resp.status_code) {
        return Err(AppError::Http {
            status: 401,
            body: "MiniMax authentication failed".to_string(),
        });
    }
    env.check_ok()?;
    to_snapshot(env, PLAN_LABEL)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    const LIVE_BODY: &str = r#"{
        "model_remains": [
            {"start_time":1785164400000,"end_time":1785182400000,"model_name":"general",
             "current_interval_remaining_percent":99,
             "weekly_start_time":1785110400000,"weekly_end_time":1785715200000,
             "current_weekly_remaining_percent":80},
            {"start_time":1785110400000,"end_time":1785196800000,"model_name":"video",
             "current_interval_remaining_percent":100,
             "weekly_start_time":1785110400000,"weekly_end_time":1785715200000,
             "current_weekly_remaining_percent":100}
        ],
        "base_resp": {"status_code":0,"status_msg":"success"}
    }"#;

    fn cache_fixture() -> (TempDir, Cache) {
        let td = TempDir::new().unwrap();
        let cache = Cache::at(td.path().join("minimax"));
        cache.ensure_dir().unwrap();
        (td, cache)
    }

    fn endpoints_for(server: &mockito::Server) -> Endpoints {
        Endpoints {
            remains: format!("{}/v1/token_plan/remains", server.url()),
        }
    }

    #[test]
    fn region_picks_the_instance_host() {
        assert!(
            Endpoints::for_region("global")
                .remains
                .starts_with(BASE_GLOBAL)
        );
        assert!(Endpoints::for_region("cn").remains.starts_with(BASE_CN));
        assert!(Endpoints::for_region("CN").remains.starts_with(BASE_CN));
        // Anything unrecognized stays on the global instance.
        assert!(Endpoints::for_region("").remains.starts_with(BASE_GLOBAL));
    }

    #[tokio::test]
    async fn live_fetch_reads_both_pools() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/v1/token_plan/remains")
            .match_header("authorization", "Bearer mm-test")
            .with_status(200)
            .with_body(LIVE_BODY)
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let out = fetch_snapshot(
            &reqwest::Client::new(),
            "mm-test",
            &cache,
            &endpoints_for(&server),
            Duration::from_secs(0),
        )
        .await
        .unwrap();

        assert_eq!(out.snapshot.session.utilization_pct, 1);
        assert_eq!(out.snapshot.weekly.utilization_pct, 20);
        assert_eq!(out.snapshot.video_session.unwrap().utilization_pct, 0);
        assert!(!out.stale);
        assert_eq!(out.snapshot.plan, PLAN_LABEL);
    }

    /// The whole point of the in-band check: a 200 carrying `2049` is an auth
    /// failure, and must not be cached as a valid zero-usage plan.
    #[tokio::test]
    async fn in_band_auth_failure_is_reported_as_401() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/v1/token_plan/remains")
            .with_status(200)
            .with_body(r#"{"base_resp":{"status_code":2049,"status_msg":"invalid api key"}}"#)
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let err = fetch_snapshot(
            &reqwest::Client::new(),
            "bad",
            &cache,
            &endpoints_for(&server),
            Duration::from_secs(0),
        )
        .await
        .unwrap_err();

        match err {
            AppError::Http { status, ref body } => {
                assert_eq!(status, 401);
                assert!(body.contains("authentication"), "body was {body:?}");
            }
            other => panic!("expected HTTP 401, got {other:?}"),
        }
    }

    /// A cache written against the other instance is wrong, not merely stale.
    #[tokio::test]
    async fn cache_from_the_other_instance_is_rejected() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/v1/token_plan/remains")
            .with_status(200)
            .with_body(LIVE_BODY)
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let other_instance = Endpoints::for_region("cn");
        let seed = serde_json::json!({
            "target": target_key(&other_instance, "mm-test"),
            "snapshot": {
                "plan": "MiniMax Token Plan",
                "session": {"pct": 77, "resets_at": null, "window_secs": 18000},
                "weekly":  {"pct": 77, "resets_at": null, "window_secs": 604800},
            }
        });
        cache
            .write_payload(&serde_json::to_vec(&seed).unwrap())
            .unwrap();

        // A long TTL would normally serve the cache; the target mismatch must
        // force a refetch instead of showing the other instance's numbers.
        let out = fetch_snapshot(
            &reqwest::Client::new(),
            "mm-test",
            &cache,
            &endpoints_for(&server),
            Duration::from_secs(3600),
        )
        .await
        .unwrap();
        assert_eq!(out.snapshot.session.utilization_pct, 1, "refetched, not 77");
    }

    /// Replacing the configured key can select another Token Plan account on
    /// the same host. A fresh cache from the previous key must not cross that
    /// account boundary.
    #[tokio::test]
    async fn cache_from_another_key_is_rejected() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/v1/token_plan/remains")
            .match_header("authorization", "Bearer new-key")
            .with_status(200)
            .with_body(LIVE_BODY)
            .expect(1)
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let endpoints = endpoints_for(&server);
        let seed = serde_json::json!({
            "target": target_key(&endpoints, "old-key"),
            "snapshot": {
                "plan": "MiniMax Token Plan",
                "session": {"pct": 77, "resets_at": null, "window_secs": 18000},
                "weekly":  {"pct": 77, "resets_at": null, "window_secs": 604800},
            }
        });
        cache
            .write_payload(&serde_json::to_vec(&seed).unwrap())
            .unwrap();

        let out = fetch_snapshot(
            &reqwest::Client::new(),
            "new-key",
            &cache,
            &endpoints,
            Duration::from_secs(3600),
        )
        .await
        .unwrap();
        assert_eq!(out.snapshot.session.utilization_pct, 1, "refetched, not 77");

        let stored = std::fs::read(cache.payload_path()).unwrap();
        let stored = String::from_utf8(stored).unwrap();
        assert!(!stored.contains("new-key"), "cache leaked the API key");
    }

    #[tokio::test]
    async fn http_error_falls_back_to_matching_cache() {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/v1/token_plan/remains")
            .with_status(500)
            .with_body("upstream exploded")
            .create_async()
            .await;

        let (_td, cache) = cache_fixture();
        let endpoints = endpoints_for(&server);
        let seed = serde_json::json!({
            "target": target_key(&endpoints, "mm-test"),
            "snapshot": {
                "plan": "MiniMax Token Plan",
                "session": {"pct": 42, "resets_at": null, "window_secs": 18000},
                "weekly":  {"pct": 43, "resets_at": null, "window_secs": 604800},
            }
        });
        cache
            .write_payload(&serde_json::to_vec(&seed).unwrap())
            .unwrap();

        let out = fetch_snapshot(
            &reqwest::Client::new(),
            "mm-test",
            &cache,
            &endpoints,
            Duration::from_secs(0),
        )
        .await
        .unwrap();

        assert!(out.stale);
        assert_eq!(out.snapshot.session.utilization_pct, 42);
        let (code, body) = out.last_error.expect("error recorded alongside the figure");
        assert_eq!(code, 500);
        assert!(
            !body.contains("exploded"),
            "upstream body must not be surfaced: {body:?}"
        );
    }

    #[test]
    fn cache_round_trips_windows_including_reset_and_duration() {
        let endpoints = Endpoints::default();
        let snap = MinimaxSnapshot {
            plan: PLAN_LABEL.to_string(),
            session: UsageWindow {
                utilization_pct: 12,
                resets_at: chrono::DateTime::from_timestamp_millis(1785182400000),
                window_duration: chrono::Duration::hours(5),
            },
            weekly: UsageWindow {
                utilization_pct: 34,
                resets_at: None,
                window_duration: chrono::Duration::days(7),
            },
            video_session: None,
            video_weekly: None,
        };
        let bytes = serde_json::to_vec(&serde_json::json!({
            "target": target_key(&endpoints, "mm-test"),
            "snapshot": serde_repr(&snap),
        }))
        .unwrap();
        let back = parse_cache(&bytes, &target_key(&endpoints, "mm-test")).unwrap();
        assert_eq!(back, snap);
    }

    #[test]
    fn cache_rejects_non_positive_window_duration() {
        let endpoints = Endpoints::default();
        for seconds in [0, -1] {
            let bytes = serde_json::to_vec(&serde_json::json!({
                "target": target_key(&endpoints, "mm-test"),
                "snapshot": {
                    "plan": "MiniMax Token Plan",
                    "session": {"pct": 1, "resets_at": null, "window_secs": seconds},
                    "weekly":  {"pct": 2, "resets_at": null, "window_secs": 604800},
                }
            }))
            .unwrap();
            let error = parse_cache(&bytes, &target_key(&endpoints, "mm-test")).unwrap_err();
            assert!(error.to_string().contains("greater than zero"), "{error:?}");
        }
    }
}
