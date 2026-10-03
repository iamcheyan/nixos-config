//! Wire types for MiniMax's Token Plan quota endpoint,
//! `GET /v1/token_plan/remains`.
//!
//! Captured against the live global endpoint (`api.minimax.io`); MiniMax does
//! not publish a schema for it, so every field here is one observed on the
//! wire. The response is `{ model_remains: [...], base_resp: { … } }` with one
//! row per model bucket (`general` for text/coding, `video`), each carrying a
//! rolling interval window and a weekly window.
//!
//! Four properties of this API drive the code below, and all four are easy to
//! get backwards:
//!
//! 1. **HTTP 200 always.** Auth failures come back `200` with the real status
//!    in `base_resp.status_code` (`1004` no key, `2049` invalid key). The HTTP
//!    status must never be read as success.
//! 2. **The percentages are what REMAINS**, not what was consumed. They are
//!    inverted here so the rest of the app keeps its consumed-% convention.
//! 3. **The interval length is not fixed** — `general` rolls every 5h but
//!    `video` rolls every 24h — so the window duration comes from each row's
//!    own `start_time`/`end_time` instead of a constant.
//! 4. **All timestamps are epoch milliseconds**, not seconds.

use serde::Deserialize;

use crate::error::{AppError, Result};
use crate::usage::{MinimaxSnapshot, UsageWindow};

/// Bucket name of the text/coding pool — the one that drives the bars.
const BUCKET_GENERAL: &str = "general";
/// Bucket name of the video-generation pool, rendered as the secondary pool.
const BUCKET_VIDEO: &str = "video";

/// Fallbacks used only when a row's own start/end can't yield a positive
/// duration (a malformed row); the pacing math needs a non-zero window.
const DEFAULT_INTERVAL: chrono::Duration = chrono::Duration::hours(5);
const DEFAULT_WEEKLY: chrono::Duration = chrono::Duration::days(7);

/// MiniMax's standard envelope. Present on every response, including the ones
/// that carry no data because authentication failed.
#[derive(Debug, Clone, Deserialize)]
pub struct BaseResp {
    pub status_code: i64,
    #[serde(default)]
    pub status_msg: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RemainsEnvelope {
    /// Absent (not merely empty) on failure responses.
    #[serde(default)]
    pub model_remains: Vec<ModelRemains>,
    pub base_resp: BaseResp,
}

impl RemainsEnvelope {
    /// Reject the in-band failure shape before any field is read as a quota.
    /// `status_code == 0` is the documented success value; everything else —
    /// including the auth failures that arrive as HTTP 200 — is an error.
    pub fn check_ok(&self) -> Result<()> {
        if self.base_resp.status_code == 0 {
            return Ok(());
        }
        // Do not surface `status_msg`: it is arbitrary upstream text and can
        // contain request details. The stable numeric code is sufficient for
        // diagnostics and safe to persist in the shared error cache.
        Err(AppError::Schema(format!(
            "minimax: API reported failure (status_code {})",
            self.base_resp.status_code
        )))
    }
}

/// Envelope codes that mean "the credential was rejected" rather than "the
/// service failed": `1004` no key supplied, `2049` the key is not valid for
/// this instance (the code a global key gets from the CN host, and vice versa).
/// The caller maps these onto an HTTP 401 so the UI reports an auth problem
/// instead of filing a wrong key under schema drift.
pub fn is_auth_failure(status_code: i64) -> bool {
    matches!(status_code, 1004 | 2049)
}

/// One model bucket's quota. The `*_count` fields are request counters that
/// only some buckets populate (`general` reports zeros and is governed by the
/// percentages), so they are not part of the snapshot.
#[derive(Debug, Clone, Deserialize)]
pub struct ModelRemains {
    pub model_name: String,
    /// Rolling interval window, epoch **milliseconds**.
    pub start_time: i64,
    pub end_time: i64,
    /// Percentage of the interval quota still available (0..=100).
    pub current_interval_remaining_percent: i64,
    /// Weekly window, epoch **milliseconds**.
    pub weekly_start_time: i64,
    pub weekly_end_time: i64,
    /// Percentage of the weekly quota still available (0..=100).
    pub current_weekly_remaining_percent: i64,
}

/// Consumed percent from MiniMax's remaining percent, clamped to the 0..=100
/// the renderers expect. An out-of-range value upstream would otherwise paint
/// a bar past its track.
fn consumed_pct(remaining: i64) -> i32 {
    (100 - remaining.clamp(0, 100)) as i32
}

/// Epoch milliseconds to a UTC instant. Non-positive values mean "unreported"
/// rather than 1970, so they become `None` and the row simply shows no reset.
fn at_millis(ms: i64) -> Option<chrono::DateTime<chrono::Utc>> {
    if ms <= 0 {
        return None;
    }
    chrono::DateTime::from_timestamp_millis(ms)
}

/// Window length from the row's own bounds, falling back to `default` when the
/// pair is unusable — never zero, which would make the pace marker divide by
/// nothing.
fn span(start_ms: i64, end_ms: i64, default: chrono::Duration) -> chrono::Duration {
    let delta = end_ms.saturating_sub(start_ms);
    if delta > 0 {
        chrono::Duration::milliseconds(delta)
    } else {
        default
    }
}

fn interval_window(row: &ModelRemains) -> UsageWindow {
    UsageWindow {
        utilization_pct: consumed_pct(row.current_interval_remaining_percent),
        resets_at: at_millis(row.end_time),
        window_duration: span(row.start_time, row.end_time, DEFAULT_INTERVAL),
    }
}

fn weekly_window(row: &ModelRemains) -> UsageWindow {
    UsageWindow {
        utilization_pct: consumed_pct(row.current_weekly_remaining_percent),
        resets_at: at_millis(row.weekly_end_time),
        window_duration: span(row.weekly_start_time, row.weekly_end_time, DEFAULT_WEEKLY),
    }
}

/// Build the snapshot from the parsed rows.
///
/// The `general` bucket is required — it is what the bars represent. If a plan
/// ever names its text bucket something else, the first non-video row is used
/// rather than failing outright; only a payload with no usable row at all is an
/// error, because rendering a plan as 0% used would be a silent lie.
pub fn to_snapshot(env: RemainsEnvelope, plan: &str) -> Result<MinimaxSnapshot> {
    let rows = &env.model_remains;
    let general = rows
        .iter()
        .find(|r| r.model_name == BUCKET_GENERAL)
        .or_else(|| rows.iter().find(|r| r.model_name != BUCKET_VIDEO))
        .ok_or_else(|| {
            AppError::Schema("minimax: response carried no usable model bucket".to_string())
        })?;
    let video = rows.iter().find(|r| r.model_name == BUCKET_VIDEO);

    Ok(MinimaxSnapshot {
        plan: plan.to_string(),
        session: interval_window(general),
        weekly: weekly_window(general),
        video_session: video.map(interval_window),
        video_weekly: video.map(weekly_window),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verbatim shape of a live successful response (values from a real Token
    /// Plan account; `general` at 99% remaining on a 5h window, `video` at
    /// 100% on a 24h one).
    const LIVE: &str = r#"{
        "model_remains": [
            {
                "start_time": 1785164400000,
                "end_time": 1785182400000,
                "remains_time": 1877492,
                "current_interval_total_count": 0,
                "current_interval_usage_count": 0,
                "model_name": "general",
                "current_weekly_total_count": 0,
                "current_weekly_usage_count": 0,
                "weekly_start_time": 1785110400000,
                "weekly_end_time": 1785715200000,
                "weekly_remains_time": 534677492,
                "current_interval_status": 1,
                "current_interval_remaining_percent": 99,
                "current_weekly_status": 1,
                "current_weekly_remaining_percent": 99
            },
            {
                "start_time": 1785110400000,
                "end_time": 1785196800000,
                "remains_time": 16277492,
                "current_interval_total_count": 3,
                "current_interval_usage_count": 0,
                "model_name": "video",
                "current_weekly_total_count": 21,
                "current_weekly_usage_count": 0,
                "weekly_start_time": 1785110400000,
                "weekly_end_time": 1785715200000,
                "weekly_remains_time": 534677492,
                "current_interval_status": 1,
                "current_interval_remaining_percent": 100,
                "current_weekly_status": 1,
                "current_weekly_remaining_percent": 100
            }
        ],
        "base_resp": { "status_code": 0, "status_msg": "success" }
    }"#;

    fn parse(raw: &str) -> RemainsEnvelope {
        serde_json::from_str(raw).expect("envelope parses")
    }

    #[test]
    fn parses_live_envelope() {
        let env = parse(LIVE);
        env.check_ok().expect("status_code 0 is success");
        assert_eq!(env.model_remains.len(), 2);
        assert_eq!(env.model_remains[0].model_name, "general");
    }

    /// The API reports what is LEFT; the app renders what was USED. A snapshot
    /// that echoed 99 here would show a nearly-exhausted plan as nearly-full.
    #[test]
    fn inverts_remaining_percent_into_consumed() {
        let snap = to_snapshot(parse(LIVE), "Token Plan").unwrap();
        assert_eq!(snap.session.utilization_pct, 1);
        assert_eq!(snap.weekly.utilization_pct, 1);
        assert_eq!(snap.video_session.unwrap().utilization_pct, 0);
    }

    /// The interval length differs per bucket, so it must come from the row.
    #[test]
    fn derives_window_length_from_the_row_not_a_constant() {
        let snap = to_snapshot(parse(LIVE), "Token Plan").unwrap();
        assert_eq!(snap.session.window_duration, chrono::Duration::hours(5));
        assert_eq!(snap.weekly.window_duration, chrono::Duration::days(7));
        assert_eq!(
            snap.video_session.unwrap().window_duration,
            chrono::Duration::hours(24),
            "video rolls daily, not on general's 5h cadence"
        );
    }

    #[test]
    fn reset_comes_from_end_time_in_milliseconds() {
        let snap = to_snapshot(parse(LIVE), "Token Plan").unwrap();
        assert_eq!(
            snap.session.resets_at,
            chrono::DateTime::from_timestamp_millis(1785182400000)
        );
    }

    /// Auth failures arrive as HTTP 200 — the envelope is the only signal.
    #[test]
    fn rejects_in_band_auth_failure() {
        for raw in [
            r#"{"base_resp":{"status_code":1004,"status_msg":"login fail: Please carry the API secret key in the 'Authorization' field of the request header"}}"#,
            r#"{"base_resp":{"status_code":2049,"status_msg":"invalid api key"}}"#,
        ] {
            let env = parse(raw);
            assert!(env.model_remains.is_empty());
            let err = env.check_ok().unwrap_err();
            assert!(
                matches!(err, AppError::Schema(ref m) if m.contains("minimax")),
                "unexpected error: {err:?}"
            );
        }
    }

    #[test]
    fn in_band_failure_does_not_surface_upstream_message() {
        let env =
            parse(r#"{"base_resp":{"status_code":9001,"status_msg":"secret request detail"}}"#);
        let error = env.check_ok().unwrap_err().to_string();
        assert!(error.contains("9001"), "{error}");
        assert!(!error.contains("secret request detail"), "{error}");
    }

    /// A plan without video quota is normal, not an error.
    #[test]
    fn video_bucket_is_optional() {
        let raw = r#"{
            "model_remains": [{
                "start_time": 1785164400000, "end_time": 1785182400000,
                "model_name": "general",
                "current_interval_remaining_percent": 40,
                "weekly_start_time": 1785110400000, "weekly_end_time": 1785715200000,
                "current_weekly_remaining_percent": 55
            }],
            "base_resp": {"status_code": 0, "status_msg": "success"}
        }"#;
        let snap = to_snapshot(parse(raw), "Token Plan").unwrap();
        assert_eq!(snap.session.utilization_pct, 60);
        assert_eq!(snap.weekly.utilization_pct, 45);
        assert!(snap.video_session.is_none());
        assert!(snap.video_weekly.is_none());
    }

    /// A response whose only row is `video` has no bar to draw — surfacing that
    /// beats rendering an empty general pool as 0% used.
    #[test]
    fn errors_when_no_text_bucket_is_present() {
        let raw = r#"{
            "model_remains": [{
                "start_time": 1, "end_time": 2, "model_name": "video",
                "current_interval_remaining_percent": 100,
                "weekly_start_time": 1, "weekly_end_time": 2,
                "current_weekly_remaining_percent": 100
            }],
            "base_resp": {"status_code": 0, "status_msg": "success"}
        }"#;
        assert!(to_snapshot(parse(raw), "Token Plan").is_err());
    }

    /// Degenerate bounds must not produce a zero-length window: the pace marker
    /// divides by it.
    #[test]
    fn falls_back_to_a_positive_window_on_degenerate_bounds() {
        let raw = r#"{
            "model_remains": [{
                "start_time": 0, "end_time": 0, "model_name": "general",
                "current_interval_remaining_percent": 100,
                "weekly_start_time": 0, "weekly_end_time": 0,
                "current_weekly_remaining_percent": 100
            }],
            "base_resp": {"status_code": 0, "status_msg": "success"}
        }"#;
        let snap = to_snapshot(parse(raw), "Token Plan").unwrap();
        assert_eq!(snap.session.window_duration, DEFAULT_INTERVAL);
        assert_eq!(snap.weekly.window_duration, DEFAULT_WEEKLY);
        assert_eq!(snap.session.resets_at, None, "epoch 0 is unreported");
    }

    /// Upstream sending something outside 0..=100 must not paint past the track.
    #[test]
    fn clamps_out_of_range_percentages() {
        assert_eq!(consumed_pct(150), 0);
        assert_eq!(consumed_pct(-5), 100);
    }
}
