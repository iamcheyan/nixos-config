# `third-party/` 目录说明

## 目录作用

`modules/anchor-shell/third-party/` 用来存放 Anchor Shell 当前需要集成、但代码最初来自外部项目或第三方插件的完整源码。

这里的“第三方”描述的是代码来源和维护边界，不代表插件没有使用，也不代表这些插件是临时文件。放入本仓库之后，这些代码会随着 NixOS 配置一起被构建和部署，并且可能包含我们为本机 Labwc、Wayland、多显示器和运行时环境做的本地修改。

当前目录中的插件是仓库管理的一部分，不应直接从生成的 `/nix/store` 副本修改。所有修改都应回到本目录的源文件中。

## 和其他目录的区别

### `plugins/`

`modules/anchor-shell/plugins/` 存放 Anchor Shell 的第一方插件，也就是当前项目自己维护、设计和集成的插件。

这些插件通常具有以下特点：

- 由 Anchor Shell 项目直接维护；
- 使用 `omarchy.*` 等第一方命名空间；
- 由第一方插件注册逻辑扫描和加载；
- 代码结构、接口和生命周期由本项目控制。

例如，`plugins/clipboard/` 是 Omarchy 原生的剪贴板 overlay，插件 ID 是 `omarchy.clipboard`。它和本目录中的 `iamcheyan.clipboard` 不是同一个插件。

### `compat/`

`modules/anchor-shell/compat/` 存放兼容层代码，主要用于兼容 Omarchy/Hyprland 侧的旧目录结构、脚本、配置和插件接口。

兼容层不等于当前 Labwc 主运行路径。即使某个功能在 `plugins/` 或 `third-party/` 中已经有新的实现，`compat/` 里的对应文件也不能仅凭目录名称直接删除，需要先确认兼容环境是否仍然依赖它。

### 用户插件目录

用户自行安装的插件位于用户配置目录，例如：

```text
~/.config/anchor-shell/plugins/
~/.config/omarchy/plugins/
```

这些目录属于用户运行时配置，不属于本仓库源代码。它们可以由插件管理命令安装、更新或删除，不能假定其内容和本仓库中的副本始终同步。

## 插件发现和运行方式

当前 Labwc 版 Anchor Shell 的插件注册器会分别扫描：

1. `modules/anchor-shell/plugins/`：第一方插件；
2. `modules/anchor-shell/third-party/`：仓库管理的第三方插件；
3. 用户插件目录：由相应的用户运行时负责。

因此，插件放在 `third-party/` 并不会使它失效。它仍然会被读取 `manifest.json`、注册到插件表，并可以提供 bar widget、overlay 或 service 等入口。

需要注意的是，插件的“目录名”和“插件 ID”是两个概念：

- 目录名用于定位源代码，例如 `iamcheyan.clipboard/`；
- manifest 中的 `id` 用于配置、IPC、快捷键和运行时识别，例如 `iamcheyan.clipboard`。

只改目录名不一定会影响运行，但改插件 ID 会影响所有引用它的配置和 IPC 调用。迁移时必须同时检查 `shell.json`、QML 中的 `moduleName`、IPC target、Labwc 脚本、Nix 路径和文档。

## 当前目录内容

### `hancore.voxtype-enhance/`

Voxtype 语音输入增强插件，提供顶栏控制、模型和语言配置，以及终端感知的 universal paste 行为。

当前 ID：

```text
hancore.voxtype-enhance
```

它目前被 `shell.json` 的顶栏配置启用，同时也出现在 `modules/home-manager/omarchy-plugins.list` 中。其脚本还被 `modules/labwc.nix` 的运行时接线引用，因此不能只删除插件目录。

### `iamcheyan.clipboard/`

面向当前 Labwc 会话的剪贴板插件，包含：

- 顶栏 clipboard widget；
- 剪贴板历史面板；
- 文本和图片条目处理；
- 后台捕获服务；
- 多显示器定位和光标位置打开逻辑；
- Labwc 快捷键和 IPC 集成脚本。

当前 ID：

```text
iamcheyan.clipboard
```

这是当前 `shell.json` 中实际启用的 clipboard 插件。它使用 Omarchy/Labwc 的剪贴板状态和图片目录，但并不等于 `plugins/clipboard/` 中的原生 Omarchy 实现。

### `henri.desktop-icons/`

桌面图标插件，负责桌面文件展示、文件图标、拖拽、选择、右键菜单、多显示器布局和桌面文件操作。

当前 ID：

```text
henri.desktop-icons
```

它还包含与 Dolphin “发送到桌面”操作相关的 service menu。`modules/labwc.nix` 对该插件的脚本、Python 运行环境和 Dolphin 文件路径存在显式引用，因此迁移目录时必须同步修改 Nix 接线。

## 为什么不直接全部放进 `plugins/`

从运行机制上说，第三方插件也可以统一放进 `plugins/`。但目前分开存放有几个实际作用：

- 能清楚区分第一方代码和外部来源代码；
- 避免误以为第三方插件使用了第一方生命周期和接口；
- 方便记录上游来源、许可证和本地修改；
- 便于后续同步上游或比较本地 patch；
- 让代码 review 时能够识别哪些逻辑是项目自身实现，哪些是外部代码的本地适配。

如果项目决定统一目录，建议把它作为一次明确的目录迁移，而不是直接移动文件。至少需要同步检查：

1. `PluginRegistry.qml` 的扫描根目录；
2. `modules/labwc.nix` 中的插件路径和环境变量；
3. `shell.json` 中的插件 ID 和启用状态；
4. Home Manager 的插件清单；
5. QML 的 `moduleName`、IPC target 和 service namespace；
6. Labwc 快捷键脚本和 Dolphin service menu；
7. `ARCHITECTURE.md`、迁移文档和插件 README；
8. 第一方/兼容层是否仍然存在同名插件目录。

尤其是 `plugins/clipboard/` 已经存在 `omarchy.clipboard`。如果要把 `iamcheyan.clipboard` 改名为 `plugins/clipboard/`，必须先处理两个不同实现之间的目录冲突，并确认旧实现是否仍被兼容层使用。

## 删除插件前的检查清单

删除本目录中的插件前，至少应完成以下检查：

- 在整个仓库搜索插件 ID、目录名和脚本名；
- 检查 `shell.json` 是否启用或禁用该插件；
- 检查 `modules/labwc.nix` 是否有显式路径引用；
- 检查 Home Manager 插件清单是否仍安装它；
- 检查 QML IPC、快捷键脚本和 system/user service；
- 检查 `compat/` 是否有同功能但不同路径的依赖；
- 停止或重启 Quickshell 后验证实际加载的插件列表；
- 完成 `nix flake check --no-build` 和必要的构建验证。

不能因为某个插件没有出现在当前顶栏，就判断它已经没有用。overlay、service、快捷键入口和兼容层依赖可能不会直接显示在顶栏中。

## 修改和迁移原则

- 修改源文件，不修改 `/nix/store` 中的生成副本；
- 保留用户已有的未提交修改，不在迁移时覆盖它们；
- 目录迁移和功能修改分开提交；
- 第三方来源更新、本地适配和第一方重构分开提交；
- 如果必须修改插件 ID，应提供旧 ID 到新 ID 的迁移或兼容别名；
- 修改后确认只运行一个 Quickshell 实例，并检查实际加载的 store/dev 路径；
- 删除内容前先确认没有其他显示器、快捷键、兼容会话或文件管理器入口依赖它。

## 相关文件

```text
modules/anchor-shell/services/PluginRegistry.qml
modules/anchor-shell/compat/omarchy/shell/services/PluginRegistry.qml
modules/anchor-shell/plugins/
modules/anchor-shell/compat/
modules/anchor-shell/shell.json
modules/labwc.nix
modules/home-manager/omarchy-plugins.list
modules/anchor-shell/ARCHITECTURE.md
modules/anchor-shell/docs/plugin-migration.md
```
