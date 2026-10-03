//! Z.AI renderer — bar text + bordered Pango tooltip.

use std::collections::HashMap;

use chrono::{DateTime, Utc};

use crate::countdown;
use crate::format::{placeholders, substitute, updated_at_hm};
use crate::pacing::{self, PaceSeverity};
use crate::pango::{color_span, escape, severity_color, severity_for};
use crate::theme::Theme;
use crate::tooltip::{Line as TooltipLine, WindowRow, push_window_with_row, render_bordered};
use crate::usage::{UsageWindow, ZaiSnapshot};
use crate::vendor::{RenderOpts, VendorId, VendorOutcome};
use crate::waybar::{Class, WaybarOutput};

use super::fetch::FetchOutcome;

pub const DEFAULT_FORMAT: &str = "{zai_session_pct}% · {zai_session_reset}";

/// Build placeholders with the historical default pacing tolerance.
///
/// Keep this signature stable for library callers. Rendering uses the private
/// tolerance-aware helper so `--pace-tolerance` still applies.
pub fn build_placeholders(snap: &ZaiSnapshot, now: DateTime<Utc>) -> HashMap<&'static str, String> {
    build_placeholders_with_tolerance(snap, pacing::DEFAULT_TOLERANCE, now)
}

fn build_placeholders_with_tolerance(
    snap: &ZaiSnapshot,
    pace_tolerance: u32,
    now: DateTime<Utc>,
) -> HashMap<&'static str, String> {
    let session_pct = snap
        .session
        .as_ref()
        .map(|w| w.utilization_pct)
        .unwrap_or(0);
    let weekly_pct = snap.weekly.as_ref().map(|w| w.utilization_pct).unwrap_or(0);
    let mcp_pct = snap.mcp.as_ref().map(|w| w.utilization_pct).unwrap_or(0);
    // A present window normally carries a reset, but the upstream response may
    // omit it. `pacing::calc` deliberately returns neutral 0/arrow values in
    // that case, matching the established OpenAI placeholder contract.
    let session = window_pacing(snap.session.as_ref(), pace_tolerance, now);
    let weekly = window_pacing(snap.weekly.as_ref(), pace_tolerance, now);
    let mcp = window_pacing(snap.mcp.as_ref(), pace_tolerance, now);
    placeholders(vec![
        ("icon", "󰚩".to_string()),
        ("vendor_short", VendorId::Zai.short_name().to_string()),
        // Cross-vendor aliases for scroll-cycle friendly formats.
        ("session_pct", session_pct.to_string()),
        (
            "session_reset",
            countdown::format(window_reset(&snap.session), now),
        ),
        ("weekly_pct", weekly_pct.to_string()),
        (
            "weekly_reset",
            countdown::format(window_reset(&snap.weekly), now),
        ),
        ("session_elapsed", session.elapsed.clone()),
        ("weekly_elapsed", weekly.elapsed.clone()),
        ("plan", snap.plan.clone()),
        ("zai_plan", snap.plan.clone()),
        ("zai_session_pct", session_pct.to_string()),
        (
            "zai_session_reset",
            countdown::format(window_reset(&snap.session), now),
        ),
        ("zai_weekly_pct", weekly_pct.to_string()),
        (
            "zai_weekly_reset",
            countdown::format(window_reset(&snap.weekly), now),
        ),
        ("zai_session_elapsed", session.elapsed),
        ("zai_session_pace", session.ratio_pace),
        ("zai_session_pace_indicator", session.point_pace),
        ("zai_weekly_elapsed", weekly.elapsed),
        ("zai_weekly_pace", weekly.ratio_pace),
        ("zai_weekly_pace_indicator", weekly.point_pace),
        ("zai_mcp_pct", mcp_pct.to_string()),
        (
            "zai_mcp_reset",
            countdown::format(window_reset(&snap.mcp), now),
        ),
        ("zai_mcp_elapsed", mcp.elapsed),
        ("zai_mcp_pace", mcp.ratio_pace),
        ("zai_mcp_pace_indicator", mcp.point_pace),
    ])
}

fn window_reset(w: &Option<UsageWindow>) -> Option<DateTime<Utc>> {
    w.as_ref().and_then(|w| w.resets_at)
}

/// Elapsed fraction and pace glyphs for one window, as ready placeholder
/// values. Empty strings when the window is absent, mirroring the OpenAI
/// renderer's convention; `pacing::calc` degrades to neutral 0/glyphs when
/// the reset is unreported.
#[derive(Default)]
struct WindowPacing {
    elapsed: String,
    ratio_pace: String,
    point_pace: String,
}

fn window_pacing(w: Option<&UsageWindow>, pace_tolerance: u32, now: DateTime<Utc>) -> WindowPacing {
    let Some(w) = w else {
        return WindowPacing::default();
    };
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

pub fn severity(snap: &ZaiSnapshot) -> PaceSeverity {
    let session = snap
        .session
        .as_ref()
        .map(|w| w.utilization_pct)
        .unwrap_or(0);
    let weekly = snap.weekly.as_ref().map(|w| w.utilization_pct).unwrap_or(0);
    let mcp = snap.mcp.as_ref().map(|w| w.utilization_pct).unwrap_or(0);
    severity_for([session, weekly, mcp].into_iter().max().unwrap_or(0))
}

pub fn render(
    outcome: &VendorOutcome,
    snap: &ZaiSnapshot,
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

    let mut text = substitute(&format, &values);
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
        substitute(fmt, &values)
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
    snap: &ZaiSnapshot,
    theme: &Theme,
    opts: &RenderOpts,
    now: DateTime<Utc>,
) -> String {
    let blue = &theme.blue;
    let dim = &theme.dim;
    // The `{zai_*_pace}` placeholders already carry this; the default tooltip
    // never consulted them, so the arrow the macOS bar draws was missing here.
    let row =
        |w: &UsageWindow| WindowRow::paced(w, now, opts.pace_tolerance, opts.tooltip_pace_pts);
    let mut lines: Vec<TooltipLine> = Vec::new();
    lines.push(TooltipLine::Center(format!(
        "<span font_weight='bold' foreground='{blue}'>{plan}</span>",
        plan = escape(&snap.plan)
    )));
    lines.push(TooltipLine::Sep);
    lines.push(TooltipLine::Body("".into()));

    if let Some(w) = snap.session.as_ref() {
        push_window_with_row(&mut lines, "  󰔟  Session (5h)", w, theme, now, row(w));
    }
    if let Some(w) = snap.weekly.as_ref() {
        if snap.session.is_some() {
            lines.push(TooltipLine::Body("".into()));
        }
        push_window_with_row(&mut lines, "  󰃰  Weekly", w, theme, now, row(w));
    }
    if let Some(w) = snap.mcp.as_ref() {
        lines.push(TooltipLine::Body("".into()));
        lines.push(TooltipLine::Sep);
        push_window_with_row(
            &mut lines,
            "  󰓹  MCP tools (monthly)",
            w,
            theme,
            now,
            row(w),
        );
    }
    if snap.session.is_none() && snap.weekly.is_none() && snap.mcp.is_none() {
        lines.push(TooltipLine::Body(format!(
            " <span foreground='{dim}'>no usage windows reported</span>"
        )));
    }

    if let Some((code, msg)) = outcome.last_error.as_ref()
        && *code != 0
    {
        let (icon, ecolor) = if *code >= 500 {
            ("󰅚", theme.red.as_str())
        } else {
            ("󰀪", theme.orange.as_str())
        };
        lines.push(TooltipLine::Body("".into()));
        lines.push(TooltipLine::Sep);
        lines.push(TooltipLine::Body(format!(
            " <span foreground='{ecolor}'>  {icon}  HTTP {code}</span>"
        )));
        lines.push(TooltipLine::Body(format!(
            "     <span foreground='{dim}'>{}</span>",
            escape(msg)
        )));
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
        o.map(crate::usage::VendorSnapshot::Zai)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::usage::{UsageWindow, ZaiSnapshot};

    fn sample_snap() -> ZaiSnapshot {
        let now = Utc::now();
        ZaiSnapshot {
            plan: "GLM Coding Pro".into(),
            session: Some(UsageWindow {
                utilization_pct: 42,
                resets_at: Some(now + chrono::Duration::hours(2)),
                window_duration: chrono::Duration::hours(5),
            }),
            weekly: Some(UsageWindow {
                utilization_pct: 15,
                resets_at: Some(now + chrono::Duration::days(3)),
                window_duration: chrono::Duration::days(7),
            }),
            mcp: None,
        }
    }

    fn outcome(s: ZaiSnapshot) -> VendorOutcome {
        VendorOutcome {
            snapshot: crate::usage::VendorSnapshot::Zai(s),
            stale: false,
            last_error: None,
            cache_age: Some(std::time::Duration::from_secs(10)),
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

    fn placeholders_at(snap: &ZaiSnapshot, now: DateTime<Utc>) -> HashMap<&'static str, String> {
        build_placeholders_with_tolerance(snap, opts().pace_tolerance, now)
    }

    #[test]
    fn default_format_renders_session_pct() {
        let snap = sample_snap();
        let oc = outcome(snap.clone());
        let out = render(&oc, &snap, &Theme::default(), &opts(), Utc::now());
        assert!(out.text.contains("42%"));
    }

    #[test]
    fn elapsed_placeholders_follow_window_progress() {
        // Fixed `now` on both sides so the fraction is exact: 2h left of a 5h
        // window → 60% elapsed; 3d left of a 7d window → 57%.
        let now = Utc::now();
        let snap = ZaiSnapshot {
            plan: "GLM Coding Pro".into(),
            session: Some(UsageWindow {
                utilization_pct: 42,
                resets_at: Some(now + chrono::Duration::hours(2)),
                window_duration: chrono::Duration::hours(5),
            }),
            weekly: Some(UsageWindow {
                utilization_pct: 15,
                resets_at: Some(now + chrono::Duration::days(3)),
                window_duration: chrono::Duration::days(7),
            }),
            mcp: None,
        };
        let values = placeholders_at(&snap, now);
        assert_eq!(values["session_elapsed"], "60");
        assert_eq!(values["weekly_elapsed"], "57");
    }

    #[test]
    fn pace_placeholders_follow_usage_vs_elapsed() {
        // Session: 80% used vs 60% elapsed → ahead of pace. Weekly: 15% used
        // vs 57% elapsed → under pace.
        let now = Utc::now();
        let snap = ZaiSnapshot {
            plan: "GLM Coding Pro".into(),
            session: Some(UsageWindow {
                utilization_pct: 80,
                resets_at: Some(now + chrono::Duration::hours(2)),
                window_duration: chrono::Duration::hours(5),
            }),
            weekly: Some(UsageWindow {
                utilization_pct: 15,
                resets_at: Some(now + chrono::Duration::days(3)),
                window_duration: chrono::Duration::days(7),
            }),
            mcp: None,
        };
        let values = placeholders_at(&snap, now);
        assert_eq!(values["zai_session_pace"], "↑");
        assert_eq!(values["zai_session_pace_indicator"], "↑");
        assert_eq!(values["zai_weekly_pace"], "↓");
        assert_eq!(values["zai_weekly_pace_indicator"], "↓");
        assert_eq!(values["zai_session_elapsed"], "60");
        assert_eq!(values["zai_weekly_elapsed"], "57");
    }

    #[test]
    fn public_builder_keeps_the_default_tolerance_api() {
        let now = Utc::now();
        let snap = sample_snap();
        assert_eq!(
            build_placeholders(&snap, now),
            build_placeholders_with_tolerance(&snap, pacing::DEFAULT_TOLERANCE, now)
        );
    }

    #[test]
    fn custom_tolerance_changes_the_ratio_pace() {
        let now = Utc::now();
        let snap = ZaiSnapshot {
            plan: "GLM Coding Pro".into(),
            session: Some(UsageWindow {
                utilization_pct: 53,
                resets_at: Some(now + chrono::Duration::minutes(150)),
                window_duration: chrono::Duration::hours(5),
            }),
            weekly: None,
            mcp: None,
        };
        assert_eq!(
            build_placeholders_with_tolerance(&snap, 5, now)["zai_session_pace"],
            "↑"
        );
        assert_eq!(
            build_placeholders_with_tolerance(&snap, 10, now)["zai_session_pace"],
            "→"
        );
    }

    #[test]
    fn present_window_without_reset_uses_documented_neutral_pacing() {
        let now = Utc::now();
        let mut snap = sample_snap();
        snap.session.as_mut().unwrap().resets_at = None;
        let values = placeholders_at(&snap, now);
        assert_eq!(values["zai_session_reset"], "—");
        assert_eq!(values["zai_session_elapsed"], "0");
        assert_eq!(values["zai_session_pace"], "→");
        assert_eq!(values["zai_session_pace_indicator"], "→");
    }

    #[test]
    fn mcp_pace_placeholders_follow_usage_vs_elapsed() {
        // 70% used vs 15d/30d = 50% elapsed → ahead of pace.
        let now = Utc::now();
        let snap = ZaiSnapshot {
            plan: "GLM Coding Pro".into(),
            session: None,
            weekly: None,
            mcp: Some(UsageWindow {
                utilization_pct: 70,
                resets_at: Some(now + chrono::Duration::days(15)),
                window_duration: chrono::Duration::days(30),
            }),
        };
        let values = placeholders_at(&snap, now);
        assert_eq!(values["zai_mcp_elapsed"], "50");
        assert_eq!(values["zai_mcp_pace"], "↑");
        assert_eq!(values["zai_mcp_pace_indicator"], "↑");
    }

    #[test]
    fn elapsed_placeholders_empty_without_window() {
        let snap = ZaiSnapshot {
            plan: "GLM Coding Unknown".into(),
            session: None,
            weekly: None,
            mcp: None,
        };
        let values = placeholders_at(&snap, Utc::now());
        assert_eq!(values["session_elapsed"], "");
        assert_eq!(values["weekly_elapsed"], "");
        assert_eq!(values["zai_session_pace"], "");
        assert_eq!(values["zai_mcp_elapsed"], "");
        assert_eq!(values["zai_mcp_pace"], "");
    }

    #[test]
    fn tooltip_contains_all_windows_present() {
        let snap = sample_snap();
        let oc = outcome(snap.clone());
        let out = render(&oc, &snap, &Theme::default(), &opts(), Utc::now());
        assert!(out.tooltip.contains("Session"));
        assert!(out.tooltip.contains("Weekly"));
        assert!(!out.tooltip.contains("MCP"));
    }

    #[test]
    fn empty_snapshot_renders_no_windows_message() {
        let snap = ZaiSnapshot {
            plan: "GLM Coding Unknown".into(),
            session: None,
            weekly: None,
            mcp: None,
        };
        let oc = outcome(snap.clone());
        let out = render(&oc, &snap, &Theme::default(), &opts(), Utc::now());
        assert!(out.tooltip.contains("no usage windows reported"));
    }

    #[test]
    fn severity_picks_worst_window() {
        let mut snap = sample_snap();
        snap.weekly.as_mut().unwrap().utilization_pct = 95;
        assert_eq!(severity(&snap), PaceSeverity::Critical);
    }

    #[test]
    fn custom_tooltip_uses_placeholders() {
        let snap = sample_snap();
        let oc = outcome(snap.clone());
        let mut o = opts();
        o.tooltip_format = Some("S:{zai_session_pct} W:{zai_weekly_pct}".into());
        let out = render(&oc, &snap, &Theme::default(), &o, Utc::now());
        assert_eq!(out.tooltip, "S:42 W:15");
    }

    fn fixed_now() -> DateTime<Utc> {
        use chrono::TimeZone;
        Utc.with_ymd_and_hms(2026, 8, 25, 12, 0, 0).unwrap()
    }

    fn paced_snap() -> ZaiSnapshot {
        let now = fixed_now();
        ZaiSnapshot {
            plan: "GLM Coding Pro".into(),
            // 3h left of 5h → 40% elapsed against 80% used: clearly ahead.
            session: Some(UsageWindow {
                utilization_pct: 80,
                resets_at: Some(now + chrono::Duration::hours(3)),
                window_duration: chrono::Duration::hours(5),
            }),
            // Reported without a reset — the case the user's own account hits.
            weekly: Some(UsageWindow {
                utilization_pct: 3,
                resets_at: None,
                window_duration: chrono::Duration::days(7),
            }),
            mcp: None,
        }
    }

    /// The `{zai_*_pace}` placeholders have carried this since the pace PR; the
    /// default tooltip never read them, so the CLI showed no arrow where the
    /// macOS bar did.
    #[test]
    fn tooltip_shows_the_pace_arrow_next_to_each_percentage() {
        let snap = paced_snap();
        let out = render(
            &outcome(snap.clone()),
            &snap,
            &Theme::default(),
            &opts(),
            fixed_now(),
        );
        assert!(out.tooltip.contains("80% ↑"), "{}", out.tooltip);
        // No reset reported → neutral pacing rather than a blank column.
        assert!(out.tooltip.contains("3% →"), "{}", out.tooltip);
    }

    /// The elapsed marker stays opt-in, exactly as on the Anthropic tooltip.
    #[test]
    fn the_elapsed_marker_stays_behind_tooltip_pace_pts() {
        let snap = paced_snap();
        let plain = render(
            &outcome(snap.clone()),
            &snap,
            &Theme::default(),
            &opts(),
            fixed_now(),
        );
        let paced = render(
            &outcome(snap.clone()),
            &snap,
            &Theme::default(),
            &RenderOpts {
                tooltip_pace_pts: true,
                ..opts()
            },
            fixed_now(),
        );
        assert_ne!(
            plain.tooltip, paced.tooltip,
            "the marker should redraw the bars"
        );
        assert!(paced.tooltip.contains("80% ↑"), "{}", paced.tooltip);
    }
}
