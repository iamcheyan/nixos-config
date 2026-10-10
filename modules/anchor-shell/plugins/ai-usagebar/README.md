# AI usage bar widget

This is the Anchor Shell bar integration for the separately packaged
`ai-usagebar` CLI. It reads the CLI's JSON report, shows provider usage and
available reset credits, and opens its custom Quickshell panel on a single
click. Hovering does not open the panel, and clicking no longer launches a
terminal TUI. The package and its pinned upstream source are documented in
[`modules/packages/ai-usagebar/README.md`](../../../packages/ai-usagebar/README.md).

The Rust CLI/TUI source is vendored from
[akitaonrails/ai-usagebar](https://github.com/akitaonrails/ai-usagebar),
version 1.30.0 at commit `ad28ba6118b6ac391ea54b76a0498c76d814de22`. Its
upstream README, changelog, development guide, reference guides, and MIT
license are retained in `modules/packages/ai-usagebar/upstream/`. The QML in
this directory is the local Anchor Shell integration; it is not part of that
upstream source.

The widget is registered as `tetsuya.ai-usagebar` in `manifest.json`. It is
included by the HX90 system configuration and default bar layout. Provider
report parsing, the displayed providers, reset-credit details, refresh timing,
and panel behavior are implemented in `BarWidget.qml`; consult that file when
updating this adapter. Avoid editing files under `upstream/` without recording
the change separately from the imported upstream revision.
