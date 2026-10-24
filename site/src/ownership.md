# 配置归属：一份文件只由一个系统管理

这台环境把系统层、私人用户层和公开通用配置分开放。这样既能在每个发行版重复使用通用配置，也能避免 Home Manager、chezmoi 和 dotlink 同时写同一路径。

## 三层职责

| 仓库 | 内容 | 生效方式 | 不放什么 |
|---|---|---|---|
| `nixos-config` | OS、硬件/主机选项、system packages、系统服务、NixOS/Darwin Home Manager | `nixos-rebuild` / nix-darwin | 可跨发行版共享的私人凭据和随手改的生成文件 |
| `chezmoi`（私人） | 用户偏好、密钥的 age 加密版本、私人 Agent / 终端编排 | `chezmoi apply` | 系统驱动、root 服务、通用公开工具 |
| `dotfiles`（公开） | 可复用 shell/editor/CLI 配置与 dotlink 规则 | `dotlink` 等用户层安装流程 | 私人路径、网络地址、密钥和 host Nix 模块 |

## 判断一个文件该放哪里

1. 它是否要写 `/etc`、安装系统包、控制用户组/驱动、定义系统 systemd service？放 NixOS/Darwin 系统模块。
2. 它是否只为某个用户使用且依赖密钥、个人路径或私有 Agent 偏好？放 chezmoi。
3. 它是否不依赖个人信息，能给其他用户复用？放公开 dotfiles。
4. 它是否只在 NixOS 上使用、依赖 Nix store 路径或必须跟系统 generation 一起回滚？放 NixOS Home Manager。

“用户级”不等于一定在 chezmoi。关键是配置是否依赖 NixOS、是否需要与系统 generation 原子激活，以及它是否属于私人偏好。

## Home Manager 文件接管

Home Manager activation 会管理目标 home 文件。把一个目标从 chezmoi 移入 Home Manager 时，应在同一次迁移中停止 chezmoi 管理它；反向迁移也一样。否则会出现每次 apply 相互覆盖、备份反复生成、登录后状态取决于执行顺序等问题。

NixOS 版本的用户入口是 [`modules/home-manager/nixos-user.nix`](../modules/home-manager/nixos-user.nix)，Darwin 使用独立的 [`darwin-user.nix`](../modules/home-manager/darwin-user.nix)。先从主机 imports 确认入口是否生效，再追踪具体子模块。

## 本地扩展边界

忽略的 `local/` 用于本机私有模块。`flake.nix` 通过 `NIXOS_CONFIG_LOCAL` 显式找到它，因此需加 `--impure`。文件不在公共 flake 输入中，任何可公开构建的模块都不能要求其他机器必须拥有本地文件。个人机密和路径不要复制到网页的公开构建产物。

## 延伸阅读

- [仓库说明与主机地图](../README.md)
- [系统架构](architecture.md)
- [NixOS 专属 Home Manager 用户层](../modules/home-manager/nixos-user.nix)
- [Darwin Home Manager 用户层](../modules/home-manager/darwin-user.nix)
- [Agent 环境配置](../docs/agent-environment.md)
- [macOS 迁移中的配置边界](../docs/macos-nix-darwin/04-ownership-and-boundaries.md)
