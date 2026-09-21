# Agent handoff guide

This directory contains the Quickshell source used by the Labwc session on
this machine. Read this file before changing bar widgets or restarting the
shell.

## Source and runtime boundaries

- Editable source: `/home/tetsuya/nixos-config/modules/quickshell/`
- User layout: `/home/tetsuya/.config/quickshell/shell.json`
- Generated runtime copy: `/nix/store/...-quickshell-shell/`
- Nix wiring: `/home/tetsuya/nixos-config/modules/labwc.nix`
- Labwc source checkout: `/home/tetsuya/labwc-plus/`

Do not edit the generated `/nix/store` copy. It is read-only and will be
replaced by the next rebuild. Do not modify Labwc merely to solve a bar-widget
problem; first check whether the behavior can be implemented in QML.

The active first-party widgets for the current topbar are:

```text
plugins/bar/widgets/ActiveWindow.qml
plugins/bar/widgets/Workspaces.qml
```

The old external active-window plugin is separate and is not the source for the
current `omarchy.active-window` widget:

```text
/home/tetsuya/.config/omarchy/plugins/iamcheyan.active-window/
```

## Build and apply changes

For a first-party source change:

```bash
cd /home/tetsuya/nixos-config
git add modules/quickshell/<changed-file>
sudo nixos-rebuild switch --impure \
  --flake /home/tetsuya/nixos-config#hx90
```

The `git add` is required before a flake rebuild because untracked files are
not included in the flake source. During normal development, use the direct
checkout mode instead:

```bash
quickshell-mode dev
```

After editing QML, run the same command again to restart the shell. Use
`quickshell-mode nix` to return to the immutable Nix build. A Nix rebuild is
still required when changing the Nix module, the launcher, or when testing a
release-like store build. The compositor module is permanently
configured to use the local `/home/tetsuya/labwc-plus` checkout on this
machine. There is no upstream fallback package; `--impure` is required because
that checkout is outside this flake.

After the rebuild, the running shell still has the old store path until it is
restarted. Check instances with:

```bash
quickshell list --all
```

Keep one instance only. Stop stale instances using their IDs:

```bash
quickshell kill --id <instance-id>
```

Then start the shell using the session's current `QUICKSHELL_ROOT`, or log out
and back in. Avoid repeated `pkill` calls: Labwc's autostart supervisor can
immediately respawn the old shell and create overlapping bars.

For a user plugin under `~/.config/omarchy/plugins/`, use:

```bash
quickshell ipc call shell rescanPlugins
```

For only the user layout, use:

```bash
quickshell ipc call shell reloadConfig
```

Neither command replaces first-party source already copied into `/nix/store`.

## Current widget contracts

### Workspaces

`Workspaces.qml` uses the Labwc state files written under:

```text
$XDG_RUNTIME_DIR/labwc/workspace-<output-name>
```

The current bridge writes the workspace name followed by the workspace count,
for example:

```text
ワークスペース 1 4
```

The parser must therefore not assume the first whitespace-separated field is a
number. It should read the final numeric fields. Labwc sessions can expose
`XDG_CURRENT_DESKTOP=labwc:wlroots`; detect `labwc` among colon-separated
desktop names rather than requiring an exact string match.

The widget is instantiated once per bar surface/monitor. Use
`Window.window.screen` when an operation must be scoped to that monitor.

### Active window

`ActiveWindow.qml` obtains titles and application IDs from
`Quickshell.Wayland.ToplevelManager`. Application icons are resolved through
the existing `shell.appLibrary`, which matches desktop entries and the icon
index used by the launcher.

The Wayland foreign-toplevel API may omit per-window screen information on
some wlroots compositors. Keep a fallback for the global active toplevel so a
missing `screens` list does not hide the widget completely. Do not assume that
the compositor exposes a generic workspace property; Quickshell's Wayland
`Toplevel` API provides visible screens, not a universal workspace ID.

## Verification checklist

After changing workspace or active-window behavior:

1. Confirm `quickshell list --all` reports one instance using the new store path.
2. Confirm both output state files exist and contain the expected workspace
   name and count.
3. Switch workspaces on each monitor separately with `Win+1` through `Win+4`.
4. Verify the square active marker moves on only the focused monitor's bar.
5. Open or focus windows on both monitors and verify each bar's title and icon.
6. Capture a screenshot if visual behavior is disputed; do not infer a working
   UI solely from the state file.

If the state file changes but the bar does not, inspect the loaded store copy
and restart Quickshell before changing Labwc. If multiple shell instances are
listed, remove the stale ones first.

## Change discipline

- Keep first-party widget changes in this directory.
- Keep user layout changes in `~/.config/quickshell/shell.json`.
- Keep compositor changes in `/home/tetsuya/labwc-plus/` only when QML cannot
  obtain the required information.
- Document any unavoidable Labwc change and keep it in a separate commit from
  the local Quickshell integration.
- Do not commit unrelated pre-existing changes in
  `/home/tetsuya/nixos-config`.
