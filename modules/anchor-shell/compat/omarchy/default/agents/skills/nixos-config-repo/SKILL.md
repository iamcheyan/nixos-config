---
name: nixos-config-repo
description: Manage Git, remotes, backup and version control of this machine NixOS configuration repository.
---

# 系统配置版本控制

## 本机约束

本机是 NixOS，配置源在 `~/nixos-config`，HX90 日常桌面是 Labwc + Anchor Shell。
Nixarchy 外部依赖已移除；不要调用 `nixarchy apply`、app/pkg 管理器或编辑旧的
`~/.config/nixarchy/*.nix`。系统变更直接编辑本仓库的 Nix 模块。先查看实际 cwd、
仓库 AGENTS.md 和已有更改。跨平台私人配置归 chezmoi，公开通用配置归 dotfiles。
构建本机使用 `nixos-rebuild build --impure --flake ~/nixos-config#hx90`；
用户授权应用后使用 `sudo nixos-rebuild switch --impure --flake ~/nixos-config#hx90`。
保留未提交改动，不编辑 `/nix/store`；不要为修复单个问题更新整个 flake。

读取 repo AGENTS.md 和 `git status`，保留已有更改。本仓库是私有系统层。
新 Nix 源文件需要暂存才能被 flake 读取；不要因此提交无关变更。
仅在用户要求时 commit/push，变更按实际任务分组。公开仓库不能携带机器凭据。
远端配置以 `git remote -v` 为准；不要臆测 GitHub 地址或自动推送。
