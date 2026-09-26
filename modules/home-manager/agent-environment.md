# 本机 Agent 环境

## 当前环境

默认工作环境是这台运行 **NixOS + Labwc / Anchor Shell** 的个人机器。系统配置由 Nix 声明并通过本机 flake 构建；本机 flake 位于 `~/nixos-config`，主机目标通常是 `hx90`。涉及其他主机、容器、远程会话或云环境时，先核实实际目标，不要把本机环境套用过去。

## 三个主要工作目录

- `~/nixos-config`：私有 NixOS 系统层。管理 NixOS 模块、系统包与服务、内核/引导、硬件和主机差异，以及本地桌面系统接线。凡需要 `nixos-rebuild`、涉及 `/etc`、systemd 系统服务、系统包/驱动/内核/用户组的变更都在这里声明。编辑源文件，不直接改 `/etc/nixos` 或 `/nix/store`。
- `~/chezmoi`：私人用户配置层。管理跨平台个人 Agent 启动器、用户级软件配置、凭据入口、输入法数据与私人自动化。编辑 chezmoi 源文件；目标家目录文件由 chezmoi 部署。
- `~/dotfiles`：公开通用配置层。管理可公开复用的 Zsh、Neovim、Ranger、Vifm、Starship 和 dotlink。保持内容通用，不放凭据、机器专属信息、私有 Agent/provider 配置。

不要在多个仓库复制同一份配置。判断归属时，以是否属于系统 generation、是否为个人私有、能否脱离本机安全公开分享为准。

## 处理 NixOS 与桌面任务

处理本机系统包、服务、硬件、驱动、Nix 配置、NixOS generation 或本地桌面系统接线时，先找到并阅读适用的 `nixos`、`anchor-desktop` 或其他专项 skill，再依据 skill 和 `~/nixos-config/AGENTS.md` 操作。系统改动要编辑仓库源文件；构建或切换前先检查改动。用户级桌面偏好属于 `~/chezmoi`，桌面系统集成属于 `~/nixos-config`。

Nixarchy 外部依赖已移除。`omarchy-*` 命令保留为兼容接口；桌面 skill 为 `anchor-desktop`。本机 Labwc 构建需 `--impure`，因为合成器源码在 `~/labwc-plus`。

NixOS 是声明式系统：不要用临时安装命令替代持久配置；不要为解决无关问题更新整个 flake；保留已有未提交更改。

## 处理任务前确认现场

无论从哪个工作目录启动，这份文件都作为本机 Agent 的全局背景。三个仓库是常用工作区，不代表每次任务的目标一定在本机。开始前查看当前目录、Git 仓库和已有变更；涉及远端/容器时确认发行版、主机和权限。不要仅凭上下文猜当前所在仓库。各仓库的 `AGENTS.md` 是该仓库规则的具体来源。
