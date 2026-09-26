# Anchor Shell

Labwc 会话的 Quickshell 桌面层：一根长驻进程里跑顶栏、面板、锁屏、通知、
桌面图标和相关插件。源码就在本目录。架构、隔离和路径见
[ARCHITECTURE.md](ARCHITECTURE.md)，改代码前读 [AGENTS.md](AGENTS.md)。

Hyprland 的 Omarchy shell 是另一棵树（Nixarchy 包 + `~/.config/omarchy/`）。
改这里不会改那份。

## 日常开发

```bash
quickshell-mode dev          # 直接加载本目录
# 编辑 QML 后再执行一次，让 shell 重启
quickshell-mode status
quickshell list --all        # Config path 应为本目录的 shell.qml
```

切回 Nix store 构建：

```bash
quickshell-mode nix
```

改 `modules/labwc.nix` 或要验证 store 构建时：

```bash
cd /home/tetsuya/nixos-config
git add modules/anchor-shell/<changed-file>
sudo nixos-rebuild switch --impure \
  --flake /home/tetsuya/nixos-config#hx90
```

本机合成器来自 `/home/tetsuya/labwc-plus`，rebuild 需要 `--impure`。flake
只看见已跟踪或已暂存的文件。

用户布局：`~/.config/anchor-shell/shell.json`  
用户插件：`~/.config/anchor-shell/plugins/`

```bash
quickshell ipc call shell reloadConfig
quickshell ipc call shell rescanPlugins
```

## 配置优先级

仓库默认布局：

```text
/home/tetsuya/nixos-config/modules/anchor-shell/shell.json
```

用户布局一旦存在就是权威文件，不会和默认做 deep-merge：

```text
/home/tetsuya/.config/anchor-shell/shell.json
```

缺某个 widget 时先看这个文件的 `bar.layout` 和 `disabledPlugins`。Labwc 可能
把桌面报成 `labwc:wlroots`，检测时按冒号分隔，认 `labwc` 即可。

## 源码布局

```text
shell.qml
Commons/
Ui/
services/          PluginRegistry, BarWidgetRegistry, AppLibrary
plugins/           见 plugins/README.md
compat/omarchy/    Labwc 自己的 omarchy-* 兼容命令，不是 Hyprland 运行时
docs/
```

## Plugin manifest

每个插件根目录有 `manifest.json`。最小例子：

```json
{
  "schemaVersion": 1,
  "id": "my.org.cool-clock",
  "name": "Cool clock",
  "version": "1.0.0",
  "author": "You",
  "description": "A clock that does cool things",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "Cool clock",
    "category": "Time",
    "allowMultiple": false,
    "defaultSection": "left",
    "defaults": { "format": "HH:mm" },
    "schema": [
      { "key": "format", "type": "string", "label": "Format" }
    ]
  }
}
```

| Kind         | 作用 |
|--------------|------|
| `bar-widget` | 顶栏一段 |
| `panel`      | 浮层面板 |
| `overlay`    | 全屏 overlay |
| `menu`       | 菜单表面 |
| `service`    | 无 UI 的单例 |
| `bar`        | 整根顶栏，可替换内置 `omarchy.bar` |

同一时间只有一根 `bar` 插件生效。完整 schema 在 `services/PluginRegistry.qml`。

## 用户插件

放到 `~/.config/anchor-shell/plugins/<id>/`，带 `manifest.json` 和
`entryPoints` 指向的 QML，然后：

```bash
quickshell ipc call shell rescanPlugins
```

不要写到 `~/.config/omarchy/plugins/`。那是 Hyprland 的目录。

插件在 Quickshell 进程里以非沙箱代码运行。只加载你愿意审查的源码。

## IPC

运行中的 shell 暴露 `shell` 目标，以及插件自己注册的目标。

| Method | Effect |
|---|---|
| `ping` | 健康检查 |
| `summon <id> <payloadJson>` | 打开 panel/overlay |
| `hide <id>` | 关闭 |
| `toggle <id> <payloadJson>` | 开关 |
| `call <id> <method> <arg>` | 调已加载插件的方法 |
| `rescanPlugins` | 重新扫描插件目录 |
| `reloadConfig` | 重载 `~/.config/anchor-shell/shell.json` |
| `setPluginEnabled <id> <enabled>` | 持久化启用位；只有字面量 `"true"` 启用 |
| `listPlugins` | JSON 列表 |

```bash
quickshell ipc call shell ping
quickshell ipc call shell listPlugins
```

Labwc 进程里 `omarchy-shell` 仍可用，因为它来自 `compat/omarchy/bin`，
`OMARCHY_PATH` 指向那份副本。那是兼容入口，启动路径仍是
`quickshell-topbar`。

## shell.json

```json
{
  "version": 1,
  "idle": {
    "screensaver": 150,
    "lock": 300
  },
  "bar": {
    "id": "omarchy.bar",
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left":   [ { "id": "omarchy.menu" }, { "id": "omarchy.workspaces" } ],
      "center": [ { "id": "omarchy.clock", "format": "HH:mm" } ],
      "right": [
        { "id": "omarchy.audio" }
      ]
    }
  },
  "plugins": []
}
```

- `bar.id` 省略或 `omarchy.bar` 用内置顶栏。
- 设置写在条目自己身上，没有另一层 merge。
- first-party 非 widget 插件默认启用，禁用写入 `disabledPlugins[]`。
- `version: 1` 必填。
