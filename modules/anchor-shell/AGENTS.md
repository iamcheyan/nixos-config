# Agent handoff guide

This directory is the Quickshell source for the Labwc session (Anchor Shell).
Read this file before changing bar widgets or restarting the shell. Isolation
and paths are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Source and runtime

- Editable source: `/home/tetsuya/nixos-config/modules/anchor-shell/`
- User layout: `/home/tetsuya/.config/anchor-shell/shell.json`
- User plugins: `/home/tetsuya/.config/anchor-shell/plugins/`
- Nix store copy: `/nix/store/...-anchor-shell/`
- Nix wiring: `/home/tetsuya/nixos-config/modules/labwc.nix`
- Compositor checkout: `/home/tetsuya/labwc-plus/`

Do not edit the `/nix/store` copy. Do not edit `modules/desktop.nix` 的系统接线 or `modules/home-manager/hypr/` for a Labwc shell change. Hyprland
keeps its own Omarchy tree.

The live first-party topbar widgets are:

```text
plugins/bar/widgets/ActiveWindow.qml
plugins/bar/widgets/Workspaces.qml
```

## Development mode

```bash
quickshell-mode dev
```

That writes `~/.config/anchor-shell/mode` and restarts the Labwc systemd
service so Quickshell loads this checkout. After a QML edit, run the same
command again. Return to the store copy with `quickshell-mode nix`.

A Nix rebuild is required when changing `labwc.nix`, the launcher, or when
testing a store build. Stage files first (`git add`) and use `--impure`
because `labwc-plus` lives outside the flake.

```bash
cd /home/tetsuya/nixos-config
git add modules/anchor-shell/<changed-file>
sudo nixos-rebuild switch --impure \
  --flake /home/tetsuya/nixos-config#hx90
```

Keep one instance:

```bash
quickshell list --all
quickshell kill --id <instance-id>
```

Do not `pkill`. After a user-plugin change under
`~/.config/anchor-shell/plugins/`:

```bash
quickshell ipc call shell rescanPlugins
```

After a layout-only change to `~/.config/anchor-shell/shell.json`:

```bash
quickshell ipc call shell reloadConfig
```

## Widget contracts

### Workspaces

`Workspaces.qml` reads Labwc state files:

```text
$XDG_RUNTIME_DIR/labwc/workspace-<output-name>
```

The bridge writes the workspace name then the count, for example
`ワークスペース 1 4`. Parse the final numeric fields. Detect `labwc` among
colon-separated `XDG_CURRENT_DESKTOP` names. Scope per-monitor work to
`Window.window.screen`.

### Active window

Titles and app ids come from `Quickshell.Wayland.ToplevelManager`. Icons go
through `shell.appLibrary`. Keep a global-active fallback when a toplevel
has no `screens` list.

## Verification

1. `quickshell list --all` shows one instance.
2. In `dev` mode the config path is this directory's `shell.qml`.
3. Workspace files exist for each output; `Win+1`–`Win+4` move only the
   focused monitor's marker.
4. Focusing windows on each monitor updates that bar's title and icon.

## Change discipline

- First-party widgets stay in this directory.
- User layout stays in `~/.config/anchor-shell/shell.json`.
- Compositor changes stay in `/home/tetsuya/labwc-plus/` only when QML
  cannot obtain the information.
- Do not commit unrelated pre-existing changes in `~/nixos-config`.
