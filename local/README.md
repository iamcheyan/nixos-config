# Local host extensions

This directory is intentionally local-only. It is not a shared configuration
layer and its contents are ignored by Git, except for this placeholder.

Add optional per-host Nix modules under `local/hosts/`:

```text
local/hosts/wsl.nix
local/hosts/aarch64.nix
local/hosts/hx90.nix
```

The matching host loads its file automatically when it exists. If the file is
absent, the host builds with the repository configuration only.

Example for the WSL host:

```nix
{ config, lib, pkgs, ... }:

{
  # Local-only packages, proxies, mounts, or other settings.
  # This file is not committed or shared.
  environment.systemPackages = [ pkgs.htop ];
}
```

Do not put shared configuration here. Put reusable modules in `modules/` and
host-independent CLI/development settings in `modules/cli.nix` or
`modules/dev.nix`.
