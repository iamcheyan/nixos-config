# Flux in Anchor Shell

Flux is built from upstream v0.10.1, commit
`1605304ac1bf6b132472fa248238be3d05ff1899`, by `modules/packages/flux.nix`.
The upstream repository has no selected license, so its source and shared QML
stay in the Nix build input instead of being copied into this repository. The
files here adapt the Omarchy Quickshell integration to Anchor Shell's service,
bar widget, and anchored popup contracts.

The Flux mark in the top bar opens the same shared Flux management UI as the
Omarchy plugin. The desktop daemon is managed by the NixOS user service. Run
`flux-cli doctor` to inspect optional features and pair the phone from the
Flux panel.

The Nix package carries a small Labwc backend patch. Remote desktop uses
`wf-recorder` and `wlr-randr`; pointer input uses Flux's wlroots virtual
pointer, and key input uses `wtype`. The shortcuts view reads the active
Labwc `rc.xml` bindings and the per-output workspace state bridge, then
dispatches configured keys or switches workspaces through Labwc's `.goto`
interface. This keeps the shared upstream UI while replacing its
Hyprland-only compositor calls.
