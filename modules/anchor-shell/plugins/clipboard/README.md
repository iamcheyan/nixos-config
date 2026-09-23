# `iamcheyan.clipboard`

这是当前 Anchor Shell/Labwc 会话唯一使用的剪贴板插件。它不是只负责显示历史记录的 UI，而是完整拥有剪贴板历史的捕获、存储、展示和粘贴流程。

## 上游来源与本地维护路径

- 上游仓库：[iamcheyan/omarchy-clipboard](https://github.com/iamcheyan/omarchy-clipboard)
- 上游插件目录：仓库根目录，原始插件 ID 为 `iamcheyan.clipboard`
- 本地维护副本：`modules/anchor-shell/plugins/clipboard/`

当前目录是 Anchor Shell 的仓库内副本，已经包含 Labwc、Anchor Shell 状态目录和本机运行时的适配。后续同步上游时应先比较变更、检查本地适配，再手动合并；不要对当前运行版本使用 `omarchy plugin update`。

## 当前职责

- 顶栏剪贴板按钮和历史面板；
- 文本和图片剪贴板捕获；
- 多显示器和光标位置打开；
- 文本、图片及图片路径粘贴；
- 历史条目删除和清空；
- Labwc 快捷键通过 Quickshell IPC 打开面板；
- Quickshell 重载后重新建立剪贴板 watcher。

插件 ID：

```text
iamcheyan.clipboard
```

## 唯一数据流

Labwc 当前只使用一套 Anchor Shell 状态目录：

```text
${ANCHOR_SHELL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/anchor-shell}/clipboard-history.json
${ANCHOR_SHELL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/anchor-shell}/clipboard-images/
```

数据流如下：

```text
Wayland clipboard
    │
    ├─ wl-paste --watch (text)
    └─ wl-paste --watch (image/png)
             │
             ▼
backend/capture.sh
             │
             ├─ clipboard-history.json
             └─ clipboard-images/
             │
             ▼
apps/iamcheyan-clipboard/services/Cliphist.qml
             │
             ▼
ClipboardPanel.qml / bar/widget.qml
```

文本粘贴脚本也从同一个 `clipboard-history.json` 读取，使用历史索引时不能再读取 `labwc/` 或 `omarchy/` 下的旧文件。

## 与旧实现的关系

Labwc 的插件注册表只加载 `modules/anchor-shell/plugins/` 下的插件，因此该会话只运行 `iamcheyan.clipboard`。未引用的旧版 `Clipboard.qml` 重复 UI 已移除。

独立的 Hyprland Omarchy 兼容会话仍保留它自己的 `omarchy.clipboard` 插件副本；它与 Labwc 会话不会同时运行，也不属于这条 Anchor Shell 数据流。Labwc 的快捷键和菜单统一使用 `iamcheyan.clipboard`。

本插件不应再依赖：

- `modules/anchor-shell/compat/omarchy/shell/plugins/clipboard/`；
- 其他 `clipboard-history.json` 或 `clipboard-images/` 状态目录；
- `~/.local/state/omarchy/clipboard-history.json` 作为运行时主文件；
- `~/.local/state/labwc/clipboard-history.json` 作为运行时主文件；
- `cliphist` 作为后台捕获守护进程。

启动时仍可以从旧的 Omarchy 状态目录迁移一次历史和图片，这是数据迁移，不是运行时双写。迁移不会删除旧目录，便于回滚和兼容性检查。

## 组件说明

### `apps/iamcheyan-clipboard/services/ClipboardCapture.qml`

由 manifest 的 `service` 入口加载，负责启动和重启两个 `wl-paste --watch` 进程。启动时会清理旧版 Omarchy watcher 和本插件旧实例，确保当前会话只有一组 watcher。

### `backend/capture.sh`

接收 watcher 的文本或图片数据，过滤敏感剪贴板内容，写入统一的 Anchor Shell 状态目录，并使用文件锁和原子替换避免并发损坏历史文件。

### `apps/iamcheyan-clipboard/services/Cliphist.qml`

读取统一历史文件，为面板提供条目、过滤、删除和清空操作，并调用本插件自己的粘贴脚本。

### `backend/clipboard-paste-text`

通过历史索引从统一的 Anchor Shell 历史文件读取文本，写回 Wayland clipboard，然后根据参数发送 `Shift+Insert` 或普通文本输入。

### `backend/clipboard-paste-file`

将图片文件以原始 MIME 类型写回 Wayland clipboard，并按需发送终端兼容的粘贴按键。

## Labwc 快捷键

Labwc 的 `clipboard-history` 脚本只负责找到正在运行的 Quickshell，并调用：

```text
quickshell ipc --pid <pid> call iamcheyan.clipboard toggleAtCursor
```

快捷键脚本不应启动第二个 Quickshell，也不应直接调用旧的 `omarchy.clipboard`。

## 维护规则

- 只保留这一套 watcher、历史文件和图片目录；
- UI、捕获脚本和粘贴脚本必须使用相同的状态根目录；
- 不要把 `cliphist` 选择器重新接回当前主流程；
- 修改后检查 `ps`，确认只有本插件的 text/image 两个 watcher；
- 修改后用 Quickshell IPC 测试顶栏按钮、快捷键、文本粘贴和图片粘贴；
- Labwc 快捷键和命令入口统一调用 `iamcheyan.clipboard`；Omarchy 兼容会话使用自己的独立插件。

## 运行时检查

```bash
quickshell list --all
ps -eo pid,ppid,args | rg 'wl-paste.*clipboard'
test -f "${XDG_STATE_HOME:-$HOME/.local/state}/anchor-shell/clipboard-history.json"
```

正常情况下，watcher 命令应指向：

```text
modules/anchor-shell/plugins/clipboard/backend/capture.sh
```
