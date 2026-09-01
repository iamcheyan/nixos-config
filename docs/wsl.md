# NixOS on WSL2 (Windows 11)

This repository includes a minimal WSL2 host named `wsl`. It is intended for
Windows 11 + WSL2 + Windows Terminal, without a Linux desktop environment.

## Scope

The WSL host uses the shared `core`, `zsh`, and `cli` modules and intentionally
contains only a command-line baseline:

- Zsh and tmux
- Git, curl, wget, OpenSSH client
- ripgrep, fd, fzf, jq, tree
- unzip/zip
- Neovim

It does not import `dev.nix` or `desktop.nix`. It therefore does not install
compilers, Python/CMake development packages, a display manager, X11/Wayland,
Nixarchy, Fcitx5, Bluetooth, audio, printing, or Firefox. The shared `core`
module does enable the SSH server and allows TCP port 22. Windows Terminal and
WSL provide the terminal and host integration.

## Initial setup

Install a NixOS WSL2 distribution on Windows 11 first. Then open the NixOS WSL
terminal and clone this repository:

```bash
git clone git@github.com:iamcheyan/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

The configured default user is `hkaku`.

## Apply the shared configuration only

This applies the tracked repository configuration and does not load any local
machine-specific module:

```bash
cd ~/nixos-config
nixos-rebuild switch --flake .#wsl
```

## Add private WSL configuration

The repository contains a tracked placeholder at `local/README.md`, while all
other files under `local/` are ignored by Git. Create your private host module:

```bash
cd ~/nixos-config
mkdir -p local/hosts
$EDITOR local/hosts/wsl.nix
```

Example:

```nix
{ config, lib, pkgs, ... }:

{
  # Private WSL-only settings. This file is never committed.
  environment.systemPackages = [ pkgs.htop ];
}
```

## Apply with the private module

Because ignored files are not included in a pure flake source snapshot, pass the
local directory explicitly and enable impure evaluation:

```bash
cd ~/nixos-config
NIXOS_CONFIG_LOCAL="$PWD/local" \
  nixos-rebuild switch --flake .#wsl --impure
```

The flake loads this file only when it exists:

```text
local/hosts/wsl.nix
```

Without `NIXOS_CONFIG_LOCAL` and `--impure`, the tracked configuration still
builds normally, but the local host module is not loaded.

For convenience, define a shell alias:

```bash
alias nixos-wsl='NIXOS_CONFIG_LOCAL="$PWD/local" nixos-rebuild switch --flake .#wsl --impure'
```

## Verify the result

```bash
nixos-rebuild dry-build \
  --flake .#wsl \
  --impure

command -v zsh tmux git nvim tree
```

If no local module is needed, omit `NIXOS_CONFIG_LOCAL` and `--impure`.

## Roll back

NixOS keeps previous generations. If a switch causes a problem, list available
generations and switch back to the previous one:

```bash
sudo nixos-rebuild list-generations
sudo nixos-rebuild switch --rollback
```

The local module remains outside Git, so it can be edited or temporarily renamed
without changing the shared repository configuration.
