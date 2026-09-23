# `third-party/` 目录说明

## 目录作用

`modules/anchor-shell/third-party/` 用来记录仍按外部来源边界管理的内容。
当前目录不再存放已迁移插件的源码；已纳入 Anchor Shell 运行时的外部来源插件
统一位于 `modules/anchor-shell/plugins/`，并在各自 README 中记录上游地址。

这里的“第三方”描述的是代码来源和维护边界，不代表插件没有使用，也不代表这些插件是临时文件。
当前目录保留这个说明文件，避免将“外部来源”误解为“必须继续放在
`third-party/`”；实际源码位置以插件 README 和 Nix 接线为准。

## 和其他目录的区别

### `plugins/`

`modules/anchor-shell/plugins/` 存放 Anchor Shell 当前统一维护和加载的插件，
其中既有项目自有插件，也有已经迁移进来的外部来源插件。

这些插件通常具有以下特点：

- 由 Anchor Shell 项目统一维护和集成；
- 可以使用 `omarchy.*`，也可以保留上游运行时 ID；
- 由第一方插件注册逻辑扫描和加载；
- 代码结构、接口和生命周期由本项目控制。

剪贴板插件 `iamcheyan.clipboard` 已迁移到
`modules/anchor-shell/plugins/clipboard/`。旧的第一方 `omarchy.clipboard`
实现已经移除；兼容层只保留必要的快捷键和命令入口，并统一转发到
`iamcheyan.clipboard`。

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

当前 Labwc 版 Anchor Shell 的插件注册器会扫描：

1. `modules/anchor-shell/plugins/`：仓库统一维护的插件；
2. 用户插件目录：由相应的用户运行时负责。

`third-party/` 本身不是当前插件扫描根目录；它只保留来源说明和迁移记录。

需要注意的是，插件的“目录名”和“插件 ID”是两个概念：

- 目录名用于定位源代码，例如 `plugins/clipboard/`；
- manifest 中的 `id` 用于配置、IPC、快捷键和运行时识别，例如 `iamcheyan.clipboard`。

只改目录名不一定会影响运行，但改插件 ID 会影响所有引用它的配置和 IPC 调用。迁移时必须同时检查 `shell.json`、QML 中的 `moduleName`、IPC target、Labwc 脚本、Nix 路径和文档。

## 当前目录内容

### Voxtype

Voxtype 语音输入增强插件已经迁移到
`modules/anchor-shell/plugins/voxtype/`。它的运行时 ID 仍是
`hancore.voxtype-enhance`，因此现有配置和 IPC 兼容。

### `iamcheyan.clipboard`

该插件已经迁移到 `modules/anchor-shell/plugins/clipboard/`，不再属于本目录。
迁移只改变源码目录，不改变 manifest ID `iamcheyan.clipboard`，因此现有
`shell.json`、IPC、快捷键和状态路径保持兼容。

### 桌面图标插件迁移

桌面图标插件已迁移到
`modules/anchor-shell/plugins/desktop-icons/`，运行时 ID 改为
`desktop-icons`。它负责桌面文件展示、文件图标、拖拽、选择、右键菜单、
多显示器布局和桌面文件操作，并包含 Dolphin“发送到桌面” service menu。

`third-party/` 不再保留该插件副本；Nix 接线位于 `modules/labwc.nix`。

## 为什么不直接全部放进 `plugins/`

从运行机制上说，外部来源插件统一放进 `plugins/` 没有问题。本仓库已经完成
这次统一迁移，`third-party/` 不再作为源码归档目录。外部来源和本地改动边界
改由各插件 README 记录，实际作用是：

- 方便记录上游来源、许可证和本地修改；
- 便于后续同步上游或比较本地 patch；
- 让代码 review 时能够识别哪些逻辑是项目自身实现，哪些是外部代码的本地适配。

目录迁移完成后，仍需持续检查：

1. `PluginRegistry.qml` 的扫描根目录；
2. `modules/labwc.nix` 中的插件路径和环境变量；
3. `shell.json` 中的插件 ID 和启用状态；
4. Home Manager 的插件清单；
5. QML 的 `moduleName`、IPC target 和 service namespace；
6. Labwc 快捷键脚本和 Dolphin service menu；
7. `ARCHITECTURE.md`、迁移文档和插件 README；
8. 第一方/兼容层是否仍然存在同名插件目录。

桌面图标、剪贴板和 Voxtype 插件的迁移已经完成上述检查；旧目录不再作为
运行时源码来源使用。

当前不再新增第二套剪贴板实现。兼容层的旧命令入口不能重新指向
`omarchy.clipboard`，必须调用 `iamcheyan.clipboard`，不能和当前 Labwc 的唯一实现混用。

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
