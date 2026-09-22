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
modules/anchor-shell/plugins/      当前使用的 first-party 插件
modules/anchor-shell/third-party/  已迁入并由本仓库管理的第三方插件
modules/anchor-shell/compat/       为兼容原有 Omarchy 命名和脚本保留的副本
modules/anchor-shell/docs/         迁移、验证和插件说明
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

开发模式由 `~/.config/quickshell/mode` 选择，内容为 `dev` 时使用仓库源码；
其他情况使用 Nix 构建副本。切换模式的入口仍保留原来的命令名：

```sh
quickshell-mode dev
quickshell-mode nix
quickshell-mode status
```

这些命令名暂时不改，是为了兼容已有脚本和个人工作流；它们的实现和运行源
已经由本仓库管理。

## 插件加载规则

Anchor Shell 的插件注册器只扫描本仓库的插件目录：

1. `modules/anchor-shell/plugins/`
2. `modules/anchor-shell/third-party/`

Hyprland/Omarchy 继续使用它自己的 `~/.config/omarchy/plugins/`。Anchor Shell
不会把这个目录作为插件来源，因此在 Anchor Shell 中修改、替换或调试插件，
不会改变 Hyprland/Omarchy 正在使用的插件源码。

原有插件 ID 和脚本名可以继续保留，例如：

- `omarchy.clock`
- `omarchy.lock`
- `iamcheyan.clipboard`
- `hancore.voxtype-enhance`

这些名称是兼容接口，不代表 Anchor Shell 仍然属于 Omarchy。

## 配置与状态

当前迁移采用“源码先迁移、用户状态后隔离”的顺序。现阶段仍兼容读取：

```text
~/.config/quickshell/shell.json
~/.config/omarchy/shell.toml
~/.config/omarchy/lock-screen.json
~/.local/state/omarchy/...
```

这样可以先切换源码而不丢失现有布局、主题和历史数据。下一阶段会把 Anchor
Shell 自己的可写状态迁移到独立命名空间：

```text
~/.config/anchor-shell/
~/.local/state/anchor-shell/
```

迁移状态完成后，Anchor Shell 将不再读取或写入 Omarchy 的用户状态目录；
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
