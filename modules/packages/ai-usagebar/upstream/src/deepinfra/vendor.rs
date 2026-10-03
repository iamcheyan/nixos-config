//! DeepInfra renderer for prepaid balance and current-month usage.

use std::collections::HashMap;

use chrono::{DateTime, Utc};

use crate::format::{placeholders, substitute, updated_at_hm, usd};
use crate::pacing::PaceSeverity;
use crate::pango::{color_span, escape, severity_color, severity_for};
use crate::theme::Theme;
use crate::tooltip::{Line as TooltipLine, render_bordered};
use crate::usage::DeepInfraSnapshot;
use crate::vendor::{RenderOpts, VendorId, VendorOutcome};
use crate::waybar::{Class, WaybarOutput};

use super::fetch::FetchOutcome;

pub const DEFAULT_FORMAT: &str = "{dif_balance} · {dif_used_month}";

pub fn build_placeholders(snapshot: &DeepInfraSnapshot) -> HashMap<&'static str, String> {
    let consumed = snapshot.monthly_consumed_pct();
    let consumed_text = consumed
        .map(|percent| percent.to_string())
        .unwrap_or_else(|| "—".into());
    placeholders(vec![
        ("icon", VendorId::Deepinfra.bar_icon().to_string()),
        ("vendor_short", VendorId::Deepinfra.short_name().to_string()),
        ("session_pct", String::new()),
        ("session_reset", "-".into()),
        ("weekly_pct", String::new()),
        ("weekly_reset", "-".into()),
        ("plan", "DeepInfra".into()),
        ("dif_balance", usd(snapshot.balance)),
        ("dif_used_month", usd(snapshot.monthly_spend)),
        (
            "dif_limit",
            snapshot
                .monthly_limit
                .map(usd)
                .unwrap_or_else(|| "no limit".into()),
        ),
        ("dif_period", snapshot.period.clone()),
        ("dif_consumed_pct", consumed_text),
    ])
}

pub fn severity(snapshot: &DeepInfraSnapshot) -> PaceSeverity {
    let balance = crate::pango::balance_severity(snapshot.balance, "USD");
    match snapshot.monthly_consumed_pct() {
        Some(percent) => balance.max(severity_for(percent)),
        None => balance,
    }
}

pub fn render(
    outcome: &VendorOutcome,
    snapshot: &DeepInfraSnapshot,
    theme: &Theme,
    opts: &RenderOpts,
    now: DateTime<Utc>,
) -> WaybarOutput {
    let class = Class::from(severity(snapshot));
    let format = opts
        .format
        .clone()
        .unwrap_or_else(|| DEFAULT_FORMAT.to_string());
    let mut values = build_placeholders(snapshot);
    if let Some(period) = values.get_mut("dif_period") {
        *period = escape(period);
    }

    let mut text = substitute(&format, &values);
    if outcome.stale {
        text.push_str(" paused");
    }
    let wrapper_color = severity_color(severity(snapshot), theme).to_string();
    let icon_prefix = match opts.icon.as_deref() {
        Some(icon) if !icon.is_empty() => format!("{icon} "),
        _ => String::new(),
    };
    let bar_text = color_span(&wrapper_color, &format!("{icon_prefix}{text}"));
    let tooltip = if let Some(format) = opts.tooltip_format.as_deref() {
        substitute(format, &values)
    } else {
        render_tooltip(outcome, snapshot, theme, now)
    };

    WaybarOutput {
        text: bar_text,
        tooltip,
        class,
    }
}

fn render_tooltip(
    outcome: &VendorOutcome,
    snapshot: &DeepInfraSnapshot,
    theme: &Theme,
    now: DateTime<Utc>,
) -> String {
    let blue = &theme.blue;
    let dim = &theme.dim;
    let fg = &theme.fg;
    let balance_color = severity_color(severity(snapshot), theme);
    let mut lines = vec![
        TooltipLine::Center(format!(
            "<span font_weight='bold' foreground='{blue}'>DeepInfra</span>"
        )),
        TooltipLine::Sep,
        TooltipLine::Body(String::new()),
        TooltipLine::Body(format!(" <span foreground='{fg}'>  Balance</span>")),
        TooltipLine::Body(format!(
            "   <span font_weight='bold' foreground='{balance_color}'>{}</span>",
            escape(&usd(snapshot.balance))
        )),
        TooltipLine::Body(String::new()),
        TooltipLine::Body(format!(" <span foreground='{fg}'>  Monthly usage</span>")),
        TooltipLine::Body(format!(
            " <span foreground='{dim}'>     {} / {}</span>",
            escape(&usd(snapshot.monthly_spend)),
            snapshot
                .monthly_limit
                .map(usd)
                .unwrap_or_else(|| "no limit".into())
        )),
        TooltipLine::Body(format!(
            " <span foreground='{dim}'>     period {}</span>",
            escape(&snapshot.period)
        )),
    ];

    if let Some((code, message)) = outcome.last_error.as_ref()
        && *code != 0
    {
        let color = if *code >= 500 {
            theme.red.as_str()
        } else {
            theme.orange.as_str()
        };
        lines.push(TooltipLine::Body(String::new()));
        lines.push(TooltipLine::Sep);
        lines.push(TooltipLine::Body(format!(
            " <span foreground='{color}'>  HTTP {code}</span>"
        )));
        lines.push(TooltipLine::Body(format!(
            "     <span foreground='{dim}'>{}</span>",
            escape(message)
        )));
    }

    let updated = updated_at_hm(now, outcome.cache_age);
    lines.push(TooltipLine::Body(String::new()));
    lines.push(TooltipLine::Sep);
    lines.push(TooltipLine::Body(format!(
        " <span foreground='{dim}'>  Updated {updated}</span>"
    )));
    render_bordered(&lines, theme)
}

impl From<FetchOutcome> for VendorOutcome {
    fn from(outcome: FetchOutcome) -> Self {
        outcome.map(crate::usage::VendorSnapshot::Deepinfra)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn snapshot() -> DeepInfraSnapshot {
        DeepInfraSnapshot {
            balance: 2.92,
            monthly_spend: 2.08,
            monthly_limit: None,
            period: "2026.09".into(),
        }
    }

    fn outcome(snapshot: DeepInfraSnapshot) -> VendorOutcome {
        VendorOutcome {
            snapshot: crate::usage::VendorSnapshot::Deepinfra(snapshot),
            stale: false,
            last_error: None,
            cache_age: Some(Duration::from_secs(15)),
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
    fn default_render_shows_balance_and_monthly_usage() {
        let snapshot = snapshot();
        let rendered = render(
            &outcome(snapshot.clone()),
            &snapshot,
            &Theme::default(),
            &opts(),
            Utc::now(),
        );
        assert!(rendered.text.contains("$2.92"));
        assert!(rendered.text.contains("$2.08"));
        assert!(rendered.tooltip.contains("no limit"));
        assert!(rendered.tooltip.contains("2026.09"));
    }

    #[test]
    fn monthly_limit_affects_severity() {
        let mut snapshot = snapshot();
        snapshot.balance = 100.0;
        snapshot.monthly_limit = Some(2.0);
        assert_eq!(severity(&snapshot), PaceSeverity::Critical);
    }

    #[test]
    fn unlimited_placeholders_do_not_invent_a_percentage() {
        let values = build_placeholders(&snapshot());
        assert_eq!(
            values.get("dif_limit").map(String::as_str),
            Some("no limit")
        );
        assert_eq!(
            values.get("dif_consumed_pct").map(String::as_str),
            Some("—")
        );
        assert_eq!(values.get("session_pct").map(String::as_str), Some(""));
        assert_eq!(values.get("weekly_pct").map(String::as_str), Some(""));
    }
}
