# 仓库和上游资料

## 核心仓库

- Nixarchy：<https://github.com/olafkfreund/nixarchy>
- Nixarchy Releases：<https://github.com/olafkfreund/nixarchy/releases>
- Omarchy 上游：<https://github.com/basecamp/omarchy>
- Omarchy Releases：<https://github.com/basecamp/omarchy/releases>
- Home Manager：<https://github.com/nix-community/home-manager>
- NixOS：<https://github.com/NixOS/nixpkgs>
- Hyprland：<https://github.com/hyprwm/Hyprland>

## 本地仓库

- 配置目录：`/home/tetsuya/nixos-config`
- 锁文件：`/home/tetsuya/nixos-config/flake.lock`
- 当前 HX90 主机：`hosts/hx90`（flake 名 `hx90`）
- ARM64 QEMU 主机：`hosts/aarch64`（flake 名 `aarch64`）
- 桌面模块：`modules/desktop.nix`

## 版本关系

`v4.0.1-1` 中的 `4.0.1` 表示打包的 Omarchy 上游版本，`-1` 表示针对该版本的第一个 Nixarchy 打包版本。实际使用的 commit 以 `flake.lock` 为准。
