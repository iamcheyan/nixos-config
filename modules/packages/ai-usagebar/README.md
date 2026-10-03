# ai-usagebar in Anchor Shell

The `upstream/` directory vendors the Rust application from
[akitaonrails/ai-usagebar](https://github.com/akitaonrails/ai-usagebar), version
1.30.0, commit `ad28ba6118b6ac391ea54b76a0498c76d814de22` (MIT license).
The package derivation in `../ai-usagebar.nix` builds its CLI and TUI from this
copy, so updates and local changes are reviewed with this system repository.

The Anchor Shell adaptation lives in
`../../anchor-shell/plugins/ai-usagebar/`. It reads the selected provider's
JSON report, refreshes every five minutes, and opens `ai-usagebar-tui` on click.
The HX90 package and the default bar layout are wired in the host and shell
configuration.
