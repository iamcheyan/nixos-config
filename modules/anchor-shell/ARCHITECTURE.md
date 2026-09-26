# Anchor Shell 架构与迁移说明

## 目标

Anchor Shell 是一套与具体 Wayland 合成器无关的桌面功能层。它承载我们日常
真正依赖的顶栏、工作区显示、窗口标题、剪贴板、语音粘贴、锁屏、通知、闲置
状态以及相关插件。

它可以由 Labwc、Sway、KDE Plasma 或其他兼容 Wayland 的桌面环境启动。窗口
管理器只负责提供 Wayland 会话、输入和窗口管理；Anchor Shell 负责熟悉的顶栏
和桌面交互。

## 仓库边界

```text
modules/anchor-shell/              Anchor Shell 的完整源码
modules/anchor-shell/plugins/      当前使用并统一维护的插件
modules/anchor-shell/compat/       为兼容原有 Omarchy 命名和脚本保留的副本
modules/anchor-shell/docs/         迁移、验证和插件说明

# 具体源码位置

```text
/home/tetsuya/nixos-config/modules/anchor-shell/
├── shell.qml              Quickshell 入口
├── Commons/               颜色、样式等公共组件
├── Ui/                    通用界面组件
├── services/              应用、插件、状态等公共服务
├── plugins/               当前使用和维护的插件
│   ├── bar/               顶栏和顶栏小组件
│   ├── clipboard/         剪贴板入口
│   ├── desktop-icons/     桌面图标、选择与拖拽
│   ├── voxtype/           语音输入控制插件
│   ├── lock/              锁屏插件
│   ├── notifications/     通知
│   ├── panels/             网络、电源、蓝牙等面板
│   └── services/          闲置、夜灯等后台服务
├── compat/omarchy/        omarchy-* 兼容命令和默认资源
└── docs/                  架构、迁移和插件文档
```

桌面图标插件已迁移到 `plugins/desktop-icons/`，运行时 ID 改为
`desktop-icons`。

## 哪些内容由仓库管理

Git 仓库管理的是源码、默认资源、兼容脚本、Nix 接线和 systemd/Home Manager
启动文件。主要接线位置是：

```text
/home/tetsuya/nixos-config/modules/labwc.nix
/home/tetsuya/nixos-config/modules/desktop.nix
/home/tetsuya/nixos-config/modules/labwc/labwc/scripts/quickshell
/home/tetsuya/nixos-config/modules/labwc/labwc/scripts/quickshell-mode
```

用户自己的布局、主题修改、剪贴板历史和手动安装插件属于运行时数据，不直接
写进 Nix 源码：

```text
~/.config/anchor-shell/              用户配置
~/.config/anchor-shell/plugins/     用户额外插件
~/.local/state/anchor-shell/        主题、通知、剪贴板等状态
```

这部分由 Anchor Shell 使用和初始化，但不会因为 NixOS rebuild 自动覆盖。首次
启动时，如果新目录缺少对应文件，Labwc 会从旧 Omarchy/Quickshell 目录复制，
不会删除旧目录。
```

旧的 `modules/quickshell/` 在迁移完成前保留为回退副本。它不是新的运行时
来源；新的独立桌面层由 `modules/anchor-shell/` 提供。删除旧副本必须等到
Anchor Shell 在所有目标桌面环境中完成验证之后再进行。

## 运行时关系

Labwc 当前通过 `modules/labwc.nix` 构建并启动 Anchor Shell：

```text
modules/anchor-shell/
        │
        ├── immutable Nix source: /nix/store/...-anchor-shell
        └── development source: /home/tetsuya/nixos-config/modules/anchor-shell

Labwc autostart
        └── QUICKSHELL_ROOT → Anchor Shell
```

## Nixarchy 脱钩进度

Labwc/Anchor Shell 的第一阶段脱钩已经完成：

- Labwc 不再使用 `config.programs.nixarchy.package` 作为运行时或回退路径；
- Omarchy 兼容命令和 shell 运行时来自本仓库的 `compat/omarchy/`；
- Labwc 使用独立的 `anchor-fcitx5.service`，不再启动或重启
  `omarchy-fcitx5.service`；
- Telegram Desktop 等普通应用通过标准 `environment.systemPackages` 声明，
  不再依赖 `programs.nixarchy.apps`。

Nixarchy 暂时仍保留在系统中，因为 Hyprland/Omarchy 会话仍使用它自己的
模块、包和服务。后续移除 Nixarchy 前，还需要迁移 Hyprland 的系统接线、主题
服务、用户模块以及 `nixarchy-apps.nix` 的剩余选项。这个阶段不会修改那些配置。

开发模式由 `~/.config/anchor-shell/mode` 选择，内容为 `dev` 时使用仓库源码；
其他情况使用 Nix 构建副本。旧的 `~/.config/quickshell/mode` 只作为兼容读取
来源。切换模式的入口仍保留原来的命令名：

```sh
quickshell-mode dev
quickshell-mode nix
quickshell-mode status
```

这些命令名暂时不改，是为了兼容已有脚本和个人工作流；它们的实现和运行源
已经由本仓库管理。

## 编译后的位置

Nix 构建会把源码复制到不可变的 `/nix/store/`。路径中的哈希会随着源码或依赖
变化，因此不能把哈希写死。当前系统中对应的主要产物包括：

```text
/nix/store/...-anchor-shell
/nix/store/...-anchor-shell-omarchy-compat
/nix/store/...-home-manager-files
/nix/store/...-hm_quickshell
/nix/store/...-hm_quickshellmode
/nix/store/...-nixos-system-hx90-...
```

当前系统 generation 可以通过下面命令查看：

```sh
readlink -f /run/current-system
nix path-info -r /run/current-system | rg 'anchor-shell|hm_quickshell|home-manager-files'
```

Home Manager 暴露给用户的入口是符号链接：

```text
~/.local/bin/quickshell-topbar
~/.local/bin/quickshell-mode
~/.config/labwc/autostart
~/.config/labwc/scripts/quickshell
~/.config/labwc/scripts/quickshell-mode
```

这些链接最终指向 `/nix/store/...`，但开发模式启动的 Quickshell 会直接加载：

```text
/home/tetsuya/nixos-config/modules/anchor-shell/shell.qml
```

因此“源码位置”和“编译后位置”可能不同，实际运行位置要以实例信息为准：

```sh
quickshell list --all
```

## 启动链和运行环境

Labwc 的启动链如下：

```text
NixOS 配置
  └── modules/labwc.nix
      └── ~/.config/labwc/autostart
          └── ~/.local/bin/quickshell-topbar
              └── Anchor Shell / Quickshell
```

当前实例使用的关键环境变量是：

```text
QUICKSHELL_ROOT              Anchor Shell 源码或 store 副本
QUICKSHELL_CONFIG            ~/.config/anchor-shell/shell.json
QUICKSHELL_PLUGINS_DIR       ~/.config/anchor-shell/plugins
ANCHOR_SHELL_CONFIG_DIR      ~/.config/anchor-shell
ANCHOR_SHELL_STATE_DIR       ~/.local/state/anchor-shell
ANCHOR_SHELL_PLUGINS_DIR     ~/.config/anchor-shell/plugins
OMARCHY_PATH                 modules/anchor-shell/compat/omarchy
NIXARCHY_ROOT                modules/anchor-shell/compat/omarchy
```

最后两个变量只是兼容名称；在 Labwc 下指向本仓库的兼容副本，不指向外部
Nixarchy/Omarchy store 包。

## 插件加载规则

Anchor Shell 的插件注册器统一扫描 `modules/anchor-shell/plugins/`。已迁入的外部来源插件也放在该目录，由插件 README 记录其来源。

Hyprland/Omarchy 继续使用它自己的 `~/.config/omarchy/plugins/`。Anchor Shell
不会把这个目录作为插件来源，因此在 Anchor Shell 中修改、替换或调试插件，
不会改变 Hyprland/Omarchy 正在使用的插件源码。

原有插件 ID 和脚本名可以继续保留，例如：

- `omarchy.clock`
- `omarchy.lock`
- `iamcheyan.clipboard`
- `hancore.voxtype-enhance`
- `desktop-icons`

Voxtype 的源码目录现为 `modules/anchor-shell/plugins/voxtype/`；为保持现有
配置和 IPC 兼容，目录名已经改变，但 manifest ID 仍然是
`hancore.voxtype-enhance`。

这些名称是兼容接口，不代表 Anchor Shell 仍然属于 Omarchy。

## 配置与状态

当前迁移采用“源码先迁移、用户状态再隔离”的顺序。Anchor Shell 现在使用：

```text
~/.config/anchor-shell/shell.json
~/.config/anchor-shell/shell.toml
~/.config/anchor-shell/lock-screen.json
~/.local/state/anchor-shell/...
```

Labwc 第一次启动时会在目标文件不存在的情况下，从旧的用户文件复制布局、
主题、锁屏设置和相关状态；复制是非破坏性的，旧路径不会被删除或覆盖。
因此现有布局、主题和历史数据可以平滑迁移。

旧路径只作为一次性迁移来源保留：

```text
~/.config/quickshell/shell.json
~/.config/omarchy/shell.toml
~/.config/omarchy/lock-screen.json
~/.local/state/omarchy/...
```

迁移后 Anchor Shell 不再读取或写入 Omarchy 的用户状态目录；
Hyprland/Omarchy 的配置和历史数据会保持原样。

## 与 Hyprland/Omarchy 的隔离原则

### Anchor Shell 可以拥有的内容

- 顶栏布局和顶栏插件；
- 锁屏界面及其 Quickshell IPC 服务；
- 剪贴板历史界面和粘贴逻辑；
- 语音输入后的粘贴适配；
- 通知、闲置、工作区和活动窗口显示；
- 与合成器无关的启动、截图和桌面操作脚本。

### 不应由 Anchor Shell 修改的内容

- `~/.config/hypr/`；
- `~/.config/omarchy/shell.json`；
- `~/.config/omarchy/plugins/`；
- Hyprland 的窗口规则、动画、工作区和显示器配置；
- Omarchy 原有插件的源码和运行时状态。

### 必须明确标记的兼容内容

`omarchy-*` 命令名、`omarchy.*` 插件 ID、`NIXARCHY_ROOT` 和 `OMARCHY_PATH`
等名称目前作为兼容接口保留。它们只能指向 Anchor Shell 的兼容副本或
明确声明的只读兼容资源，不能重新成为 Hyprland 配置的隐式写入口。

系统级的 keyd、Fcitx、Voxtype、PipeWire 和 systemd user 服务不属于任一套
Shell，因此天然可能被两个桌面环境共享。修改这些服务时必须单独评估，不能
把它们误认为 Anchor Shell 私有配置。

## 修改流程

修改 Anchor Shell 源码时：

```sh
cd /home/tetsuya/nixos-config
git add modules/anchor-shell/<changed-file>
nixos-rebuild build --impure --flake .#hx90
```

确认构建成功后，再执行切换：

```sh
sudo nixos-rebuild switch --impure --flake /home/tetsuya/nixos-config#hx90
```

运行中的 Quickshell 不会自动变成新 store 路径。切换后应确认只有一个实例，
并按当前环境重启 Anchor Shell；不要编辑 `/nix/store` 中的生成副本。

## 验收标准

迁移完成、可以考虑删除旧目录之前，必须确认：

1. Labwc、Sway 或 KDE 启动的都是 `modules/anchor-shell` 对应的实例；
2. Hyprland/Omarchy 仍使用自己的 shell、插件目录和配置；
3. 两套环境的顶栏布局、剪贴板历史、通知状态和锁屏设置互不覆盖；
4. Anchor Shell 中修改插件不会改变 `~/.config/omarchy/plugins/`；
5. 在 Anchor Shell 下执行主题、锁屏、剪贴板和语音粘贴测试后，重新进入
   Hyprland/Omarchy，原有功能仍保持不变；
6. `nix flake check --no-build` 和 `nixos-rebuild build --impure --flake
   .#hx90` 均通过；
7. 旧 `modules/quickshell/` 只在确认无回退需求后才删除。

## 回退

如果 Anchor Shell 的新源码出现问题，可以暂时把 `modules/labwc.nix` 的源码
路径恢复到旧的 `modules/quickshell/`，然后重新构建。Hyprland/Omarchy 不需要
任何回退操作，因为它们的配置树没有被此迁移修改。
