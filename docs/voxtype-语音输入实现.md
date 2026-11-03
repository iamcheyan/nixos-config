# 语音输入法实现说明

本文说明本仓库当前语音输入从物理按键到文字进入应用的完整链路，并记录主要配置位置、会话启动关系和排错方法。配置分属 NixOS 系统层、Hyprland/Labwc 桌面层和用户目录；模型文件与 `~/.config/voxtype/config.toml` 是本机运行数据，不由本文档中的 NixOS 模板完全描述。

## 1. 全链路概览

```text
MINILA-R 左 Ctrl / CapsLock 单独按住超过 300ms
  → keyd 将长按映射为 F24（Ctrl 组合键仍保持 Ctrl）
  → 当前桌面会话接收 F24
      Hyprland：F24 按下 start，松开 stop
      Labwc：voxtype-ptt 监听 keyd 虚拟键盘，按下 start，松开 stop
  → voxtype.service 从 PipeWire 默认输入源录音
  → 松键后 SenseVoice small-int8 在本机识别中文
  → Voxtype 将新文本写入 Wayland 剪贴板
  → pre/post output hooks 检测剪贴板是否变更，并调用通用粘贴逻辑
  → 终端/TUI 注入 Shift+Insert；图形应用注入 Ctrl+V
```

此外，F9 在 Hyprland 和 Labwc 中用于切换录音；Labwc 还有 Alt+A 切换绑定。顶栏的麦克风图标显示状态并提供设置面板。这些入口最终都控制同一个 Voxtype daemon。

## 2. 按键层：keyd 将长按变成 F24

[modules/keyd-voice.nix](../modules/keyd-voice.nix) 定义可复用的 keyd 映射。核心参数为 300ms：单独按住左 Ctrl 或 CapsLock 超过阈值后，keyd 输出 F24；短按仍是原键。MINILA-R profile 在 [modules/keyd.nix](../modules/keyd.nix) 中合入左 Ctrl 和 CapsLock 映射。物理右 Ctrl 在这块键盘上被重映射为方向键，因此没有用于语音。

映射通过 `oneshotk(control, f24)` 保留 Ctrl 层。这样即使 Ctrl 已按过 300ms，随后按 A 仍是 Ctrl+A，而不是单独的 A。keyd 的 `oneshot_timeout = 50` 用于清除单独长按释放后的残留一次性 Ctrl。

这只是键盘事件转换，不直接运行语音程序。当前配置按 MINILA-R 的 USB/Bluetooth 硬件 ID 匹配；其他键盘不会自动获得这组语音键。

### F24 的两个桌面处理方式

- **Hyprland：** [modules/home-manager/hypr/bindings.lua](../modules/home-manager/hypr/bindings.lua) 清除旧 F24 绑定，再分别绑定按下时 `voxtype record start`、释放时 `voxtype record stop`。F9 绑定 `voxtype record toggle`。
- **Labwc：** [modules/labwc/labwc/keybinds/linux.xml](../modules/labwc/labwc/keybinds/linux.xml) 将 F24 释放绑定到 stop；F24 按下由 `voxtype-ptt` 用户服务监听 keyd 虚拟输入设备并启动录音。F9 和 Alt+A 绑定 toggle。

Labwc 的监听器实现位于 [modules/voxtype-ptt.py](../modules/voxtype-ptt.py)，包装和服务定义位于 [modules/keyd.nix](../modules/keyd.nix)。监听器扫描 `/dev/input/event*`，通过 sysfs 设备名 `keyd virtual keyboard` 找到设备，并读取 Linux evdev 事件。F24 按下时只在 Voxtype 状态为 idle 时 start；释放时只在 recording 时 stop。录音期间按下非修饰键会 cancel，避免 Ctrl 组合操作被误当成语音继续录制；按键自动重复和修饰键不会取消。udev 规则给该虚拟输入设备设置 `uaccess`，使用户服务可以读取事件。

## 3. 服务、录音和识别

Voxtype daemon 运行在用户级 `voxtype.service`。`voxtype-ptt` 是独立的键盘监听服务：它只负责把 F24 事件转换成 Voxtype CLI 命令，录音、模型加载、识别和输出由 `voxtype.service` 完成。

本机用户配置文件是 `~/.config/voxtype/config.toml`。当前有效配置的关键值为：

```toml
engine = "sensevoice"

[audio]
device = "default"
sample_rate = 16000
max_duration_secs = 60
pause_media = true

[output]
mode = "clipboard"
fallback_to_clipboard = true
pre_output_command = ".../voxtype-paste.py snapshot"
post_output_command = ".../voxtype-paste.py paste"

[sensevoice]
model = "small-int8"
quantized = true
language = "zh"
use_itn = true
```

音频从 PipeWire 默认输入设备采集，采样率为 16kHz，单次最长 60 秒；录音期间配置会请求暂停 MPRIS 媒体播放器。SenseVoice 通过 ONNX 版 Voxtype 在本机运行，语言设为中文，`use_itn` 启用数字等文本规范化。模型放在 `~/.local/share/voxtype/models/`，当前模型目录为 `sensevoice-small-int8`，主要文件是 `model.int8.onnx` 和 `tokens.txt`。模型不在仓库内，也不会由 NixOS rebuild 下载。

仓库模板 [modules/anchor-shell/compat/omarchy/default/voxtype/config.toml](../modules/anchor-shell/compat/omarchy/default/voxtype/config.toml) 是通用初始值，包含 Whisper 与 `type` 输出默认项；它不等同于这台机器当前配置。面板桥接程序 [voxtype-config.py](../modules/anchor-shell/plugins/voxtype/scripts/voxtype-config.py) 管理引擎、模型、语言和输出选项，并在修改后重启用户级 `voxtype.service`。

Voxtype 将状态写入 `$XDG_RUNTIME_DIR/voxtype/state`，状态值包括 idle、recording 和 transcribing。Anchor Shell 的顶栏指标读取该状态并显示录音动画；它属于状态展示，不负责音频识别。

## 4. 输出层：剪贴板和通用粘贴

当前选择的是 Universal paste 工作方式：Voxtype 负责把识别文本写入 Wayland 剪贴板，仓库脚本负责面向当前应用发出合适的粘贴动作。配置通过两个 hook 把脚本接入 Voxtype 输出流程：

1. `pre_output_command` 执行 `omarchy-universal-paste.py snapshot`。脚本读取剪贴板文本并保存摘要到 `$XDG_RUNTIME_DIR/voxtype-enhance/clipboard-before.sha256`。
2. Voxtype 将本次识别文本写入剪贴板。
3. `post_output_command` 执行脚本的 `paste` 动作。只有剪贴板内容非空且摘要变化时才继续，避免无语音时把剪贴板旧内容误粘贴。
4. 脚本根据焦点应用选择输入路径。Kitty 有专用远程控制路径；终端/TUI 使用 Shift+Insert；图形应用使用 Ctrl+V。不同 compositor、XWayland 窗口和 Kitty 会走各自的注入实现或回退路径。

主要实现位于 [omarchy-universal-paste.py](../modules/anchor-shell/plugins/voxtype/scripts/omarchy-universal-paste.py)。Labwc 用户配置中的 `~/.config/labwc/voxtype-paste.py` 由 NixOS 模块链接到该仓库脚本；Hyprland 下仍使用同一套输出逻辑，并由脚本探测当前会话及活动窗口。Voxtype 自带的 `type` 模式则是另一条路径：通过合成按键逐字输入。本机不使用它，因为中英混排可能受输入法逐字符处理影响。

顶栏麦克风图标打开插件设置面板，可选模型、语言和输出方式。插件提供三种 ONNX 模型选项：SenseVoice int8、SenseVoice 全精度和 Paraformer int8；当前运行的是 SenseVoice int8。选择模型时，配置桥接程序会检查当前 Voxtype 是否支持所需 ONNX 引擎，再下载并校验模型文件，写配置并重启服务。

## 5. 桌面会话环境为何重要

`wl-copy`、`wtype`、`hyprctl` 等输出工具需要连接当前图形会话。用户级 systemd manager 的环境（例如 `WAYLAND_DISPLAY`、`DISPLAY`、`XDG_RUNTIME_DIR`）必须对应正在运行的 compositor。

Hyprland 启动接线在 [modules/home-manager/hypr/autostart.lua](../modules/home-manager/hypr/autostart.lua)：先运行 `~/.local/bin/desktop-import-session-environment` 导入会话变量，再重启 `voxtype.service`。这样 daemon 使用用户级 systemd manager 环境启动时，能找到正确的 Wayland socket。Labwc 启动脚本在桌面启动后异步重启 `voxtype.service` 和 `voxtype-ptt.service`；其中 Voxtype 的重启用于让 paste hook 获得当前 compositor 的 Quickshell IPC 环境。

若 daemon 沿用旧的 `WAYLAND_DISPLAY`，录音和转写仍可能成功，但 `wl-copy` 会连接已失效的 socket，导致最后输出失败。这次故障的表现就是日志先显示 SenseVoice transcription completed，随后报告 `wl-copy` 失败及 `All output methods failed`。恢复时重新导入**当前会话**变量并重启 Voxtype：

```sh
systemctl --user import-environment \
  WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
  XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS
systemctl --user restart voxtype.service
```

不要手动把示例中的 `wayland-1` 或 `wayland-2` 写死；socket 名称随会话变化。重启 Voxtype 不需要重启桌面 shell。

## 6. 常用状态检查

```sh
# 主 daemon 是否启动、模型是否就绪
systemctl --user status voxtype.service --no-pager -l
journalctl --user -u voxtype.service -n 80 --no-pager

# keyd 的 F24 监听器状态（主要用于 Labwc 按住说话路径）
systemctl --user status voxtype-ptt.service --no-pager -l
journalctl --user -u voxtype-ptt.service -n 50 --no-pager

# 当前用户 systemd manager 保存的图形会话环境
systemctl --user show-environment | grep -E '^(WAYLAND_DISPLAY|DISPLAY|XDG_RUNTIME_DIR)='

# 当前 Voxtype 状态及活动配置
voxtype status --format json
```

### 按现象定位

| 现象 | 优先检查 |
| --- | --- |
| 按键没有任何反应 | MINILA-R 是否被 keyd 识别；左 Ctrl/CapsLock 是否长按超过 300ms；Hyprland F24 绑定或 Labwc 的 `voxtype-ptt.service` 是否正常。 |
| 能开始录音但没有转写 | `voxtype.service` 日志中的音频设备和模型加载错误；模型文件是否存在；daemon 是否显示 `Model loaded, ready for voice input`。 |
| 日志有转写文本，但没有进入应用 | `WAYLAND_DISPLAY` 是否指向当前 compositor；`wl-copy` 是否能在同一会话工作；检查 pre/post hook、脚本日志和当前焦点窗口类型。 |
| 内容进入剪贴板但没有粘贴 | 查看 universal paste 脚本判断到的活动窗口和粘贴分支；检查 Kitty remote control、XWayland 注入或当前 compositor 的虚拟键盘/快捷键注入。 |
| 使用 F9 后录音状态不符合预期 | F9 是 toggle；检查是否已有录音，以及桌面快捷键是否正确绑定。F24 是按住说话，按下开始、松开结束。 |

## 7. 关键文件索引

| 职责 | 文件 |
| --- | --- |
| MINILA-R 长按到 F24 的映射 | [modules/keyd-voice.nix](../modules/keyd-voice.nix)、[modules/keyd.nix](../modules/keyd.nix) |
| Labwc F24 evdev 监听器 | [modules/voxtype-ptt.py](../modules/voxtype-ptt.py) |
| Hyprland 按键接线 | [modules/home-manager/hypr/bindings.lua](../modules/home-manager/hypr/bindings.lua)、[modules/home-manager/hypr/autostart.lua](../modules/home-manager/hypr/autostart.lua) |
| Labwc 按键及服务启动 | [modules/labwc/labwc/keybinds/linux.xml](../modules/labwc/labwc/keybinds/linux.xml)、[modules/labwc.nix](../modules/labwc.nix) |
| 通用 Voxtype 用户配置模板 | [modules/anchor-shell/compat/omarchy/default/voxtype/config.toml](../modules/anchor-shell/compat/omarchy/default/voxtype/config.toml) |
| 顶栏状态与设置面板 | [modules/anchor-shell/plugins/voxtype/README.md](../modules/anchor-shell/plugins/voxtype/README.md)、插件目录 `modules/anchor-shell/plugins/voxtype/` |
| 模型和配置桥接 | [voxtype-config.py](../modules/anchor-shell/plugins/voxtype/scripts/voxtype-config.py) |
| 剪贴板快照与粘贴注入 | [omarchy-universal-paste.py](../modules/anchor-shell/plugins/voxtype/scripts/omarchy-universal-paste.py) |
