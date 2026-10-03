# Upstream provenance

- Repository: https://github.com/Elevate08/qs-bitwarden-cli
- Commit: `6832e10b2ab923deb54b88995b65502395ee9625`
- Version: 1.11.2
- License: MIT (`LICENSE`)

Local changes adapt the plugin id, runtime IPC, and desktop integration to Anchor Shell / Labwc. The plugin invokes the standard `bw` Bitwarden CLI; this host has `bw` installed from the NixOS configuration. There is no separate `bwc` command or wrapper in this environment. Keep this file and the upstream license when updating or redistributing.
