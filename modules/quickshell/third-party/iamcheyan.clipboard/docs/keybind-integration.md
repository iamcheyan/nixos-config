# 剪贴板历史面板 — 快捷键集成说明

本文档说明 `iamcheyan.clipboard` 插件的快捷键触发机制，以及曾经遇到的
问题与解决过程，供后续维护参考。

---

## 调用链路

```
用户按下 fn+v
  → keyd（muhenkan 层）将其转换为 Ctrl+Alt+V
    → Labwc（rc.xml）检测到 A-C-v，执行
      → ~/.config/labwc/scripts/clipboard-history
        → quickshell ipc --pid <pid> call iamcheyan.clipboard toggleAtCursor
          → 顶栏剪贴板历史面板弹出
```

---

## 各组件的配置位置

| 组件 | 文件 | 关键内容 |
|------|------|---------|
| **keyd 键盘映射** | `modules/keyd.nix` | `settings.muhenkan.v = "C-M-v"` |
| **Labwc 快捷键绑定** | `modules/labwc/labwc/rc.xml` | `<keybind key="A-C-v">` → clipboard-history |
| **触发脚本** | `modules/labwc/labwc/scripts/clipboard-history` | 查找 quickshell PID，通过 IPC 调用插件 |
| **插件 IPC 接口** | `ClipboardPanel.qml` | `ipc function toggleAtCursor()` |

---

## 触发脚本详解

**文件**：`modules/labwc/labwc/scripts/clipboard-history`

```bash
# 确保 Wayland 环境变量存在（Labwc Execute 动作继承的环境可能缺失）
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

QS=/run/current-system/sw/bin/quickshell

# 从进程列表中找到带有 -p 参数的 quickshell 实例
pid="$(ps -eo pid=,args= | awk '/[q]uickshell/ && / -p / { print $1; exit }')"
if [[ -n "$pid" ]]; then
  exec "$QS" ipc --pid "$pid" call iamcheyan.clipboard toggleAtCursor
fi
```

**关键点**：
- 用绝对路径 `/run/current-system/sw/bin/quickshell` 调用，不依赖 `PATH` 里有 `qs`
- quickshell 以 `quickshell -p /path/to/config` 启动，IPC 必须用 `--pid` 指定
  实例，直接 `quickshell ipc call ...` 会报 `Could not find "default" config directory`

---

## 问题历史与根因分析

### 问题现象（2026-09 遇到）
- `Ctrl+Alt+V` 可以正常弹出剪贴板面板 ✓
- `fn+v` 没有任何反应 ✗

### 排查过程

**第一阶段：怀疑脚本路径问题**

`clipboard-history` 脚本用 `exec qs ipc ...` 调用，但 Labwc 通过
`rc.xml Execute` 动作触发脚本时，继承的环境 `PATH` 可能不包含
`/run/current-system/sw/bin`，导致 `qs` 命令找不到。

**修复**：将 `qs` 改为绝对路径 `/run/current-system/sw/bin/quickshell`，
同时补充 `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR` 的兜底导出。

结果：`Ctrl+Alt+V` 依然工作，但 `fn+v` 仍无反应。

**第二阶段：定位到 F13 keysym 问题**

原始设计是 `fn+v` → keyd 发出 `F13` → Labwc `<keybind key="F13">` 触发。
验证发现：
- PID 提取正确（`ps -eo pid=,args=` awk 能匹配到正确的进程）
- `quickshell ipc --pid <pid> call iamcheyan.clipboard toggleAtCursor` 执行成功（exit 0）
- `Ctrl+Alt+V`（`A-C-v`）绑定工作正常
- 但 F13 绑定完全没有触发

**根本原因**：Labwc 对 `F13` keysym 的识别不可靠。keyd 将 `f13`
转换为 xkb keysym 后，Labwc 未能将其匹配到 `<keybind key="F13">`。
（具体原因可能是 xkb keysym 大小写、或 Labwc 对非标准功能键的处理差异）

**最终修复**：绕开 F13 中间层，直接在 keyd 层映射：

```nix
# keyd.nix — muhenkan 层
v = "C-M-v";  # 直接发出 Ctrl+Alt+V，跳过 F13
```

`Ctrl+Alt+V` 绑定已验证可靠，fn+v 现在走同一条路径，问题彻底解决。

---

## 可用快捷键汇总

| 快捷键 | 描述 |
|--------|------|
| `fn+v` | 弹出/关闭剪贴板历史面板（MINILA-R 键盘专用） |
| `Ctrl+Alt+V` | 同上（通用，任意键盘均可用） |
| `Win+v` | 直接粘贴（wtype，不经过剪贴板历史） |
