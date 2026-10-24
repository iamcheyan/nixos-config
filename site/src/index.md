# NixOS 配置学习手册

这个仓库既是正在使用的系统配置，也是理解多设备 NixOS/Darwin 配置的实例。学习手册不只介绍单个 Nix 语法，而是沿真实配置追踪：**flake 输入 → 主机输出 → 模块组合 → 系统 generation → 日常恢复**。

## 入门路线

1. [先学 NixOS 的核心模型](https://nixos.org/manual/nixos/stable/)并阅读[本仓库学习笔记](../docs/nixos-learning-notes.md)：声明式配置、惰性求值、不可变 store、flake.lock、generation。
2. 阅读[仓库说明](../README.md)与[配置架构地图](architecture.md)：确定有哪些系统、每台主机从哪里进入 flake。
3. 选一台机器追踪：[`hx90`](../hosts/hx90/configuration.nix)、[`aarch64`](../hosts/aarch64/configuration.nix)、[`wsl`](../hosts/wsl/configuration.nix)，或 [Darwin Mac](../hosts/macbook-m1-max/configuration.nix)。
4. 查看它导入的共享模块；从[模块学习索引](index.md#共享模块地图)或[桌面架构](desktop.md)开始。
5. 练习安全构建与恢复：参阅[更新和排错](troubleshooting.md)及[更新快照手册](../docs/nixos-update-snapshots.md)。

## 网站内容

网站是这份 README、手写学习页面与仓库原有 Markdown 文档的统一阅读入口。支持站内搜索、原始源码跳转和按主题浏览；`docs/`、`modules/` 下符合发布范围的文档会生成对应页面。

该网站只为本仓库提供结构化导航与教学脉络，不是自动机密扫描或脱敏工具。硬件文件、主机运行日志、Git 忽略的 `local/` 配置、`AGENTS.md` 和 vendored/upstream 文档不会进入站点 artifact。新增文档若含机器私密细节，应先审查 GitHub 仓库的公开可见性。

## 主机索引

| flake 输出 | 平台 / 架构 | 角色 | 配置入口 |
|---|---|---|---|
| `hx90` | NixOS · `x86_64-linux` | HX90 工作站；Labwc + Anchor Shell，另保留备用会话 | [configuration.nix ↗](https://github.com/iamcheyan/nixos-config/blob/main/hosts/hx90/configuration.nix) |
| `aarch64` | NixOS · `aarch64-linux` | ARM64 QEMU 虚拟机，使用 GNOME/SPICE | [configuration.nix ↗](https://github.com/iamcheyan/nixos-config/blob/main/hosts/aarch64/configuration.nix) |
| `wsl` | NixOS-WSL · `x86_64-linux` | Windows 11 轻量终端环境，不导入桌面模块 | [configuration.nix ↗](https://github.com/iamcheyan/nixos-config/blob/main/hosts/wsl/configuration.nix) |
| `macbook-m1-max` | macOS · `aarch64-darwin` | Apple Silicon，使用独立 nix-darwin 输出 | [configuration.nix ↗](https://github.com/iamcheyan/nixos-config/blob/main/hosts/macbook-m1-max/configuration.nix) |

主机的实际模块关系以当前源码为准。硬件生成文件含设备标识，不在网站公开。

## 共享模块地图

- [core.nix — 系统基础选项](https://github.com/iamcheyan/nixos-config/blob/main/modules/core.nix)
- [cli.nix — 命令行工具](https://github.com/iamcheyan/nixos-config/blob/main/modules/cli.nix)
- [dev.nix — 编译器与开发环境](https://github.com/iamcheyan/nixos-config/blob/main/modules/dev.nix)
- [workstation.nix — 图形工作站基础](https://github.com/iamcheyan/nixos-config/blob/main/modules/workstation.nix)
- [desktop.nix — 登录、音频、字体及桌面](https://github.com/iamcheyan/nixos-config/blob/main/modules/desktop.nix)
- [labwc.nix — Labwc 和 Anchor Shell 接线](https://github.com/iamcheyan/nixos-config/blob/main/modules/labwc.nix)
- [NixOS Home Manager 用户入口](https://github.com/iamcheyan/nixos-config/blob/main/modules/home-manager/nixos-user.nix)
- [Darwin 模块目录](https://github.com/iamcheyan/nixos-config/tree/main/modules/darwin)

## 网站文档范围

站点下方目录提供 `docs/` 和 `modules/` 的主题入口、检索与原文跳转。项目级 README 先折叠展示，读完本页摘要后可展开完整原文。

## 与 NixOS 官方资料的关系

官方资料负责解释通用 NixOS 选项、安装、模块系统和 systemd 行为：

- [NixOS 手册](https://nixos.org/manual/nixos/stable/)
- [Nix 手册](https://nix.dev/manual/nix/2.28/)
- [Nixpkgs 手册](https://nixos.org/manual/nixpkgs/stable/)
- [NixOS 选项搜索](https://search.nixos.org/options)

本项目手册解释这些概念如何体现在本仓库；真实生效值仍须以当前 flake 求值、构建结果和目标机器为准。
