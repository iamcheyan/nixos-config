---
name: devenv
description: Set up or fix per-project development environments, devenv.nix and automatic shell activation on this NixOS machine.
---

# 项目开发环境

## 本机约束

本机是 NixOS，配置源在 `~/nixos-config`，HX90 日常桌面是 Labwc + Anchor Shell。
Nixarchy 外部依赖已移除；不要调用 `nixarchy apply`、app/pkg 管理器或编辑旧的
`~/.config/nixarchy/*.nix`。系统变更直接编辑本仓库的 Nix 模块。先查看实际 cwd、
仓库 AGENTS.md 和已有更改。跨平台私人配置归 chezmoi，公开通用配置归 dotfiles。
构建本机使用 `nixos-rebuild build --impure --flake ~/nixos-config#hx90`；
用户授权应用后使用 `sudo nixos-rebuild switch --impure --flake ~/nixos-config#hx90`。
保留未提交改动，不编辑 `/nix/store`；不要为修复单个问题更新整个 flake。

项目工具链写入项目自己的 `devenv.nix` / `devenv.yaml` / `devenv.lock`，机器级工具
才进入 NixOS 配置。本机 `modules/devenv.nix` 声明 devenv 包及 bash/zsh/fish hooks。

在项目中先阅读现有文件。新项目可用 `devenv-init <preset>`（`devenv-init --list` 查看预设）或 `devenv init`，然后配置 `languages.<语言>.enable`
与 packages；用当前 `devenv --help` 确认版本支持的参数。只对可信项目执行 `devenv allow`。
进入目录未激活时检查 shell hook 和信任状态，`devenv shell` 可显式进入。
不把项目编译器版本塞进全局 mise 或系统包来绕过项目环境。
