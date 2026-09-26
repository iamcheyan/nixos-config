# Anchor Shell / Nixarchy 脱钩记录

更新时间：2026-09-26

Labwc 的 Quickshell 运行时已经迁到本目录。Nixarchy 仍留在系统里，因为
Hyprland/Omarchy 会话还在用它。策略是：Labwc 继续独立演进，不改 Hyprland
那棵树。

## 已完成

```text
源码           modules/anchor-shell/
启动           Labwc autostart → anchor-shell-labwc-probe.service
输入法         Labwc → anchor-fcitx5.service
兼容命令       modules/anchor-shell/compat/omarchy/
用户数据       ~/.config/anchor-shell/ 和 ~/.local/state/anchor-shell/
旧回退副本     modules/quickshell/ 已删除
```

`modules/labwc.nix` 不再读取 `config.programs.nixarchy.package`。Labwc 也不
再把 Nixarchy 的 `/share/omarchy` 当作 fallback。

2026-09-26 核对过正在运行的 Labwc 实例：

- 配置路径：`.../modules/anchor-shell/shell.qml`（dev）或
  `/nix/store/...-anchor-shell/shell.qml`（nix）
- 用户配置：`~/.config/anchor-shell/shell.json`
- 插件扫描：仓库 `plugins/` + `~/.config/anchor-shell/plugins/`
- `omarchy-fcitx5.service` 在 Labwc 会话中未运行

## 隔离现状

已经分开：shell 源码、用户配置/状态、插件目录、Fcitx 服务、Labwc 的
`OMARCHY_PATH` / `NIXARCHY_ROOT`（指向本仓库 `compat/omarchy/`）。

仍然共享、改 Labwc 时不要碰：

| 位置 | 作用 |
|---|---|
| `flake.nix` 的 Nixarchy input | Hyprland 还需要 |
| `modules/desktop.nix` | Nixarchy 模块和对 Omarchy 包的补丁 |
| `modules/home-manager/hypr/` | Hyprland 用户配置 |
| `modules/home-manager/nixos-user.nix` 的 `programs.nixarchy` | Hyprland 用户模块 |
| `/etc/set-environment` 的 `OMARCHY_PATH` | 默认指向 Nixarchy 树；Labwc 进程会覆盖 |
| 系统 PATH 上的 `quickshell` 包装器 | `labwc.nix` 用 `hiPrio` 装上的，Hyprland 直接调 `quickshell` 也会走到 |

## 以后若要移除 Nixarchy

那是 Hyprland 会话的迁移，不是 Labwc 的。需要先把 Hyprland 的系统接线、
主题服务、用户模块和 `nixarchy-apps.nix` 迁走，再删 `programs.nixarchy`
和 flake input。当前不要做这一步。

## 回退

1. `quickshell-mode nix` 回到上一次 store 构建；或
2. 回退 NixOS generation。

`modules/quickshell/` 已删除，不能再作为源码回退路径。
