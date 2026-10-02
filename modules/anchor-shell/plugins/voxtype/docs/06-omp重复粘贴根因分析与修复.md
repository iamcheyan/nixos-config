# 06 · omp 等 CLI/TUI 工具重复粘贴根因分析与修复

## 1. 现象描述

在使用 Voxtype 语音输入法（SenseVoice 引擎，Hold-to-Talk 模式）进行语音输入时：
- 在普通 GUI 窗口（如浏览器、编辑器）中，转写完成后自动粘贴一次，表现正常；
- 在终端 CLI/TUI 工具（以 `omp` / `Oh My Prompt` 为代表）中，说话结束后转写内容会**被连续粘贴两次**。

用户反馈该问题在 `omp` 这类无内置语音适配的 CLI 命令行工具中尤为明显，担心其他类似的 CLI/TUI 应用也会遇到同样的问题。

---

## 2. 根因剖析（Root Cause Analysis）

通过对 Voxtype 守护进程日志、系统调用（strace）、Kitty 源码及 `omp`（底层 `@oh-my-pi/pi-tui`）输入处理逻辑的联合逆向跟踪，确认导致重复粘贴的完整调用链如下：

### 2.1 整体时序与链路

```text
用户说话结束（按键释放）
  ↓
Voxtype 完成 ASR 转写
  ├─ 1. 执行 pre_output_command: voxtype-paste.py snapshot（记录原剪贴板摘要）
  ├─ 2. Voxtype 自身通过 wl-copy 将转写文本写入系统剪贴板
  └─ 3. 执行 post_output_command: voxtype-paste.py paste（触发自动粘贴）
```

在 `voxtype-paste.py paste` 中，优先检测 Kitty 终端并执行专有注入通道：
```python
if paste_to_focused_kitty():
    return
```

### 2.2 根因一：`kitten @ send-text --stdin` 的 EOF 空包 Bug

原实现使用子进程命令向 Kitty 发送文本：
```bash
kitty @ --to unix:/tmp/mykitty-* send-text --match state:focused --stdin --bracketed-paste auto
```

在现代 Kitty（0.48.2，CLI 由 Go 编写的 `kitten` 二进制实现）中，`--stdin` 和 `--from-file` 在流式读取输入时存在一个协议层边界行为：
通过 `strace -f -s 500 kitty @ send-text --stdin` 抓包可见：
```text
[pid 967545] write(5, "\33P@kitty-cmd", 12)
[pid 967545] write(5, "{\"cmd\":\"send-text\",...,\"payload\":{\"data\":\"base64:YWJj\",\"match\":\"state:focused\",\"bracketed_paste\":\"auto\"}}", 159)
[pid 967545] write(5, "\33\\", 2)
[pid 967545] read(0, "", 2048) = 0   <-- stdin 读到 EOF (0 字节)
[pid 967545] write(5, "\33P@kitty-cmd", 12)
[pid 967545] write(5, "{\"cmd\":\"send-text\",...,\"payload\":{\"data\":\"base64:\",\"match\":\"state:focused\",\"bracketed_paste\":\"auto\"}}", 155)
[pid 967545] write(5, "\33\\", 2)
```

**关键点**：`kitten` 在读取到 EOF（0 字节）时，并未立即结束，而是向 Kitty 服务端多发送了一个 **`data: "base64:"`（长度为 0 的空 Payload）**。

Kitty 服务端在处理 `send-text` 并开启 `--bracketed-paste auto` 时：
1. 收到第一个包 `base64:YWJj`，如果是括号粘贴模式，包装为：
   `\x1b[200~<转写文本>\x1b[201~`
2. 收到第二个包 `base64:`（空），同样按括号粘贴规则包装为：
   `\x1b[200~\x1b[201~`（**一个完全为空的 Bracketed Paste 序列**）。

### 2.3 根因二：`omp` / `pi-tui` 对空 Bracketed Paste 的特殊兜底逻辑

`omp` 是基于 `@oh-my-pi/pi-tui` 的交互式终端应用。其编辑器组件 `CustomEditor`（位于 `custom-editor.ts`）包含如下逻辑：

```typescript
// Bracketed-paste assembly:
//  - empty payload → `onPasteImage` (#3601: `Cmd+V`/`Ctrl+V` on an
//    image-only macOS pasteboard the terminal stripped to `""` first);
//  - explicit image-file paths → `onPasteImagePath`;
//  - anything else → base editor's pasteText
const paste = this.#pasteHandler.process(data);
if (paste.handled) {
    if (paste.pasteContent === undefined) return;
    const content = paste.pasteContent;
    if (content.length === 0 && this.onPasteImage) {
        this.#trackAsyncPaste(Promise.resolve(this.onPasteImage()));
        return;
    }
    this.pasteText(content);
    return;
}
```

- 当正常的 `\x1b[200~<文本>\x1b[201~` 到达时，`content.length > 0`，`omp` 调用 `this.pasteText(content)`，完成**第一次粘贴**；
- 紧接着，Kitty 发送的空包 `\x1b[200~\x1b[201~` 到达，`content.length === 0`；
- `omp` 认为这是一个“被终端剥离为空串的剪贴板粘贴（常见于图片粘贴）”，于是触发 `this.onPasteImage()`；
- `this.onPasteImage()` 调用 `handleImagePaste()` 读取系统剪贴板（`wl-paste`）；
- 剪贴板里此时正是刚转写完成的文本（不是图片），`handleImagePaste()` 执行降级分支：
  ```javascript
  else if (n && !t) n.pasteText(p); else r.pasteText(p);
  ```
  再次将剪贴板文本写入编辑器，导致了**第二次粘贴**！

### 2.4 伴随根因：`active_window_is_terminal()` 的失效

在 `omarchy-universal-paste.py` 原代码中：
```python
quickshell_root = os.environ.get("QUICKSHELL_ROOT", "")
command = ["qs", "ipc"]
if quickshell_root:
    command.extend(["-p", quickshell_root])
command.extend(["call", "shell", "activeAppId"])
```
在非打包开发模式（`quickshell-mode dev`）或系统升级后，环境变量中的 `$QUICKSHELL_ROOT` 指向旧的 `/nix/store` 路径，导致 `qs ipc -p ...` 报错退出码 255，终端检测恒为 `False`。

若检测为 `False`，向终端窗口回退发送的是 GUI 的 `Ctrl+V`。由于部分终端或内部应用会将 `Ctrl+V` 当作自身热键并再次读取剪贴板，同样会放大双重粘贴的风险。

---

## 3. 修复方案

本修复在系统层脚本 `modules/anchor-shell/plugins/voxtype/scripts/omarchy-universal-paste.py` 进行：

### 3.1 消除 Kitty 端的 EOF 空包注入

不通过调用 `kitty @ send-text --stdin`，改为**直接通过 Python 原生 UNIX Domain Socket 向 Kitty 控制套接字发送单条结构化指令**：
- 格式符合 Kitty 远程控制协议：`\x1bP@kitty-cmd{"cmd":"send-text",...}\x1b\`
- 数据以 `base64:<完整转写文本>` 一次性交付
- 连接后单次发送并立即断开，杜绝 Go 客户端在 EOF 处的空包刷新
- 即使未来 Kitty CLI 行为变化，底层协议直接写入依然严格保证只投递一次

### 3.2 统一活动窗口 ID 获取与终端识别

- 将 `active_app_id()` 统一作为 Quickshell 窗口查询入口（通过 `quickshell list --all` 获取活动 PID 并定向通信，不受开发模式根目录变动影响）；
- `active_window_is_terminal()` 复用 `active_app_id()`，保证终端应用名单（`kitty`, `wezterm`, `foot`, `alacritty`, `ghostty` 等）识别准确可靠；
- 保留 `VOXTYPE_PASTE_DEBUG` 环境变量，支持按需调试日志，生产环境下零无用 I/O。

---

## 4. 改动清单（Added & Removed）

### 4.1 增加的内容 (Added)

1. **`send_text_to_kitty_socket(socket_path: pathlib.Path, text_bytes: bytes) -> bool`**：
   - 使用 Python 标准库 `socket`、`json`、`base64` 直接与 Kitty UNIX 控制套接字通信；
   - 构造精确的单个 `send-text` 协议帧，消除流式 EOF 造成的二次空包注入；
   - 超时保护（1.0s），异常时自动回退。
2. **安全回退逻辑**：
   - 若直接套接字发送失败，使用位置参数调用 `kitty @ ... send-text <text>` 而非 `--stdin`，规避 EOF 缺陷。
3. **环境开关日志系统**：
   - 增加 `DEBUG = bool(os.environ.get("VOXTYPE_PASTE_DEBUG"))`；
   - 仅在指定环境变量时输出排查日志到 `/tmp/voxtype-paste.log`。

### 4.2 删除 / 替换的内容 (Removed / Replaced)

1. **删除了 `paste_to_focused_kitty()` 中的 `subprocess.run([... "send-text", "--stdin"])`**：
   - 彻底切断导致现代 `kitten` 产生空包的输入流。
2. **删除了 `active_window_is_terminal()` 中失效的 `["qs", "ipc", "-p", quickshell_root, ...]`**：
   - 移除了对可能过期的 `QUICKSHELL_ROOT` 路径的依赖，消除了 255 错误与误判。
3. **调整了函数定义顺序**：
   - 将 `active_app_id()` 提升至 `active_window_is_terminal()` 之前，保证引用拓扑清晰统一。

---

## 5. 用法与验证指南

### 5.1 日常使用（保持透明）

系统配置已接管并软链至最新脚本，用户操作无需任何改变：
- **触发语音**：按住热键说话（Hold-to-Talk）；
- **释放热键**：Voxtype 识别完成后，在 `omp`、`nvim`、普通终端及 GUI 输入框中均能平滑、单次完成粘贴。

### 5.2 开启排查日志（调试时使用）

若需要观察注入链路分流，可在终端中临时设置：
```bash
export VOXTYPE_PASTE_DEBUG=1
# 模拟执行一次验证
~/.config/labwc/voxtype-paste.py snapshot
wl-copy "测试语音文本"
~/.config/labwc/voxtype-paste.py paste

# 查看日志
tail -f /tmp/voxtype-paste.log
```

日志会记录以下关键决策点：
- `main: clipboard_changed=True`
- `paste_to_focused_kitty: socket ... MATCHED focused window`
- `paste_to_focused_kitty: successfully sent text via socket ...`
- 或 `main: handled by paste_via_shared_universal_clipboard`
