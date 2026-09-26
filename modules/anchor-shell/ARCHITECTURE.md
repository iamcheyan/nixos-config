# Anchor Shell 架构

Anchor Shell 是 Labwc 会话使用的桌面功能层：顶栏、工作区、活动窗口、
桌面图标、剪贴板、语音粘贴、锁屏、通知、闲置和相关面板。窗口管理器只
提供 Wayland 会话、输入和窗口管理。

它由 Quickshell 承载，源码全部在本目录。Labwc 改这里不会改 Hyprland 那份
Omarchy shell。

## 源码树

```text
modules/anchor-shell/
├── shell.qml              Quickshell 入口
├── shell.json             仓库默认布局
├── Commons/               颜色、样式
├── Ui/                    通用界面组件
├── services/              应用库、插件注册、状态
├── plugins/               Labwc 实际加载的插件
│   ├── bar/               顶栏、工作区、活动窗口
│   ├── clipboard/         剪贴板（runtime id: iamcheyan.clipboard）
│   ├── desktop-icons/     桌面图标（runtime id: desktop-icons）
│   ├── voxtype/           语音粘贴（runtime id: hancore.voxtype-enhance）
│   ├── launcher/          启动器
│   ├── lock/              锁屏（runtime id: omarchy.lock）
│   ├── notifications/
│   ├── osd/
│   ├── panels/            网络、电源、蓝牙、时钟等
│   ├── polkit/
│   └── services/          闲置、夜灯、电池、媒体
├── compat/omarchy/        Labwc 自己的 omarchy-* 命令和默认资源副本
└── docs/                  迁移记录和插件说明
```

`compat/omarchy/` 是给 Labwc 用的兼容层，不是 Hyprland 的运行时。Hyprland
的 Omarchy 由本仓库 `modules/packages/desktop-compat.nix` 构建，使用 `~/.config/omarchy/`；两种会话的 shell 源码和用户状态仍分开。

旧的 `modules/quickshell/` 已经删除。它曾经是迁到本目录之前的回退副本，
没有任何 `.nix` 引用，Labwc 和 Hyprland 都不读它。

## 仓库接线

```text
modules/labwc.nix                          Labwc 会话、autostart、systemd
modules/labwc-plus.nix                     本机 labwc-plus 合成器包
modules/labwc/labwc/scripts/quickshell     启动入口（安装为 quickshell-topbar）
modules/labwc/labwc/scripts/quickshell-mode
```

`modules/desktop.nix`、`modules/home-manager/hypr/`、
`modules/packages/desktop-compat.nix` 属于 Hyprland/Omarchy 会话。改
Labwc 顶栏或插件时不要动这些文件。

## 运行时目录

| 用途 | 路径 |
|---|---|
| 用户布局 | `~/.config/anchor-shell/shell.json` |
| 用户插件 | `~/.config/anchor-shell/plugins/` |
| 模式选择 | `~/.config/anchor-shell/mode`（`dev` 或 `nix`） |
| 状态 | `~/.local/state/anchor-shell/` |
| 启动入口 | `~/.local/bin/quickshell-topbar` |
| 模式切换 | `~/.local/bin/quickshell-mode` |

Labwc 第一次启动时，如果新目录还没有对应文件，会从
`~/.config/omarchy/`、`~/.local/state/omarchy/`、`~/.config/quickshell/`
复制一份。旧目录会留下，Hyprland 继续用它们。

磁盘上的 `~/.config/quickshell/` 只是旧数据。`quickshell-mode` 在
`~/.config/anchor-shell/mode` 不存在时仍会去读它，不要把它当成现行配置。

## 开发模式和正式模式

`~/.config/anchor-shell/mode` 为 `dev` 时，启动器直接加载本目录：

```text
QUICKSHELL_ROOT=/home/tetsuya/nixos-config/modules/anchor-shell
```

其他情况使用 Nix 构建的不可变副本：

```text
QUICKSHELL_ROOT=/nix/store/<hash>-anchor-shell
```

用户插件目录始终是 `~/.config/anchor-shell/plugins/`。仓库内 first-party
插件由 `shell.qml` 通过 `QUICKSHELL_ROOT/plugins` 扫描，不经过
`QUICKSHELL_PLUGINS_DIR`。

```sh
quickshell-mode dev      # 切到仓库源码并重启
quickshell-mode nix      # 切回 store 副本并重启
quickshell-mode status
```

改 QML、manifest 或本目录下的插件时，用 `dev`，改完再执行一次
`quickshell-mode dev` 重启。Labwc 的 `reload`（右键菜单 Reload
Configuration）如果发现当前是开发模式，会写回 `nix` 并只通过
`anchor-shell-labwc-probe.service` 拉起一根顶栏，避免开发实例和
systemd 实例叠在一起。改 `modules/labwc.nix`、启动脚本或要验证
store 构建时，才需要：

```sh
cd /home/tetsuya/nixos-config
git add modules/anchor-shell/<changed-file>
sudo nixos-rebuild switch --impure --flake /home/tetsuya/nixos-config#hx90
```

本机合成器来自 `/home/tetsuya/labwc-plus`，在 flake 外，所以 rebuild
需要 `--impure`。

一次运行里，命令行 `-p` 和 `QUICKSHELL_ROOT` 必须指向同一棵树。用
`quickshell list --all` 和进程环境确认：

```sh
quickshell list --all
pid=$(quickshell list --all | awk '/Process ID:/ {print $3; exit}')
tr '\0' ' ' < /proc/$pid/cmdline; echo
tr '\0' '\n' < /proc/$pid/environ | rg '^QUICKSHELL_|^ANCHOR_|^OMARCHY_PATH='
```

保持一个实例。不要 `pkill`；Labwc 的 systemd 服务会立刻拉起旧进程，
容易叠两根顶栏。

## Labwc 启动链

```text
Labwc
  └── ~/.config/labwc/autostart
      └── systemctl --user restart anchor-shell-labwc-probe.service
          └── ~/.local/bin/quickshell-topbar
              └── quickshell -p $QUICKSHELL_ROOT
```

Labwc 进程里的关键环境：

```text
QUICKSHELL_ROOT              本目录或 /nix/store/...-anchor-shell
QUICKSHELL_CONFIG            ~/.config/anchor-shell/shell.json
QUICKSHELL_PLUGINS_DIR       ~/.config/anchor-shell/plugins
ANCHOR_SHELL_CONFIG_DIR      ~/.config/anchor-shell
ANCHOR_SHELL_STATE_DIR       ~/.local/state/anchor-shell
ANCHOR_SHELL_PLUGINS_DIR     ~/.config/anchor-shell/plugins
OMARCHY_PATH                 modules/anchor-shell/compat/omarchy 的副本
XDG_CURRENT_DESKTOP          labwc
```

`OMARCHY_PATH` 在 Labwc 进程里指向本仓库兼容层。系统会话变量与用户服务都由
本仓库声明，Hyprland 的 shell 资源在它自己的会话内使用同一个兼容包。

输入法：

```text
Labwc       → anchor-fcitx5.service
Hyprland    → omarchy-fcitx5.service
```

## 和 Hyprland / Omarchy 的隔离

Labwc 的 shell 源码、配置、状态、插件扫描和输入法服务已经分开。

| 层 | Labwc | Hyprland / Omarchy |
|---|---|---|
| Shell 源码 | `modules/anchor-shell/` | Nixarchy 包 `/nix/store/...-omarchy-*` 和 `...-nixarchy-omarchy-tree` |
| 用户布局 | `~/.config/anchor-shell/` | `~/.config/omarchy/` |
| 用户插件 | `~/.config/anchor-shell/plugins/` | `~/.config/omarchy/plugins/` |
| 状态 | `~/.local/state/anchor-shell/` | `~/.local/state/omarchy/` |
| 启动 | `anchor-shell-labwc-probe.service` | Omarchy/Hyprland autostart |
| 输入法 | `anchor-fcitx5.service` | `omarchy-fcitx5.service` |

Anchor Shell 的 PluginRegistry 只扫描 `modules/anchor-shell/plugins/` 和
`~/.config/anchor-shell/plugins/`。改本目录的插件不会改
`~/.config/omarchy/plugins/`。

Hyprland 会话在本仓库里的位置：

```text
modules/desktop.nix
modules/home-manager/hypr/
modules/home-manager/omarchy-plugins.list
modules/home-manager/nixos-user.nix   中的 programs.nixarchy
modules/packages/nixarchy-omarchy.nix
```

`desktop.nix` 里对 `nixarchyPackage` 的 `postInstall` 补丁（字体、去掉
SystemSwitch、锁屏时禁止热重载）改的是 Hyprland 那份 shell。改 Labwc
不要动那里。

仍然连在一起、改 Labwc 时要避开的系统层：

- `labwc.nix` 往系统 PATH 放了一个高优先级 `quickshell` 包装器（Kirigami /
  `QT_QUICK_CONTROLS_STYLE=Basic`）。Hyprland 如果直接调用 `quickshell`，
  也会走到这个包装器。
- `~/.local/bin/quickshell-mode` 会杀掉当前用户下任意 Quickshell 实例。
  只在 Labwc 会话里用它。
- 主题、keyd、Voxtype、PipeWire 是会话共享的系统服务，不属于任何一套
  shell。

`omarchy-*` 命令名和 `omarchy.*` 插件 ID 保留为兼容接口。`OMARCHY_PATH`
指向 `compat/omarchy/`。

## 插件 ID

目录名可以和 runtime id 不同，`shell.json` 继续用原来的 id：

| 源码目录 | Runtime ID |
|---|---|
| `plugins/bar/` | `omarchy.bar` 以及 `omarchy.workspaces`、`omarchy.active-window` 等 |
| `plugins/clipboard/` | `iamcheyan.clipboard` |
| `plugins/desktop-icons/` | `desktop-icons` |
| `plugins/voxtype/` | `hancore.voxtype-enhance` |
| `plugins/lock/` | `omarchy.lock` |
| `plugins/launcher/` | `iamcheyan.launcher` |

`hancore.overview-workspaces` 和独立的 `iamcheyan.active-window` 用户插件
已经不再作为仓库插件维护；现行顶栏用 `plugins/bar/widgets/`。

## 修改范围

改 Labwc 桌面层时，动这些：

- `modules/anchor-shell/`
- `modules/labwc.nix`、`modules/labwc-plus.nix`、`modules/labwc/`

不要动这些：

- `~/.config/hypr/` 和 `modules/home-manager/hypr/`
- `~/.config/omarchy/`
- Nixarchy 包和 `programs.nixarchy`
- `modules/desktop.nix` 里对 Omarchy 包的补丁

合成器改动只放 `/home/tetsuya/labwc-plus/`，并且只在 QML 拿不到所需信息
时才改。

## 回退

Anchor Shell 出问题：

1. `quickshell-mode nix` 回到上一次 store 构建；或
2. 回退到上一个 NixOS generation。

Hyprland 不需要为 Anchor Shell 的改动做任何回退。旧的
`modules/quickshell/` 已经不存在，不能再把 `labwc.nix` 指回去。
