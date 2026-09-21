# Omarchy shell

`omarchy-shell` is a single long-running [Quickshell](https://quickshell.org/)
instance that hosts the Omarchy desktop. Hyprland autostart launches one shell
per graphical session; everything else — the bar, background switcher, panels,
and overlays — runs **inside** the shell as a plugin.

Hosting everything inside one shell means:

- shared services and singletons live once, not once per process
- summoning a panel is an IPC call into a process that is already running,
  not a fresh `quickshell -p ...` cold start
- third-party plugins can be loaded from disk without changing any source
  code in Omarchy itself

## Labwc/NixOS development workflow

On this machine the Quickshell source is maintained in the NixOS repository:

```text
/home/tetsuya/nixos-config/modules/quickshell/
```

The main Labwc bar widgets are:

```text
plugins/bar/widgets/ActiveWindow.qml
plugins/bar/widgets/ActiveWindow.manifest.json
plugins/bar/widgets/Workspaces.qml
plugins/bar/widgets/Workspaces.manifest.json
```

The normal Labwc Nix module copies this directory into a read-only
`/nix/store/...-quickshell-shell/` derivation. For day-to-day QML work, enable
the development source once:

```bash
quickshell-mode dev
```

This makes the Labwc supervisor launch Quickshell directly from
`/home/tetsuya/nixos-config/modules/quickshell/`. After editing a QML file,
run the same command again to restart the running shell without rebuilding.
Return to the immutable Nix build with:

```bash
quickshell-mode nix
```

Check the selected mode with `quickshell-mode status`. The development mode
must be installed by one NixOS switch first, because it adds the selector and
supervisor logic to the Labwc session.

For a release-like test, or after changing the Nix module itself, stage the
changed file and rebuild:

```bash
cd /home/tetsuya/nixos-config
git add modules/quickshell/plugins/bar/widgets/ActiveWindow.qml
git add modules/quickshell/plugins/bar/widgets/Workspaces.qml
sudo nixos-rebuild switch --impure \
  --flake /home/tetsuya/nixos-config#hx90
```

The explicit `git add` matters: flake evaluation only sees tracked or staged
files. The compositor module is intentionally hardcoded to the local
`/home/tetsuya/labwc-plus` checkout on this machine, so `--impure` is required
and there is no upstream fallback version. A normal first-party QML edit does
not require this rebuild while development mode is active.

After rebuilding, start a shell from the new store path. The safest method is
to log out of Labwc and log in again. Check the result with:

```bash
quickshell list --all
```

There should normally be one instance, and its `Config path` should be a new
`/nix/store/...-quickshell-shell/` path. Stop stale test instances cleanly by
their instance ID:

```bash
quickshell kill --id <instance-id>
```

Avoid repeatedly using `pkill` in the Labwc session: an autostart supervisor
may restart the process and leave multiple bars layered over each other,
which can make menus and buttons appear not to accept clicks.

For user plugins under `~/.config/omarchy/plugins/<id>/`, a NixOS rebuild is
not required. Use the running shell's IPC:

```bash
quickshell ipc call shell rescanPlugins
```

For changes to the user layout at `~/.config/quickshell/shell.json`, use:

```bash
quickshell ipc call shell reloadConfig
```

These IPC operations do not replace first-party code already copied into the
store. In `nix` mode, changes under `modules/quickshell/` require a rebuild and
a new shell instance. In `dev` mode, the source is read from the checkout and
only the Quickshell restart is needed.

### Configuration precedence

The repository default layout is:

```text
/home/tetsuya/nixos-config/modules/quickshell/shell.json
```

The active user layout is normally:

```text
/home/tetsuya/.config/quickshell/shell.json
```

Once the user layout exists, it is authoritative rather than deep-merged with
the default. If a widget is missing, check its `bar.layout` entry and the
`disabledPlugins` list in the active user file. Labwc may advertise the desktop
as `labwc:wlroots`; detection code should accept `labwc` as a colon-separated
desktop name.

The runtime layout:

```
shell/
  shell.qml              entry point (ShellRoot)
  services/
    PluginRegistry.qml   discovers, validates plugins, looks up enabled state in shell.json
    BarWidgetRegistry.qml unified registry for bar widgets (1p + 3p)
  plugins/
    bar/                 first-party plugins (see plugins/README.md)
    image-picker/
    menu/
    notifications/
    panels/
      audio/
      bluetooth/
      monitor/
      network/
      power/
      weather/
    agents/
    services/
      battery/
      idle/
    osd/
    polkit/
```

The plugin discovery path is documented in [plugins/README.md](plugins/README.md).

## Plugin manifest

Every plugin ships a `manifest.json` describing what it is and how the
shell should load it. Minimal example:

```json
{
  "schemaVersion": 1,
  "id": "my.org.cool-clock",
  "name": "Cool clock",
  "version": "1.0.0",
  "author": "You",
  "description": "A clock that does cool things",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "Cool clock",
    "category": "Time",
    "allowMultiple": false,
    "defaultSection": "left",
    "defaults": { "format": "HH:mm" },
    "schema": [
      { "key": "format", "type": "string", "label": "Format" }
    ]
  }
}
```

Supported `kinds`:

| Kind         | What it is                                                   |
|--------------|--------------------------------------------------------------|
| `bar-widget` | A component that the active bar can drop into a section      |
| `panel`      | A persistent or summoned floating window (e.g. OSD)          |
| `overlay`    | A fullscreen overlay (e.g. background switcher)              |
| `menu`       | A summoned menu surface                                      |
| `service`    | A headless singleton, no UI                                  |
| `bar`        | A full bar option that can replace the built-in `omarchy.bar` |

Only one `bar` plugin is active at a time. Missing or invalid selections fall
back to the built-in `omarchy.bar`, so users always have a safe path home.
Panels, overlays, and menus are loaded when summoned. Plugins that need
to outlive a single summon can set `keepLoaded: true` (e.g. the image
picker keeps its overlay window mounted between summons). First-party
services are loaded at startup.

The full schema lives in `services/PluginRegistry.qml`.

## Installing a third-party plugin

A plugin is a **git repo** with a `manifest.json` at its root. Adding one
clones it straight into `~/.config/omarchy/plugins/<id>/` (named by the
manifest id); updating is a fast-forward pull of that checkout.

```bash
omarchy plugin add https://github.com/acme/omarchy-weather.git
omarchy plugin update acme.weather       # fetches, shows a diff, fast-forwards
omarchy plugin update                    # updates every git-managed plugin
omarchy plugin remove acme.weather
```

> ⚠️ **Plugins run as unsandboxed code inside `omarchy-shell`.** Adding warns
> you before cloning, plugins land disabled so you can review the code before
> enabling, and updates show a diff of the changes before touching anything.
> Only add repos whose code you are willing to run.

Each command is **interactive** when run bare in a terminal (gum pickers,
confirmation, a diff to review) and fully **non-interactive** when given
arguments. Pass `--yes` to skip every prompt — this is the path for scripts and
AI agents:

```bash
omarchy plugin add https://github.com/acme/omarchy-weather.git --enable --yes
omarchy plugin update --yes
```

The installer never runs plugin code, install hooks, or sudo — it only clones
files, validates the manifest, and toggles enabled state over shell IPC. Since
an installed plugin is a plain git checkout, anything beyond add/update
(pinning a ref, switching branches) is ordinary git in the plugin directory.

### Installing by hand

You can still drop a plugin in without git:

1. Put it in `~/.config/omarchy/plugins/<plugin-id>/` with a `manifest.json`
   plus the QML referenced from its `entryPoints`.
2. `omarchy-shell shell rescanPlugins`.
3. `omarchy plugin enable <id>`. Bar widgets start in
   `barWidget.defaultSection`, or in the center when it is omitted, and can be
   moved with `omarchy bar move`; a full bar replaces the one in use.

The lower-level IPC equivalents remain available via `omarchy-shell shell rescanPlugins`,
`omarchy-shell shell enablePlugin <id> '{}'`, and `omarchy-shell shell listPlugins`.
The `omarchy plugin` commands wrap those calls. `omarchy bar move` and
`omarchy bar set` edit the persisted widget layout in `shell.json`.

To hack on a built-in plugin safely, clone it into user config instead of
editing the built-in source. The complete plugin directory is copied, including
every declared kind and local dependency. A built-in id such as
`omarchy.clock` becomes `<username>.clock` (e.g. `dhh.clock`), with `My Clock`
as its display name. The username prefix keeps shared clones from colliding
with each other or with other plugin authors.

```bash
omarchy plugin clone omarchy.clock
```

Cloning switches from the built-in to the new personal plugin, preserving an
existing bar widget's position and settings. Setup > Plugins > Clone provides
the interactive picker, then opens the new `<username>.*` directory in `$EDITOR`.
Existing shortcuts and shell IPC calls made to the built-in id are routed to
the enabled clone, so cloning does not require changing its callers. Removing
an active clone switches back to its built-in source.
Saving a file anywhere under `~/.config/omarchy/plugins/` reloads plugin code
automatically; `omarchy-shell shell rescanPlugins` remains available to force a reload.

First-party plugins under `shell/plugins/` are discovered the same way and load
by default. Disabling a non-widget records it in `disabledPlugins[]`; disabling
a widget removes it from the bar layout while leaving its component available
to add again. A full bar has no off state and is replaced by enabling another.

## IPC contract

The shell exposes a single `shell` IPC target plus whatever extra targets
individual plugins register (e.g. the bar's `bar` target for refresh
hooks, the image picker's `image-selector` target). `omarchy-menu` uses the
shell target to summon the first-party `omarchy.menu` plugin instead of
running a separate Quickshell instance.

| Method                                   | Returns | Effect                                                |
|------------------------------------------|---------|-------------------------------------------------------|
| `ping`                                   | `ok`    | health check                                          |
| `summon <id> <payloadJson>`              | `ok` / `unknown` | load + open a panel/overlay plugin           |
| `hide <id>`                              | —       | close a previously-summoned plugin                    |
| `toggle <id> <payloadJson>`              | —       | summon if closed, hide if open                        |
| `call <id> <method> <arg>`               | string  | call a method on an already-loaded plugin             |
| `rescanPlugins`                          | —       | re-walk plugin dirs and hot-reload plugin code        |
| `reloadConfig`                           | `ok`    | reload `~/.config/omarchy/shell.json`                 |
| `setPluginEnabled <id> <enabled>`        | `ok` / `unknown` | flip the persisted enabled bit (see note)    |
| `listPlugins`                            | JSON    | every discovered plugin, sorted by name               |

Direct invocation:

```
quickshell ipc -p $NIXARCHY_ROOT/shell call shell ping
```

Hyprland autostart launches the shell directly with `quickshell -p
$NIXARCHY_ROOT/shell`. Use `omarchy-restart-shell` to stop every running
instance of that config and launch one fresh shell process.

A convenience wrapper, [`omarchy-shell`](../bin/omarchy-shell), forwards IPC
calls to the running shell. It does not start the shell.

```
omarchy-shell shell ping
omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'
omarchy-shell shell listPlugins
omarchy-shell shell rescanPlugins
```

**Note on `setPluginEnabled`:** the `enabled` argument is a string. Only the
literal `"true"` enables the plugin; every other value (including `"True"`,
`"1"`, `"yes"`, or omitted) disables it. This keeps the IPC surface
type-stable across QML's `string`-only IPC arguments.

## Persisted state

There is one user config file. Everything that distinguishes your
customization from the shipped defaults lives in it.

| Path                              | Owner          | Purpose                                                |
|-----------------------------------|----------------|--------------------------------------------------------|
| `~/.config/omarchy/shell.json`    | the shell      | full layout + per-entry settings + enabled plugin list |
| `~/.config/omarchy/plugins/<id>/` | user           | drop-in third-party plugin source files                |

The `config/omarchy/shell.json` default config describes the
fresh-install state. When the user has no `shell.json`, the shell uses
the defaults verbatim. Once the user customizes anything, `shell.json`
becomes the authoritative file — we do **not** deep-merge defaults back in.

### shell.json shape

```json
{
  "version": 1,
  "idle": {
    "screensaver": 150,
    "lock": 300
  },
  "bar": {
    "id": "omarchy.bar",
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left":   [ { "id": "omarchy.menu" }, { "id": "omarchy.workspaces" } ],
      "center": [ { "id": "omarchy.clock", "format": "HH:mm" } ],
      "right": [
        { "id": "omarchy.audio" }
      ]
    }
  },
  "plugins": []
}
```

### Storage rules

1. **The active bar option is `bar.id`.** Omit it or set it to `omarchy.bar`
   to use the built-in bar. Set it to another plugin id whose manifest declares
   `kind: "bar"` to replace the full bar.
2. **Every plugin instance is one entry.** Either in `bar.layout.<section>`
   for bar widgets, or in `plugins[]` for panels, overlays, services,
   menus, and anything else non-bar.
3. **Settings are inline on the entry.** No `config:` sub-object, no
   separate per-plugin settings file, no merge layers. The fields on each
   entry are the values the plugin sees.
4. **Built-in widget ids are namespaced.** Use ids such as `omarchy.clock`,
   `omarchy.audio`, and `omarchy.network`. The migration rewrites older ids
   like `Clock` and `AudioPanel` forward.
5. **Third-party enabled ⇔ present.** A third-party plugin is enabled iff
   its id appears somewhere in shell.json. For full bar options, that means
   `bar.id`; for bar widgets, plugin enable/disable adds/removes layout entries;
   other plugin kinds are enabled the same way. First-party non-bar plugins
   are enabled unless listed in `disabledPlugins[]`.
6. **Multiple instances** are allowed when a manifest sets
   `allowMultiple: true`. Each instance is independent — e.g. two clock
   widgets in different timezones are just two `{"id":"omarchy.clock", "timezone": ...}`
   entries with their own values.
7. **Idle timings are top-level.** `idle.screensaver` and `idle.lock`
   are seconds since user idle began, so the default lock fires at 300s
   even if the 150s screensaver starts first.
8. **`version: 1` is required** at the top level. The shell will fall back
   to defaults rather than load an unknown version.

## Implementation history

Built up in phases on this branch:

- Phase 1 — `omarchy-shell phase 1: host the existing bar in a single shell`
- Phase 2 — `omarchy-shell phase 2: plugin registry and bar widget registry`
- Phase 3 — `omarchy-shell phase 3: fold bar-settings into the shell as a panel plugin`
- Phase 4 — `omarchy-shell phase 4: absorb background-switcher as a plugin`
- Phase 5 — `omarchy-shell phase 5: docs, cleanup, and migration crumbs`
- Phase 6 — `omarchy-shell phase 6: reviewer cleanup (path traversal, collision, races)`
- Phase 7 — `omarchy-shell phase 7: replace socket with IpcHandler, rename to image-picker`
- Phase 8a — `omarchy-shell phase 8a: unified shell.json with inline plugin settings`

Shared services and Pipewire/UPower/Hyprland consolidation are explicitly
out of scope here and deferred to a follow-up after a review pass.
