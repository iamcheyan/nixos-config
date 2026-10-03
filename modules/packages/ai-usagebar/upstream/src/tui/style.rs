//! Shared TUI styling adapters.

use ratatui::style::Color;
use ratatui_bubbletea_theme::{BubbleTheme, Palette, Symbols};

use crate::pacing::PaceSeverity;
use crate::theme::Theme;

/// Build a Charm/Bubble Tea-style theme while preserving this app's configured
/// foreground, dim, and health colors where possible.
pub fn bubble_theme(theme: &Theme) -> BubbleTheme {
    let charm = Palette::CHARM;
    let palette = Palette {
        foreground: color(&theme.fg).unwrap_or(charm.foreground),
        muted: color(&theme.dim).unwrap_or(charm.muted),
        accent: charm.accent,
        success: color(&theme.green).unwrap_or(charm.success),
        warning: color(&theme.yellow).unwrap_or(charm.warning),
        error: color(&theme.red).unwrap_or(charm.error),
        border: color(&theme.dim).unwrap_or(charm.border),
        focused_border: color(&theme.blue).unwrap_or(charm.focused_border),
        selected_background: color(&theme.bar_empty).unwrap_or(charm.selected_background),
    };
    BubbleTheme::new(palette, Symbols::default())
}

pub fn color(hex: &str) -> Option<Color> {
    let (r, g, b) = crate::theme::parse_hex_rgb(hex)?;
    Some(Color::Rgb(r, g, b))
}

pub fn severity_color(theme: &Theme, bubble: &BubbleTheme, severity: PaceSeverity) -> Color {
    match severity {
        PaceSeverity::Low => bubble.palette.success,
        PaceSeverity::Mid => bubble.palette.warning,
        PaceSeverity::High => color(&theme.orange).unwrap_or(bubble.palette.warning),
        PaceSeverity::Critical => bubble.palette.error,
    }
}

pub fn progress_theme(base: BubbleTheme, filled: Color, empty: Color) -> BubbleTheme {
    let mut palette = base.palette;
    palette.accent = filled;
    palette.muted = empty;
    BubbleTheme::new(palette, base.symbols)
}
