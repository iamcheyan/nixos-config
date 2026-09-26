# Anchor Shell 迁移清单

当前状态：Labwc 已经用本目录作为唯一 Quickshell 源码。Nixarchy/Omarchy 只
服务 Hyprland 会话。

## 本仓库拥有

- `modules/anchor-shell/`：Labwc 的 shell、插件、默认布局
- `compat/omarchy/`：Labwc 进程里的 `omarchy-*` 命令和默认资源
- `quickshell-topbar` / `quickshell-mode`：Labwc 启动和 dev/nix 切换
- `modules/labwc/labwc/scripts/universal-clipboard`：统一复制粘贴

## 已删除

- `modules/quickshell/`：迁出后留下的回退副本，无 Nix 引用

## 仍留给 Hyprland 的接线

不要在 Labwc 工作里删除：

- `programs.nixarchy` 和 Nixarchy Home Manager 模块
- `~/.config/omarchy/` 以及 `~/.config/omarchy/plugins.list`
- `modules/desktop.nix` 对 Nixarchy 包的补丁
- `modules/home-manager/hypr/`

Anchor Shell 的 PluginRegistry 不再扫描 `~/.config/omarchy/plugins/`。

## 运行时选择

`quickshell-mode runtime {compat|legacy}` 还在脚本里。Labwc 的
`NIXARCHY_ROOT` / `OMARCHY_PATH` 已经固定指向本仓库 `compat/omarchy/`，
不再回退到 Nixarchy store 包。日常只用 `quickshell-mode dev|nix`。
