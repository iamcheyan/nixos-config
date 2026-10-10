# Anchor Shell Bitwarden

Vendored from [Elevate08/qs-bitwarden-cli](https://github.com/Elevate08/qs-bitwarden-cli), upstream v1.11.2, commit `6832e10b2ab923deb54b88995b65502395ee9625` (MIT; see `LICENSE`). This local copy is adapted and managed in `nixos-config` for Anchor Shell / Labwc.

The upstream README is retained as [`UPSTREAM-README.md`](UPSTREAM-README.md), alongside its `CHANGELOG.md`, `SECURITY.md`, and `LICENSE`. Provenance and local changes are recorded in [`UPSTREAM.md`](UPSTREAM.md). The upstream README's Omarchy setup instructions describe the original environment and do not apply here.

This repository's usage and implementation notes are in [`docs/`](docs/):

- [`features.md`](docs/features.md): feature reference
- [`ssh-agent.md`](docs/ssh-agent.md): setup, use, and security model for the optional SSH agent
- [`vault-helper.md`](docs/vault-helper.md): local vault helper
- [`uninstall.md`](docs/uninstall.md): remove plugin state and helpers
- [`development.md`](docs/development.md): local development and verification

The plugin uses the system Bitwarden CLI and stores its state in user data and
configuration directories, never in this repository. When updating the vendored
plugin, retain the upstream README, changelog, security policy, and license;
keep Anchor Shell specific instructions in this README and `docs/`.
