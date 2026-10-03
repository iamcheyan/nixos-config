//! Kiro CLI renderer — a single credit pool (used/limit + reset), closer in
//! shape to `anthropic_api::vendor` (one headline %) than to Cursor's two
//! pools, plus the reset countdown/tooltip layout `cursor::vendor` uses.

use std::collections::HashMap;

use chrono::{DateTime, Utc};

use crate::countdown;
use crate::format::{placeholders, substitute, updated_at_hm};
use crate::pacing::PaceSeverity;
use crate::pango::{color_span, escape, severity_color, severity_for};
use crate::theme::Theme;
use crate::tooltip::{Line as TooltipLine, render_bordered};
use crate::usage::KiroSnapshot;
use crate::vendor::{RenderOpts, VendorId, VendorOutcome};
use crate::waybar::{Class, WaybarOutput};

use super::fetch::FetchOutcome;

pub const DEFAULT_FORMAT: &str = "{kiro_pct}%";

/// No confirmed Kiro glyph in the common Nerd Font sets — a plain diamond,
/// matching Cursor's "no dedicated icon" treatment. Override with `--icon`.
const DEFAULT_ICON: &str = "◆";

fn credits(v: f64) -> String {
    // Two decimals only when the wire value actually carries a fraction
    // (kiro-cli's own `/usage` shows "9943.38 of 10000", not "9943.00").
    if (v.fract()).abs() < f64::EPSILON {
        format!("{v:.0}")
    } else {
        format!("{v:.2}")
    }
}

pub fn build_placeholders(
    snap: &KiroSnapshot,
    now: DateTime<Utc>,
) -> HashMap<&'static str, String> {
    let pct = snap.pct();
    let reset = countdown::format(snap.reset_at, now);
    placeholders(vec![
        ("icon", DEFAULT_ICON.to_string()),
        ("vendor_short", VendorId::Kiro.short_name().to_string()),
        // Cross-vendor aliases: one pool, so it fills both generic slots.
        ("plan", snap.plan.clone()),
        ("session_pct", pct.to_string()),
        ("session_reset", reset.clone()),
        ("weekly_pct", pct.to_string()),
        ("weekly_reset", reset.clone()),
        // Kiro-specific placeholders.
        ("kiro_plan", snap.plan.clone()),
        ("kiro_pct", pct.to_string()),
        ("kiro_used", credits(snap.used)),
        ("kiro_limit", credits(snap.limit)),
        ("kiro_reset", reset),
    ])
}

pub fn severity(snap: &KiroSnapshot) -> PaceSeverity {
    severity_for(snap.pct())
}

pub fn render(
    outcome: &VendorOutcome,
    snap: &KiroSnapshot,
    theme: &Theme,
    opts: &RenderOpts,
    now: DateTime<Utc>,
) -> WaybarOutput {
    let class = Class::from(severity(snap));
    let format = opts
        .format
        .clone()
        .unwrap_or_else(|| DEFAULT_FORMAT.to_string());
    let mut values = build_placeholders(snap, now);
    // Both sinks fed by this map (bar text and --tooltip-format) are Pango
    // markup. The plan label is API-controlled, so escape its aliases at the
    // projection boundary. The default tooltip escapes the raw snapshot.
    for key in ["plan", "kiro_plan"] {
        if let Some(value) = values.get_mut(key) {
            *value = escape(value);
        }
    }

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
        render_tooltip(outcome, snap, theme, now)
    };

    WaybarOutput {
        text: bar_text,
        tooltip,
        class,
    }
}

fn render_tooltip(
    outcome: &VendorOutcome,
    snap: &KiroSnapshot,
    theme: &Theme,
    now: DateTime<Utc>,
) -> String {
    let blue = &theme.blue;
    let dim = &theme.dim;
    let fg = &theme.fg;
    let pct = snap.pct();
    let color = severity_color(severity(snap), theme);

    let mut lines: Vec<TooltipLine> = Vec::new();
    lines.push(TooltipLine::Center(format!(
        "<span font_weight='bold' foreground='{blue}'>Kiro {}</span>",
        escape(&snap.plan)
    )));
    lines.push(TooltipLine::Sep);
    lines.push(TooltipLine::Body("".into()));
    lines.push(TooltipLine::Body(format!(
        " <span foreground='{fg}'>  󰠮  Credits</span>"
    )));
    lines.push(TooltipLine::Body(format!(
        "   <span font_weight='bold' foreground='{color}'>{pct}%</span> used \
         <span foreground='{dim}'>({} of {})</span>",
        credits(snap.used),
        credits(snap.limit)
    )));

    lines.push(TooltipLine::Body("".into()));
    lines.push(TooltipLine::Body(format!(
        " <span foreground='{dim}'>  󰃰  Resets {}</span>",
        escape(&countdown::format(snap.reset_at, now))
    )));

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
        o.map(crate::usage::VendorSnapshot::Kiro)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 26, 12, 0, 0).unwrap()
    }

    fn sample_snap() -> KiroSnapshot {
        KiroSnapshot {
            plan: "KIRO POWER".into(),
            used: 9943.38,
            limit: 10000.0,
            reset_at: Some(now() + chrono::Duration::days(1)),
        }
    }

    fn sample_outcome(snap: KiroSnapshot) -> VendorOutcome {
        VendorOutcome {
            snapshot: crate::usage::VendorSnapshot::Kiro(snap),
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

    #[test]
    fn default_bar_shows_the_percentage() {
        let snap = sample_snap();
        let out = render(
            &sample_outcome(snap.clone()),
            &snap,
            &Theme::default(),
            &opts(),
            now(),
        );
        assert!(out.text.contains("99%"), "text: {}", out.text);
    }

    #[test]
    fn tooltip_shows_plan_credits_and_reset() {
        let snap = sample_snap();
        let out = render(
            &sample_outcome(snap.clone()),
            &snap,
            &Theme::default(),
            &opts(),
            now(),
        );
        assert!(out.tooltip.contains("Kiro KIRO POWER"));
        assert!(out.tooltip.contains("99%"));
        assert!(out.tooltip.contains("9943.38"));
        assert!(out.tooltip.contains("10000"));
        assert!(out.tooltip.contains("1d"));
    }

    #[test]
    fn whole_number_credits_have_no_decimals() {
        assert_eq!(credits(10000.0), "10000");
        assert_eq!(credits(9943.38), "9943.38");
    }

    #[test]
    fn severity_tracks_the_credit_percentage() {
        let mut snap = sample_snap();
        snap.used = 99.0;
        snap.limit = 100.0;
        assert_eq!(severity(&snap), PaceSeverity::Critical);
    }

    #[test]
    fn stale_appends_pause() {
        let snap = sample_snap();
        let mut outcome = sample_outcome(snap.clone());
        outcome.stale = true;
        let out = render(&outcome, &snap, &Theme::default(), &opts(), now());
        assert!(out.text.contains("⏸"));
    }

    #[test]
    fn custom_tooltip_uses_placeholders() {
        let snap = sample_snap();
        let mut o = opts();
        o.tooltip_format = Some("{kiro_pct}% of {kiro_limit} · {kiro_plan}".into());
        let out = render(
            &sample_outcome(snap.clone()),
            &snap,
            &Theme::default(),
            &o,
            now(),
        );
        assert_eq!(out.tooltip, "99% of 10000 · KIRO POWER");
    }

    #[test]
    fn api_plan_is_inert_in_custom_pango_formats() {
        let mut snap = sample_snap();
        snap.plan = "<b>not markup</b> & control\u{1b}".into();
        let mut o = opts();
        o.format = Some("{kiro_plan}".into());
        o.tooltip_format = Some("{plan}".into());

        let out = render(
            &sample_outcome(snap.clone()),
            &snap,
            &Theme::default(),
            &o,
            now(),
        );

        assert!(!out.text.contains("<b>"));
        assert!(!out.tooltip.contains("<b>"));
        assert!(
            out.text
                .contains("&lt;b&gt;not markup&lt;/b&gt; &amp; control")
        );
        assert_eq!(out.tooltip, "&lt;b&gt;not markup&lt;/b&gt; &amp; control");
        assert!(!out.text.contains('\u{1b}'));
    }

    #[test]
    fn generic_windows_map_to_the_single_pool() {
        let values = build_placeholders(&sample_snap(), now());
        assert_eq!(values["session_pct"], "99");
        assert_eq!(values["weekly_pct"], "99");
        assert_eq!(values["plan"], "KIRO POWER");
    }

    #[test]
    fn placeholder_set_contains_all_keys() {
        let values = build_placeholders(&sample_snap(), now());
        for key in [
            "icon",
            "vendor_short",
            "plan",
            "session_pct",
            "session_reset",
            "weekly_pct",
            "weekly_reset",
            "kiro_plan",
            "kiro_pct",
            "kiro_used",
            "kiro_limit",
            "kiro_reset",
        ] {
            assert!(values.contains_key(key), "missing placeholder {key}");
        }
    }

    #[test]
    fn fetch_outcome_conversion_preserves_metadata() {
        let fetch = FetchOutcome {
            snapshot: sample_snap(),
            stale: true,
            last_error: Some((401, "bad".into())),
            cache_age: Some(std::time::Duration::from_secs(42)),
        };
        let vendor: VendorOutcome = fetch.into();
        assert!(matches!(
            vendor.snapshot,
            crate::usage::VendorSnapshot::Kiro(_)
        ));
        assert!(vendor.stale);
    }
}
