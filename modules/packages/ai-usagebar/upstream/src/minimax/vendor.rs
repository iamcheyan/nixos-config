//! MiniMax renderer — bar text + bordered Pango tooltip.
//!
//! MiniMax reports quota per model bucket, so its rows are labeled by pool the
//! same way Antigravity labels its Gemini / third-party groups. The text pool
//! is what the bar shows; the video pool, when the plan has one, appears in the
//! tooltip rather than competing for space on the bar.

use std::collections::HashMap;

use chrono::{DateTime, Utc};

use crate::countdown;
use crate::format::{placeholders, substitute, updated_at_hm};
use crate::pacing::{self, PaceSeverity};
use crate::pango::{color_span, escape, severity_color, severity_for};
use crate::theme::Theme;
use crate::tooltip::{Line as TooltipLine, WindowRow, push_window_with_row, render_bordered};
use crate::usage::{MinimaxSnapshot, UsageWindow};
use crate::vendor::{RenderOpts, VendorId, VendorOutcome};
use crate::waybar::{Class, WaybarOutput};

use super::fetch::FetchOutcome;

/// The text & coding pool (`general` on the wire) — what the bars represent.
pub const POOL_GENERAL: &str = "Text";
/// The video-generation pool (`video` on the wire), shown when the plan has it.
pub const POOL_VIDEO: &str = "Video";

pub const DEFAULT_FORMAT: &str = "{minimax_session_pct}% · {minimax_session_reset}";

/// Build placeholders with the historical default pacing tolerance.
///
/// Keep this signature stable for library callers. Rendering uses the private
/// tolerance-aware helper so `--pace-tolerance` still applies.
pub fn build_placeholders(
    snap: &MinimaxSnapshot,
    now: DateTime<Utc>,
) -> HashMap<&'static str, String> {
    build_placeholders_with_tolerance(snap, pacing::DEFAULT_TOLERANCE, now)
}

fn build_placeholders_with_tolerance(
    snap: &MinimaxSnapshot,
    pace_tolerance: u32,
    now: DateTime<Utc>,
) -> HashMap<&'static str, String> {
    let session_pct = snap.session.utilization_pct;
    let weekly_pct = snap.weekly.utilization_pct;
    let session_reset = countdown::format(snap.session.resets_at, now);
    let weekly_reset = countdown::format(snap.weekly.resets_at, now);
    // The video pool is optional; its placeholders resolve to an em dash rather
    // than vanishing, so a user format referencing them never leaves a gap.
    let video = |w: &Option<UsageWindow>, pct: bool| -> String {
        match w {
            Some(w) if pct => w.utilization_pct.to_string(),
            Some(w) => countdown::format(w.resets_at, now),
            None => "—".to_string(),
        }
    };
    // Present windows normally carry resets, but degenerate upstream bounds
    // are represented without one. `pacing::calc` deliberately returns
    // neutral 0/arrow values then, matching the existing provider contract.
    let session = window_pacing(&snap.session, pace_tolerance, now);
    let weekly = window_pacing(&snap.weekly, pace_tolerance, now);
    let video_pacing = optional_window_pacing(snap.video_session.as_ref(), pace_tolerance, now);
    let video_weekly_pacing =
        optional_window_pacing(snap.video_weekly.as_ref(), pace_tolerance, now);

    placeholders(vec![
        ("icon", "󰚩".to_string()),
        ("vendor_short", VendorId::Minimax.short_name().to_string()),
        // Cross-vendor aliases — what the desktop surfaces read.
        ("plan", snap.plan.clone()),
        ("session_pct", session_pct.to_string()),
        ("session_reset", session_reset.clone()),
        ("weekly_pct", weekly_pct.to_string()),
        ("weekly_reset", weekly_reset.clone()),
        ("session_elapsed", session.elapsed.clone()),
        ("weekly_elapsed", weekly.elapsed.clone()),
        // MiniMax-specific placeholders.
        ("minimax_plan", snap.plan.clone()),
        ("minimax_session_pct", session_pct.to_string()),
        ("minimax_session_reset", session_reset),
        ("minimax_weekly_pct", weekly_pct.to_string()),
        ("minimax_weekly_reset", weekly_reset),
        ("minimax_session_elapsed", session.elapsed),
        ("minimax_session_pace", session.ratio_pace),
        ("minimax_session_pace_indicator", session.point_pace),
        ("minimax_weekly_elapsed", weekly.elapsed),
        ("minimax_weekly_pace", weekly.ratio_pace),
        ("minimax_weekly_pace_indicator", weekly.point_pace),
        ("minimax_video_pct", video(&snap.video_session, true)),
        ("minimax_video_reset", video(&snap.video_session, false)),
        ("minimax_video_elapsed", video_pacing.elapsed),
        ("minimax_video_pace", video_pacing.ratio_pace),
        ("minimax_video_pace_indicator", video_pacing.point_pace),
        ("minimax_video_weekly_pct", video(&snap.video_weekly, true)),
        (
            "minimax_video_weekly_reset",
            video(&snap.video_weekly, false),
        ),
        ("minimax_video_weekly_elapsed", video_weekly_pacing.elapsed),
        ("minimax_video_weekly_pace", video_weekly_pacing.ratio_pace),
        (
            "minimax_video_weekly_pace_indicator",
            video_weekly_pacing.point_pace,
        ),
    ])
}

/// Elapsed fraction and pace glyphs for one window, as ready placeholder
/// values.
struct WindowPacing {
    elapsed: String,
    ratio_pace: String,
    point_pace: String,
}

impl WindowPacing {
    fn unavailable() -> Self {
        Self {
            elapsed: "—".to_string(),
            ratio_pace: "—".to_string(),
            point_pace: "—".to_string(),
        }
    }
}

fn optional_window_pacing(
    window: Option<&UsageWindow>,
    pace_tolerance: u32,
    now: DateTime<Utc>,
) -> WindowPacing {
    window.map_or_else(WindowPacing::unavailable, |window| {
        window_pacing(window, pace_tolerance, now)
    })
}

fn window_pacing(w: &UsageWindow, pace_tolerance: u32, now: DateTime<Utc>) -> WindowPacing {
    let p = pacing::calc(
        w.utilization_pct,
        w.resets_at,
        now,
        w.window_duration,
        pace_tolerance,
    );
    WindowPacing {
        elapsed: p.elapsed_pct.to_string(),
        ratio_pace: p.ratio_pace.glyph().to_string(),
        point_pace: p.point_pace.glyph().to_string(),
    }
}

/// Worst of the two text-pool windows. The video pool deliberately does not
/// drive the bar color: running out of video quota should not paint the coding
/// bar red.
pub fn severity(snap: &MinimaxSnapshot) -> PaceSeverity {
    severity_for(
        snap.session
            .utilization_pct
            .max(snap.weekly.utilization_pct),
    )
}

pub fn render(
    outcome: &VendorOutcome,
    snap: &MinimaxSnapshot,
    theme: &Theme,
    opts: &RenderOpts,
    now: DateTime<Utc>,
) -> WaybarOutput {
    let class = Class::from(severity(snap));
    let format = opts
        .format
        .clone()
        .unwrap_or_else(|| DEFAULT_FORMAT.to_string());
    let values = build_placeholders_with_tolerance(snap, opts.pace_tolerance, now);
    // User formats are Pango markup after Waybar renders them. Escape API
    // strings there, while retaining raw values for the default tooltip (which
    // escapes exactly once at its markup insertion point).
    let mut pango_values = values.clone();
    for key in ["plan", "minimax_plan"] {
        if let Some(value) = pango_values.get_mut(key) {
            *value = escape(value);
        }
    }

    let mut text = substitute(&format, &pango_values);
    if outcome.stale {
        text.push_str(" ⏸");
    }

    let wrapper_color = severity_color(severity(snap), theme).to_string();
    let icon_prefix = match opts.icon.as_deref() {
        Some(ic) if !ic.is_empty() => format!("{ic} "),
        _ => String::new(),
    };
    let bar_text = color_span(&wrapper_color, &format!("{icon_prefix}{text}"));

    let tooltip = if let Some(fmt) = opts.tooltip_format.as_deref() {
        substitute(fmt, &pango_values)
    } else {
        render_tooltip(outcome, snap, theme, opts, now)
    };

    WaybarOutput {
        text: bar_text,
        tooltip,
        class,
    }
}

fn render_tooltip(
    outcome: &VendorOutcome,
    snap: &MinimaxSnapshot,
    theme: &Theme,
    opts: &RenderOpts,
    now: DateTime<Utc>,
) -> String {
    let blue = &theme.blue;
    let dim = &theme.dim;
    let fg = &theme.fg;

    let mut lines: Vec<TooltipLine> = Vec::new();
    lines.push(TooltipLine::Center(format!(
        "<span font_weight='bold' foreground='{blue}'>{}</span>",
        escape(&snap.plan)
    )));
    lines.push(TooltipLine::Sep);

    // Rows go through the shared window helper so a pool reads like every
    // other vendor's block — bar, percentage, pace arrow — instead of the bare
    // `Session 20%` pair MiniMax printed before. The pool keeps its heading,
    // the way Antigravity groups its Gemini / third-party budgets.
    let mut pool = |label: &str, icon: &str, session: &UsageWindow, weekly: &UsageWindow| {
        lines.push(TooltipLine::Body("".into()));
        lines.push(TooltipLine::Body(format!(
            " <span font_weight='bold' foreground='{fg}'>  {icon}  {label}</span>"
        )));
        for (slot, (what, w)) in [("  󰔟  Session", session), ("  󰃰  Weekly", weekly)]
            .into_iter()
            .enumerate()
        {
            if slot > 0 {
                lines.push(TooltipLine::Body("".into()));
            }
            push_window_with_row(
                &mut lines,
                what,
                w,
                theme,
                now,
                WindowRow::paced(w, now, opts.pace_tolerance, opts.tooltip_pace_pts),
            );
        }
    };

    pool(POOL_GENERAL, "󰅄", &snap.session, &snap.weekly);
    if let (Some(vs), Some(vw)) = (&snap.video_session, &snap.video_weekly) {
        pool(POOL_VIDEO, "󰕧", vs, vw);
    }

    if let Some((code, msg)) = outcome.last_error.as_ref() {
        let (label, icon, ecolor) = if *code == 0 {
            ("MiniMax error".to_string(), "󰅚", theme.red.as_str())
        } else if *code >= 500 {
            (format!("HTTP {code}"), "󰅚", theme.red.as_str())
        } else {
            (format!("HTTP {code}"), "󰀪", theme.orange.as_str())
        };
        lines.push(TooltipLine::Body("".into()));
        lines.push(TooltipLine::Sep);
        lines.push(TooltipLine::Body(format!(
            " <span foreground='{ecolor}'>  {icon}  {label}</span>"
        )));
        if msg != &label {
            lines.push(TooltipLine::Body(format!(
                "     <span foreground='{dim}'>{}</span>",
                escape(msg)
            )));
        }
    }

    let updated = updated_at_hm(now, outcome.cache_age);
    lines.push(TooltipLine::Body("".into()));
    lines.push(TooltipLine::Sep);
    lines.push(TooltipLine::Body(format!(
        " <span foreground='{dim}'>  󰅐  Updated {updated}</span>"
    )));

    render_bordered(&lines, theme)
}

impl From<FetchOutcome> for VendorOutcome {
    fn from(o: FetchOutcome) -> Self {
        o.map(crate::usage::VendorSnapshot::Minimax)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 27, 12, 0, 0).unwrap()
    }

    fn window(pct: i32, mins_ahead: i64, dur: chrono::Duration) -> UsageWindow {
        UsageWindow {
            utilization_pct: pct,
            resets_at: Some(now() + chrono::Duration::minutes(mins_ahead)),
            window_duration: dur,
        }
    }

    fn snap() -> MinimaxSnapshot {
        MinimaxSnapshot {
            plan: "MiniMax Token Plan".to_string(),
            session: window(31, 45, chrono::Duration::hours(5)),
            weekly: window(62, 3000, chrono::Duration::days(7)),
            video_session: Some(window(5, 200, chrono::Duration::hours(24))),
            video_weekly: Some(window(9, 3000, chrono::Duration::days(7))),
        }
    }

    fn opts() -> RenderOpts {
        RenderOpts {
            format: None,
            tooltip_format: None,
            icon: None,
            pace_tolerance: 5,
            format_pace_color: false,
            tooltip_pace_pts: false,
        }
    }

    fn placeholders_at(
        snap: &MinimaxSnapshot,
        now: DateTime<Utc>,
    ) -> HashMap<&'static str, String> {
        build_placeholders_with_tolerance(snap, opts().pace_tolerance, now)
    }

    fn outcome(s: &MinimaxSnapshot) -> VendorOutcome {
        VendorOutcome {
            snapshot: crate::usage::VendorSnapshot::Minimax(s.clone()),
            stale: false,
            last_error: None,
            cache_age: Some(std::time::Duration::ZERO),
        }
    }

    #[test]
    fn default_format_shows_session_percent_and_reset() {
        let s = snap();
        let out = render(&outcome(&s), &s, &Theme::default(), &opts(), now());
        assert!(out.text.contains("31%"), "bar text was {:?}", out.text);
    }

    /// Cross-vendor aliases are what the GNOME/macOS surfaces read; without
    /// them MiniMax would render blank rows on the desktop.
    #[test]
    fn exposes_cross_vendor_aliases() {
        let v = placeholders_at(&snap(), now());
        assert_eq!(v.get("session_pct").map(String::as_str), Some("31"));
        assert_eq!(v.get("weekly_pct").map(String::as_str), Some("62"));
        assert_eq!(v.get("vendor_short").map(String::as_str), Some("mmx"));
        assert!(v.contains_key("session_reset"));
    }

    /// The video pool must not drag the coding bar into red.
    #[test]
    fn severity_ignores_the_video_pool() {
        let mut s = snap();
        s.session.utilization_pct = 10;
        s.weekly.utilization_pct = 10;
        s.video_session = Some(window(99, 10, chrono::Duration::hours(24)));
        s.video_weekly = Some(window(99, 10, chrono::Duration::days(7)));
        assert_eq!(severity(&s), severity_for(10));
    }

    #[test]
    fn video_placeholders_degrade_to_a_dash_without_the_pool() {
        let mut s = snap();
        s.video_session = None;
        s.video_weekly = None;
        let v = placeholders_at(&s, now());
        assert_eq!(v.get("minimax_video_pct").map(String::as_str), Some("—"));
        assert_eq!(
            v.get("minimax_video_weekly_pct").map(String::as_str),
            Some("—")
        );
        assert_eq!(v.get("minimax_video_pace").map(String::as_str), Some("—"));
        assert_eq!(
            v.get("minimax_video_weekly_reset").map(String::as_str),
            Some("—")
        );
        assert_eq!(
            v.get("minimax_video_weekly_pace").map(String::as_str),
            Some("—")
        );
    }

    #[test]
    fn public_builder_keeps_the_default_tolerance_api() {
        let snap = snap();
        assert_eq!(
            build_placeholders(&snap, now()),
            build_placeholders_with_tolerance(&snap, pacing::DEFAULT_TOLERANCE, now())
        );
    }

    #[test]
    fn present_window_without_reset_uses_documented_neutral_pacing() {
        let mut snap = snap();
        snap.session.resets_at = None;
        let values = placeholders_at(&snap, now());
        assert_eq!(values["minimax_session_reset"], "—");
        assert_eq!(values["minimax_session_elapsed"], "0");
        assert_eq!(values["minimax_session_pace"], "→");
        assert_eq!(values["minimax_session_pace_indicator"], "→");
    }

    #[test]
    fn pace_placeholders_follow_usage_vs_elapsed() {
        // Session: 80% used vs 2h/5h = 60% elapsed → ahead of pace. Weekly:
        // 15% used vs 3d/7d = 57% elapsed → under pace.
        let n = now();
        let mut s = snap();
        s.session = window(80, 120, chrono::Duration::hours(5));
        s.weekly = window(15, 3 * 24 * 60, chrono::Duration::days(7));
        let v = placeholders_at(&s, n);
        assert_eq!(v["minimax_session_elapsed"], "60");
        assert_eq!(v["minimax_session_pace"], "↑");
        assert_eq!(v["minimax_session_pace_indicator"], "↑");
        assert_eq!(v["minimax_weekly_elapsed"], "57");
        assert_eq!(v["minimax_weekly_pace"], "↓");
        assert_eq!(v["minimax_weekly_pace_indicator"], "↓");
    }

    #[test]
    fn video_pace_follows_usage_vs_elapsed() {
        // 90% used vs 6h/24h = 75% elapsed → ahead of pace.
        let n = now();
        let mut s = snap();
        s.video_session = Some(window(90, 6 * 60, chrono::Duration::hours(24)));
        let v = placeholders_at(&s, n);
        assert_eq!(v["minimax_video_elapsed"], "75");
        assert_eq!(v["minimax_video_pace"], "↑");
        assert_eq!(v["minimax_video_pace_indicator"], "↑");
    }

    #[test]
    fn video_weekly_exposes_the_complete_pacing_family() {
        let n = now();
        let mut s = snap();
        s.video_weekly = Some(window(90, 3 * 24 * 60, chrono::Duration::days(7)));
        let v = placeholders_at(&s, n);
        assert_ne!(v["minimax_video_weekly_reset"], "—");
        assert_eq!(v["minimax_video_weekly_elapsed"], "57");
        assert_eq!(v["minimax_video_weekly_pace"], "↑");
        assert_eq!(v["minimax_video_weekly_pace_indicator"], "↑");
    }

    #[test]
    fn tooltip_lists_both_pools_when_present() {
        let s = snap();
        let tip = render_tooltip(&outcome(&s), &s, &Theme::default(), &opts(), now());
        assert!(tip.contains(POOL_GENERAL));
        assert!(tip.contains(POOL_VIDEO));
    }

    #[test]
    fn tooltip_omits_the_video_pool_when_absent() {
        let mut s = snap();
        s.video_session = None;
        s.video_weekly = None;
        let tip = render_tooltip(&outcome(&s), &s, &Theme::default(), &opts(), now());
        assert!(tip.contains(POOL_GENERAL));
        assert!(!tip.contains(POOL_VIDEO));
    }

    /// Plan text reaches Pango exactly once escaped, from both paths.
    #[test]
    fn escapes_the_plan_name_exactly_once() {
        let mut s = snap();
        s.plan = "Plan <b>&</b>".to_string();
        let out = render(
            &outcome(&s),
            &s,
            &Theme::default(),
            &RenderOpts {
                format: Some("{minimax_plan}".to_string()),
                ..opts()
            },
            now(),
        );
        assert!(
            out.text.contains("&lt;b&gt;&amp;&lt;/b&gt;"),
            "{:?}",
            out.text
        );
        assert!(
            !out.text.contains("&amp;lt;"),
            "double-escaped: {:?}",
            out.text
        );
    }

    #[test]
    fn stale_marks_the_bar() {
        let s = snap();
        let mut o = outcome(&s);
        o.stale = true;
        let out = render(&o, &s, &Theme::default(), &opts(), now());
        assert!(out.text.contains('⏸'));
    }

    /// MiniMax printed a bare `Session 20%` pair per pool; both rows now draw
    /// the shared bar and carry the pace arrow the placeholders already had.
    #[test]
    fn tooltip_draws_a_bar_and_pace_arrow_for_every_pool_row() {
        let s = snap();
        let tip = render_tooltip(&outcome(&s), &s, &Theme::default(), &opts(), now());
        let cells = tip.matches('░').count() + tip.matches('█').count();
        assert_eq!(
            cells,
            4 * crate::pango::BAR_LEN as usize,
            "expected a bar for each of the four windows: {tip}"
        );
        let arrows = tip.matches('↑').count() + tip.matches('→').count() + tip.matches('↓').count();
        assert_eq!(arrows, 4, "expected one arrow per window: {tip}");
    }

    #[test]
    fn the_elapsed_marker_stays_behind_tooltip_pace_pts() {
        let s = snap();
        let plain = render_tooltip(&outcome(&s), &s, &Theme::default(), &opts(), now());
        let paced = render_tooltip(
            &outcome(&s),
            &s,
            &Theme::default(),
            &RenderOpts {
                tooltip_pace_pts: true,
                ..opts()
            },
            now(),
        );
        assert_ne!(plain, paced, "the marker should redraw the bars");
    }
}
