# 配置架构地图

## 一次系统构建如何发生

```text
flake.lock ──固定来源──▶ flake.nix ──导出主机名──▶ hosts/<主机>/configuration.nix
                                                    │
                                      主机硬件与平台差异
                                                    │ imports
                     ┌──────────────────────────────┼────────────────┐
                     ▼                              ▼                ▼
                core / cli / dev              workstation       Darwin modules
                     │                         │       │
                     └──────────▶ desktop / labwc / Home Manager     │
                                                               nix-darwin
```

Nix 先根据输入源码求值模块并合并 options，再构建不可变的 store 闭包。`nixos-rebuild build` 验证并构建候选；`switch` 才把候选设为当前系统。flake 名称来自 flake 输出，不一定和 `networking.hostName` 相同，例如 WSL 输出叫 `wsl`、系统 hostname 是 `nixos-wsl`。

## 每层负责什么

| 层 | 目录 | 用途 |
|---|---|---|
| 输入版本 | `flake.nix`、`flake.lock` | 软件源、模块来源和精确锁定版本 |
| 平台入口 | `flake.nix` outputs | 将 NixOS 主机与 Darwin 主机分别导出 |
| 主机入口 | `hosts/*/configuration.nix` | hostname、硬件引用、机器独有服务和模块组合 |
| 共享系统模块 | `modules/core.nix`、`cli.nix`、`dev.nix` | 可复用系统选项，按主机需求选择导入 |
| 图形工作站 | `modules/workstation.nix`、`desktop.nix` | 图形登录、系统桌面包与共同策略 |
| 桌面实现 | `modules/labwc.nix`、`modules/anchor-shell/` | compositor、shell、QML 组件、插件和运行时接口 |
| 用户级系统配置 | `modules/home-manager/` | 随系统 generation 管理的用户文件及 user services |
| 本地扩展 | 被忽略的 `local/` | 不提交的主机特定设置，通过 impure 环境变量引入 |

## 四个 flake 输出

### `hx90`：工作站

入口 [`hosts/hx90/configuration.nix`](../hosts/hx90/configuration.nix) 继承共享系统配置和本机硬件差异，再加入 Tailscale、Syncthing、Docker 等机器服务。它主要使用 Labwc 与 Anchor Shell，保留 Hyprland 和 Plasma 等会话。工作站具体程序列表另在 [`hosts/hx90/apps.nix`](../hosts/hx90/apps.nix)。该主机的 TTM/kernel 问题和设备运行记录不发布在此站。

### `aarch64`：ARM64 虚拟机

入口 [`hosts/aarch64/configuration.nix`](../hosts/aarch64/configuration.nix) 指定 `aarch64-linux`，并配置 QEMU/SPICE 来宾支持。它与 x86_64 工作站共享适用的系统模块，但不会继承 AMD GPU、电源管理等特定硬件处理。

### `wsl`：WSL2

入口 [`hosts/wsl/configuration.nix`](../hosts/wsl/configuration.nix) 通过 NixOS-WSL 模块接入 Windows。它刻意不导入图形桌面、蓝牙、音频和打印栈。因为开发者会话可使用 Git 忽略的本地模块，构建命令需启用 impure 求值。操作说明：[WSL 指南](../docs/wsl.md)。

### `macbook-m1-max`：macOS

Darwin 输出位于 `flake.nix` 的 `darwinConfigurations`，不属于 `nixosConfigurations`。Apple Silicon 使用 `aarch64-darwin`、nix-darwin 与独立的 [`darwin-user.nix`](../modules/home-manager/darwin-user.nix)。Linux 的 systemd、内核和设备模块不能直接复制到这里。完整学习手册：[macOS Nix / nix-darwin](../docs/macos-nix-darwin/README.md)。

## 读配置时追踪 imports

1. 从 `flake.nix` 找目标输出和平台系统。
2. 打开对应主机的 `configuration.nix`，查看 imports、hostname、机器专属服务与 stateVersion。
3. 逐个打开导入的共享模块；确认它确实进入目标 host 的 imports 链。
4. `home-manager.users.*` 是用户环境；systemd system services 和 `environment.systemPackages` 属于系统环境。
5. 某些选项有默认值或多处定义，查看最终合并结果，不要仅按文件名推断生效行为。

## `localRoot` 例外路径

`flake.nix` 读取 `NIXOS_CONFIG_LOCAL` 并把值传入 `specialArgs`。主机模块只在目标本地文件存在时追加它。flake 的纯快照无法看到 Git 忽略文件，所以这条路径必须显式使用 `--impure`。在启用前先阅读 [`本地扩展说明`](../local/README.md)；不要把私人配置复制到公共模块。

## 配置归属判断

- 系统 package、驱动、systemd system service、用户组：本仓库。
- 与 NixOS 软件闭包/路径绑定的用户级 Home Manager 文件：NixOS Home Manager 层。
- 跨发行版且属个人的配置与私有凭据：`chezmoi`。
- 可公开复用的通用工具/配置：`dotfiles`。
- 不清楚归属时，先读 [配置边界说明](ownership.md)，避免两个配置管理器竞争写同一个文件。
