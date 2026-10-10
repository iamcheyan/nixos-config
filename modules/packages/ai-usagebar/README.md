# ai-usagebar in Anchor Shell

The `upstream/` directory vendors the Rust application from
[akitaonrails/ai-usagebar](https://github.com/akitaonrails/ai-usagebar), version
1.30.0, commit `ad28ba6118b6ac391ea54b76a0498c76d814de22` (MIT license).
The upstream Markdown documentation, referenced screenshots, and `LICENSE`
are kept beside the vendored source at that same revision. This keeps the
upstream documentation links in the README working offline and makes the
license and update history reviewable with the source.

The package derivation in `../ai-usagebar.nix` builds its CLI and TUI from this
copy, so updates and local changes are reviewed with this system repository.
When updating, refresh the source and its documentation together, then update
the pinned revision above.

The Anchor Shell adaptation lives in
`../../anchor-shell/plugins/ai-usagebar/`. It reads the selected provider's
JSON report, refreshes every five minutes, and shows its custom Quickshell
usage panel on click. The bar does not launch the upstream terminal TUI.
The HX90 package and the default bar layout are wired in the host and shell
configuration. See that plugin's [README](../../anchor-shell/plugins/ai-usagebar/README.md)
for the shell integration and its differences from upstream.
