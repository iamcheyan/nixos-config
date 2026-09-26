# Omarchy-compatible runtime

This directory is the first migration batch for the Quickshell desktop. It
contains the runtime closure currently consumed by the shell and its plugins:

- `bin/` keeps the historical `omarchy-*` command names;
- `shell/plugins/` keeps the helper scripts imported through `OMARCHY_PATH`;
- `default/omarchy/` and `config/omarchy/` keep compatibility defaults and
  state/configuration paths used by first-party widgets;
- `applications/` keeps desktop entries needed by the launcher compatibility
  path.

The files are intentionally kept under their original names and layout. This
batch does not remove or change the existing Nixarchy/Omarchy runtime. Later
batches will make the Labwc module select this copy first, retain the current
store path as a fallback, and verify the active bar before any external
dependency is removed.

Source snapshot: Omarchy 4.0.2, copied from the active Nix store generation.
