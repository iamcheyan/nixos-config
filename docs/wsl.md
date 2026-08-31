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

The first evaluation will fetch and lock the `nixos-wsl` input. Keep the resulting
`flake.lock` update if it is generated on the target WSL machine.

The configured default user is `tetsuya`.
