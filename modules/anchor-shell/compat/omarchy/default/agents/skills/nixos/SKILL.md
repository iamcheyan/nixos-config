---
name: nixos
description: Install, remove or configure system software, services, hardware or NixOS generations on this machine.
---

# 本机 NixOS 配置

## 本机约束

本机是 NixOS，配置源在 `~/nixos-config`，HX90 日常桌面是 Labwc + Anchor Shell。
Nixarchy 外部依赖已移除；不要调用 `nixarchy apply`、app/pkg 管理器或编辑旧的
`~/.config/nixarchy/*.nix`。系统变更直接编辑本仓库的 Nix 模块。先查看实际 cwd、
仓库 AGENTS.md 和已有更改。跨平台私人配置归 chezmoi，公开通用配置归 dotfiles。
构建本机使用 `nixos-rebuild build --impure --flake ~/nixos-config#hx90`；
用户授权应用后使用 `sudo nixos-rebuild switch --impure --flake ~/nixos-config#hx90`。
保留未提交改动，不编辑 `/nix/store`；不要为修复单个问题更新整个 flake。

## 配置归属

- 系统共享桌面运行环境：`modules/desktop-runtime.nix`，集成：`modules/desktop.nix`。
- Labwc / Anchor Shell：`modules/labwc.nix`、`modules/anchor-shell/`。
- 主机专属配置：`hosts/hx90/configuration.nix`；QQ/微信覆盖：`hosts/hx90/apps.nix`。
- 用户级 Nix 集成及 Agent 全局文档/skills：`modules/home-manager/nixos-user.nix`。
- 临时尝试可用 `nix shell nixpkgs#<包>`，持久安装声明 `environment.systemPackages`。
- 服务使用真实 NixOS options；先在锁定的 nixpkgs 源码或官方文档确认。
- 新文件先 `git add`，否则 Git flake 看不到；展示 diff，再构建和应用。
- 保留 `system.stateVersion`。不要运行垃圾回收或删除回滚 generations。
- 更新入口 `nixos-update` 保留 root/home 快照、构建后切换和历史。

专项工作读取相应 nixos-services、nixos-gpu、nixos-secrets 等 skill。
项目语言工具链读取 devenv skill。
