# NixOS on WSL2 (Windows 11)

This repository includes a minimal WSL2 host named `wsl`.

## Scope

The WSL host intentionally contains only:

- Zsh and tmux
- Git, curl, wget, OpenSSH
- ripgrep, fd, fzf, jq
- unzip/zip
- Neovim
- Python 3
- GCC, Make, and CMake

It does not import the desktop, Nixarchy, Fcitx5, Bluetooth, audio, printing,
Firefox, display-manager, or system SSH modules used by the physical/QEMU hosts.
Windows Terminal and WSL provide the terminal and host integration.

## Build from Windows 11 WSL2

After installing a NixOS WSL2 distribution, clone this repository inside WSL:

```bash
git clone git@github.com:iamcheyan/nixos-config.git ~/nixos-config
cd ~/nixos-config
nixos-rebuild switch --flake .#wsl
```

To load the ignored local host extension, pass the working-tree local directory
explicitly and enable impure evaluation:

```bash
NIXOS_CONFIG_LOCAL="$PWD/local" nixos-rebuild switch --flake .#wsl --impure
```

The repository configuration does not require a local extension; without
`NIXOS_CONFIG_LOCAL`, `local/hosts/wsl.nix` is not loaded.

The configured default user is `hkaku`.

Host-specific local modules are optional and ignored by Git. After cloning, create
`local/hosts/wsl.nix` if this WSL instance needs private settings.
