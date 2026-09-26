---
name: nixarchy
description: Customize the locally managed Labwc / Anchor Shell desktop or retained Hyprland compatibility session; this legacy skill name does not imply a Nixarchy dependency.
---

# 本地桌面（历史 skill 名 nixarchy）

## 本机约束

本机是 NixOS，配置源在 `~/nixos-config`，HX90 日常桌面是 Labwc + Anchor Shell。
Nixarchy 外部依赖已移除；不要调用 `nixarchy apply`、app/pkg 管理器或编辑旧的
`~/.config/nixarchy/*.nix`。系统变更直接编辑本仓库的 Nix 模块。先查看实际 cwd、
仓库 AGENTS.md 和已有更改。跨平台私人配置归 chezmoi，公开通用配置归 dotfiles。
构建本机使用 `nixos-rebuild build --impure --flake ~/nixos-config#hx90`；
用户授权应用后使用 `sudo nixos-rebuild switch --impure --flake ~/nixos-config#hx90`。
保留未提交改动，不编辑 `/nix/store`；不要为修复单个问题更新整个 flake。

日常会话是 Labwc。先检查进程和桌面环境变量，确认目标会话。
修改 Anchor Shell 前阅读 `~/nixos-config/modules/anchor-shell/AGENTS.md` 与 ARCHITECTURE.md。
源目录 `modules/anchor-shell/`，用户布局 `~/.config/anchor-shell/shell.json`，用户插件
`~/.config/anchor-shell/plugins/`。用 `quickshell-mode dev` / `quickshell-mode nix` 切换。
保留一个 shell 实例，不使用 pkill；重载方式以该目录 AGENTS.md 为准。

私人桌面/终端偏好编辑 chezmoi 源后部署；系统集成编辑本仓库。
备用 Hyprland 使用独立锁定的上游输入和本地 Omarchy 兼容资源。
历史 `omarchy-*` 命令是本仓库保留的兼容接口。不要用 Arch/pacman 安装路径。
