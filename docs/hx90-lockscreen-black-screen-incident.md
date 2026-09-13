# HX90 锁屏卡死与黑屏事故记录

日期：2026-09-06  目标主机：`hx90`（NixOS，192.168.3.149）

## 结论摘要

这次不是传统 `hyprlock` 二进制本身卡死，而是 Omarchy 使用的
`iamcheyan.lock-screen` Quickshell 插件在 Wayland session lock 生命周期中
遗留了一个安全锁状态。

锁屏曾经成功进入 `secure=true`，密码 PAM 认证也曾成功，但插件在本地热重载
后进入了：

```text
lock-stranded: recovering
lock-requested
lock-pending: screen-stabilizing
```

随后没有提供可用的 IPC 解锁方法，且插件自己的 `omarchy-restart-shell` 保护逻辑
拒绝在锁定状态下重启 Shell。这使得图形界面无法正常恢复。

之后终止图形会话时，SDDM greeter/helper 又出现一次崩溃，导致屏幕表现为完全黑屏。
这不是 GPU、HDMI、EDID 或整台机器死机：SSH 始终可用，系统仍在运行，
`HDMI-A-2` 一直是 `connected/enabled`，AMD GPU 没有新的显示驱动错误。

最终恢复方式是：

1. 保留远程 SSH 通道。
2. 确认锁状态确实卡在 `secure=true`。
3. 终止卡死的活动图形会话，回到 SDDM。
4. 重启 `display-manager.service`，恢复 SDDM greeter/session。
5. 禁用第三方 `iamcheyan.lock-screen`，恢复 Omarchy 原生 `omarchy.lock`。
6. 执行显示唤醒命令，确认新的 Omarchy session 为未锁定状态。

## 现场证据

### 主机和网络没有死

SSH、ping、22 端口均正常；远程执行得到：

```text
HOST=hx90 USER=tetsuya
systemd=running
```

因此第一步应始终是从 SSH/TTY 判断“系统死机”还是“图形 session 死机”。

### 锁屏不是 hyprlock 进程

进程列表中没有 `hyprlock`，实际运行的是：

```text
quickshell -n -p .../nixarchy-omarchy-tree/shell
```

锁屏界面由：

```text
~/.config/omarchy/plugins/iamcheyan.lock-screen/
```

中的 `Service.qml` 和 `LockView.qml` 提供，使用 Quickshell 的
`WlSessionLock` 与 PAM。

### PAM/密码不是根因

日志中曾出现：

```text
Starting pam session for user "tetsuya"
Authenticated successfully.
```

所以不能把这次事故归因于密码错误、PAM 配置错误或指纹配置错误。

### 真正卡住的状态

锁屏 IPC 返回过：

```json
{
  "locked": true,
  "requested": true,
  "pending": true,
  "sessionLocked": false,
  "secure": true,
  "realScreens": 1,
  "passwordPam": true
}
```

Hyprland 的显示器状态同时包含：

```json
{"name":"HDMI-A-2","solitaryBlockedBy":["LOCK","WINDOWED","CANDIDATE"]}
```

这说明 compositor 仍然持有 session lock；不能把它当成普通 Shell 崩溃后直接
重启。直接杀掉锁客户端可能留下 Hyprland failsafe，产生更彻底的黑屏。

### 触发链

本次日志时间线如下：

```text
15:21:52  lock-requested
15:21:52  secure=true
15:21:55  Local plugin changed, reloading: iamcheyan.lock-screen
15:21:55  lock-stranded: recovering
15:21:55  lock-requested
15:21:55  lock-pending: screen-stabilizing
```

插件目录当时存在未提交的 `LockView.qml` 修改，内容主要是头像缓存刷新和
`cache: false`。目前能确认的是：它导致/伴随了插件热重载；不能仅凭现有证据
断言头像代码本身是功能性根因。真正危险的是“锁屏已经 secure 时触发插件热重载”。

## 为什么后来变成完全黑屏

锁屏卡住后尝试恢复图形会话，活动 Wayland session 被终止。随后 SDDM 日志中出现：

```text
Authentication error: ... "Process crashed"
sddm-helper ... omarchy-session ... crashed (exit code 1)
```

此时 SDDM 服务本身仍然是 active，但 greeter 不一定已经成功显示，所以用户看到
的是黑屏而不是登录界面。

同时必须注意：锁屏的 blank/wake 逻辑可能已经执行过显示关闭命令。因此恢复时
要同时检查：

```bash
cat /sys/class/drm/card1-HDMI-A-2/status
cat /sys/class/drm/card1-HDMI-A-2/enabled
systemctl is-active display-manager.service
```

本次结果为 `connected`、`enabled`、`active`，说明不是物理断线或 GPU 输出丢失。

## 本次实际恢复操作

以下命令是本次使用过的恢复路径。执行前必须确认目标主机和活动 session。

### 1. 检查锁状态

```bash
OMARCHY_SHELL_IPC_TIMEOUT=2s omarchy-shell lock status
```

若返回 `secure=true`，不能直接假设 `omarchy-restart-shell` 安全。

### 2. 保存并切换锁屏配置

原配置备份为：

```text
~/.config/omarchy/shell.json.pre-lockscreen-fix-20260906-152708
```

最终配置为：

```json
{
  "plugins": [{"id": "omarchy.lock"}],
  "disabledPlugins": ["iamcheyan.lock-screen", "omarchy.menu"]
}
```

这里没有删除第三方插件目录，只是禁用它，因此可以在后续调查完成后恢复。

### 3. 终止卡死的活动图形 session

先找 `Active=yes` 且 `Type=wayland` 的 session：

```bash
loginctl list-sessions
loginctl show-session <SESSION_ID> -p Type -p Active -p State -p Leader
```

本次活动 session 是 13，使用：

```bash
sudo loginctl terminate-session 13
```

这会丢失该图形 session 中未保存的 GUI 应用状态，所以这是恢复手段，不是日常
操作。SSH manager session 不应一起终止。

### 4. 恢复 SDDM

```bash
sudo systemctl restart display-manager.service
```

然后检查：

```bash
systemctl is-active display-manager.service
pgrep -a -f 'sddm|sddm-greeter'
sudo journalctl -u display-manager.service -b -n 60 --no-pager
```

### 5. 恢复显示输出

```bash
omarchy-system-wake
omarchy-brightness-display on
```

键盘背光没有设备时出现 `No keyboard backlight device found` 不代表显示失败，
HX90 本机没有对应的 keyboard backlight device。

### 6. 最终验证

登录后检查：

```bash
OMARCHY_SHELL_IPC_TIMEOUT=2s omarchy-shell lock status
```

正常空闲状态应接近：

```json
{
  "locked": false,
  "requested": false,
  "pending": false,
  "sessionLocked": false,
  "secure": false
}
```

## 如何避免再次发生

### 1. 不要在锁屏 secure 期间热重载锁屏插件

最重要的规则：

> 锁屏已经 `secure=true` 或 Hyprland 显示器包含 `LOCK` 时，不要修改、更新、
> checkout、切换分支或让 watcher 重载锁屏插件目录。

尤其要避免：

```bash
chezmoi apply
git pull
git checkout ...
omarchy plugin update iamcheyan.lock-screen
```

这些操作如果触碰 `~/.config/omarchy/plugins/iamcheyan.lock-screen`，可能触发
Quickshell 的本地插件重载。

### 2. 修改锁屏插件前先禁用自动锁屏

把 Omarchy idle lock 暂时调大或关闭，确保当前不是锁屏状态，再修改插件。
修改完成后重新启动一次完整图形 session，确认：

```bash
omarchy-shell lock status
```

处于 `locked=false` 后再测试手动锁屏。

### 3. 不要在锁定状态直接使用 `omarchy-restart-shell`

该命令有保护逻辑，发现 session lock 时会输出：

```text
Refusing to restart Omarchy shell while the session is locked.
```

这是正确的保护，不应该绕过。因为普通重启可能让锁客户端消失，但让 Hyprland
继续处于 LOCK failsafe，形成“屏幕黑、没有输入界面”的状态。

### 4. 为锁屏插件保留可用的安全回退

建议长期保持：

- Omarchy 原生 `omarchy.lock` 作为默认锁屏；
- 第三方锁屏只在明确测试时启用；
- 修改前备份 `~/.config/omarchy/shell.json`；
- 保留 SSH、TTY 或本地 console 的恢复路径；
- 不要把锁屏恢复完全依赖图形界面上的快捷键。

### 5. 给锁屏插件增加更可靠的恢复设计

后续调查可以考虑给 `iamcheyan.lock-screen` 增加：

1. 显式的 `unlock`/`abort` 管理接口，但必须要求本地认证或 console 权限，不能
   变成绕过锁屏的后门。
2. 插件热重载前检测 `sessionLock.secure`，若已锁定则延迟 reload，而不是销毁
   当前 lock client。
3. 把 `secure=true`、`sessionLocked=false`、`pending=true` 视为异常组合，显示
   可见的恢复提示，而不是无限等待 `screen-stabilizing`。
4. 在锁屏 client 被重启时，先确认旧的 `WlSessionLock` 已释放，再重新申请锁。
5. 增加自动化测试：锁定、插件文件变更、Shell reload、显示器重连、解锁、休眠
   唤醒等场景都要覆盖。

### 6. 监控日志中的早期信号

出现下面任意组合，就应立即停止继续改配置并走恢复流程：

```bash
journalctl --user -b --no-pager | grep -E \
  'lock-stranded|lock-pending|secure=true|Local plugin changed'
```

重点信号：

- `lock-stranded: recovering`
- `secure=true` 后紧跟 `Local plugin changed`
- 长时间只有 `lock-pending: screen-stabilizing`
- `locked=true` 但界面没有输入响应
- Hyprland `solitaryBlockedBy` 含 `LOCK`，而锁屏 UI 已消失

## 后续调查建议

1. 在不启用第三方锁屏的状态下，确认原生 `omarchy.lock` 可以重复锁定/解锁。
2. 备份当前插件目录后，在测试窗口重新启用第三方插件。
3. 暂时撤销本地 `LockView.qml` 修改，先测试上游 `75e4e7c` 原始版本。
4. 单独测试头像文件不存在、头像热更新、显示器重连，不要把多个变量混在一起。
5. 记录每次测试的 `omarchy-shell lock status`、Hyprland monitor JSON 和用户 journal。
6. 如果问题只在插件文件变化时出现，应优先修复插件热重载生命周期，而不是继续
   调整 PAM、GPU 或 SDDM。

## 当前状态

本次处理结束时：

- 主机 `hx90` 在线，未重启。
- `display-manager.service` 为 active。
- `HDMI-A-2` 为 connected/enabled。
- 新 Omarchy session 的锁状态为 `locked=false`、`secure=false`。
- `iamcheyan.lock-screen` 已禁用，原生 `omarchy.lock` 已启用。
- 原第三方插件目录仍保留，后续可在隔离测试中调查。

## 2026-09-06 晚些时候复发后的追加调查

后续复发证明：之前仅修改用户侧 `shell.json` 不是持久解决方案。配置又回到了：

```json
{
  "plugins": [{"id": "iamcheyan.lock-screen"}],
  "disabledPlugins": ["omarchy.menu", "omarchy.lock"]
}
```

因此第三方锁屏插件重新成为实际锁屏实现。

这次日志给出了更完整的链：

```text
16:19:45  lock-requested
16:19:46  secure=true
16:21:05  There are no outputs - creating placeholder screen
16:21:05  The Wayland connection experienced a fatal error: Invalid argument
16:21:05  Omarchy shell exited with status 255; relaunching.
16:29:25  lock-stranded: refusing-second-lock
16:29:25  lock-requested
16:29:26  secure=true
```

这说明复发的直接机制不是 Shizuka 的背景、头像或颜色，而是：

1. 自定义锁屏已经持有 `WlSessionLock`。
2. Wayland 输出短暂消失，Quickshell 看到 placeholder screen 并退出。
3. 新 Shell 启动时发现 compositor 仍然有旧的 `LOCK` failsafe。
4. 旧代码虽然记录了 `refusing-second-lock`，但随后 idle 服务仍可再次调用
   `beginLock()`，重新申请第二把锁。
5. 第二次申请又进入 `secure=true`，用户看到黑屏或无输入界面。

### 已实施的锁屏代码修复

在 `~/.config/omarchy/plugins/iamcheyan.lock-screen/Service.qml` 增加了
`strandedLockBlocked` 状态：

- 发现旧 compositor lock 时保持阻断状态；
- `beginLock()` 在阻断状态下返回 `lock-denied: stranded-lock`；
- 不再让 idle timeout 在旧锁未清除时申请第二把锁；
- 只有明确检测到 compositor 返回“无锁”，或一次真实解锁完成后才清除阻断。

这份修改保留了你自己的锁屏界面和 PAM 认证，不是换回默认主题。

### 已实施的 Shizuka/SDDM 修复

在 `~/nixos-config/modules/desktop.nix` 中为 Qt6 SDDM 包增加兼容包装：

```text
sddm-greeter -> sddm-greeter-qt6
```

原因是当前 NixOS/Qt6 SDDM wrapper 原本只提供 `sddm-greeter-qt6`，但 SDDM
对自定义主题的兼容检查仍检查旧名称 `sddm-greeter`。这会让任何自定义主题
回退到默认主题，并产生：

```text
requires missing .../sddm-greeter
Using fallback theme
```

补丁已经经过构建并切换到系统 generation 41。重启 SDDM 后验证结果为：

```text
Loading theme configuration from .../shizuka/theme.conf
Greeter starting...
```

且不再出现 fallback；运行中的 greeter 命令为补丁后的
`.../sddm-wrapped/bin/sddm-greeter`，实际仍使用 Qt6 greeter。

### 进一步避免复发

NixOS 配置中已有的 Shell reload guard 也应保留：锁屏期间禁止本地插件 watcher
拆除并重建锁屏服务。以后如果修改锁屏插件，顺序应是：

1. 先确认 `omarchy-shell lock status` 的 `secure=false`；
2. 暂停 idle lock；
3. 修改并静态检查 QML；
4. 重新登录一个全新的图形 session；
5. 先手动锁定/解锁一次，再恢复 idle lock。

不要在 `secure=true`、显示器 `solitaryBlockedBy` 包含 `LOCK` 或日志出现
`placeholder screen` 时执行插件热重载。

## 2026-09-06 再次复发：空屏幕与残留 LOCK 的完整现场

这次现场是在用户正在修改配置时复现的。SDDM 日志在复现前后都明确加载了：

```text
Loading theme configuration from .../share/sddm/themes/shizuka/theme.conf
Greeter starting...
```

所以这一次可以排除 Shizuka 登录主题作为直接原因。真正的错误顺序是：

```text
17:02:34  iamcheyan.clipboard: TypeError: Cannot read property 'screen' of null
17:02:34  There are no outputs - creating placeholder screen
17:02:34  Layershell screen does not correspond to a real screen
17:02:34  Not creating lock surface ... not backed by a valid Wayland output
17:02:35  Could not create EGL surface / eglSwapBuffers failed
17:02:35  The Wayland connection experienced a fatal error: Invalid argument
17:02:35  Omarchy shell exited with status 255; relaunching.
```

其中 `iamcheyan.clipboard/ClipboardPanel.qml` 原本直接访问：

```qml
root.anchorItem.QsWindow.window.screen
```

但在显示输出或窗口对象短暂消失时，`QsWindow.window` 可以是空值。修复后会先
安全判断窗口和屏幕是否存在，并且只有在屏幕有名称、宽高有效时才显示剪贴板
layershell；无输出期间不会再把 placeholder screen 交给 Wayland。

随后检查到 Hyprland 仍报告：

```json
{"solitaryBlockedBy":["LOCK","WINDOWED","CANDIDATE"]}
```

这说明旧的 `ext-session-lock` 已经残留在 compositor 中。新 Quickshell 虽然正确
拒绝了第二把锁，但旧锁本身不能由新客户端释放，因此屏幕仍然是黑的。最后通过
优雅退出当前 Hyprland 图形会话，让 SDDM 重新创建会话，才清掉这个 compositor
级别的残留锁；没有重启机器，也没有修改 Shizuka 主题。

### 本次最终修复

- 保留 `iamcheyan.lock-screen` 和用户自定义锁屏界面；不改回默认主题。
- 给 `iamcheyan.clipboard/ClipboardPanel.qml` 增加空窗口、空屏幕和无效屏幕保护。
- 保留 `Service.qml` 的 stranded-lock 二次加锁阻断，避免 shell 重启后反复申请
  第二把 `WlSessionLock`。
- 保留 `desktop.nix` 的 SDDM Qt6 兼容别名，确保 Shizuka 不回退。
- 释放残留 LOCK 后，SDDM 已重新加载 Shizuka；下一次登录需要再验证一次锁定、
  解锁和 idle timeout。

### 以后如何避免

1. 修改锁屏、剪贴板或任何会创建 `PanelWindow`/`WlSessionLock` 的插件前，先确认
   `omarchy-shell lock status` 显示 `locked=false`、`secure=false`。
2. 先执行静态检查，再重载 shell；不要在 `secure=true` 或 `solitaryBlockedBy`
   含 `LOCK` 时热重载。
3. 若出现 `There are no outputs`、`placeholder screen` 或 Wayland fatal，先停止
   继续改 QML；检查 `hyprctl -j monitors` 和日志，必要时优雅退出图形会话清掉
   残留锁。
4. 每次修改后按“手动锁定 → 输入密码解锁 → 等待 idle timeout → 再解锁”的顺序
   验证，不要只验证 SDDM 登录画面。

## 2026-09-06 18:34 的复发：确认是 blank timer 关闭输出

这一次的时间间隔给出了决定性证据：

```text
18:34:52  lock-requested / secure=true
18:35:35  There are no outputs - creating placeholder screen
18:35:36  Could not create EGL surface
18:35:36  Wayland connection experienced a fatal error
```

锁屏配置的 `blankDelaySeconds` 是 30 秒，锁定后约 43 秒发生输出消失。
`Service.qml` 的 `runBlank()` 原先会运行：

```text
omarchy-brightness-keyboard off
omarchy-brightness-display off
```

在这台机器上，关闭唯一的 `HDMI-A-2` 输出会让 Quickshell/Qt Wayland 看到
placeholder screen；自定义锁屏的 `WlSessionLockSurface` 随后失去真实输出，
EGL 创建失败并导致 shell 崩溃。现在 `runBlank()` 改为记录
`blank-skipped: keep-output-alive`，不再关闭物理 DPMS，锁屏画面仍然使用用户的
自定义主题显示。

同时，剪贴板插件的屏幕保护改为使用独立的 `targetScreen` 属性，避免把
`visible` 绑定到 `PanelWindow.screen` 本身而产生 QML binding loop。
