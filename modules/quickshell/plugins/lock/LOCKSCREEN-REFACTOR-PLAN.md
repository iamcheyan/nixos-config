# 自定义锁屏精简改造方案

本文档用于把 `iamcheyan.lock-screen` 收敛为：

> 原生锁屏服务 + 自定义视觉界面。

目标是保留模糊壁纸、头像、时间、日期和密码登录，同时移除网络、电池、
指纹按钮、截图、休眠、额外屏幕管理和自定义锁状态机，降低 Quickshell/Wayland
锁屏崩溃的概率。

## 一、最终目标

锁屏只负责显示和登录：

- 模糊的当前壁纸；
- 屏幕下方的头像、用户名和登录区域；
- 时间；
- 日期；
- 用户名；
- 点击或按键后显示密码输入框；
- 密码提交、失败提示和解锁。

锁屏服务继续使用原生实现：

- `WlSessionLock`；
- PAM 密码认证；
- 原生锁定/解锁生命周期；
- 原生焦点处理；
- 原生 idle lock 调用；
- 原生会话锁安全行为。

## 二、明确删除的功能

从自定义 `LockView.qml` 中删除：

- 网络图标和网络状态；
- 电池百分比和充电状态；
- 指纹按钮及指纹提示；
- 截图按钮；
- 睡眠按钮；
- 休眠按钮；
- `UPower`；
- `Quickshell.Networking`；
- `busctl CanHibernate` 检查；
- 自定义鼠标区域和复杂按键分发；
- 不必要的额外 `Timer`、`Process` 和外部命令。

从自定义 `Service.qml` 中删除或恢复为原生实现的内容：

- 自定义 stranded-lock 恢复状态机；
- 自定义 lock preflight；
- 自定义二次锁请求队列；
- 自定义无限重试；
- 自定义屏幕检测和锁屏恢复逻辑；
- 在锁屏后关闭唯一 HDMI 输出的 DPMS 行为。

特别注意：不要在锁屏期间执行：

```text
omarchy-brightness-display off
```

这台机器只有一个实际使用中的 HDMI 输出。关闭它后，Qt/Wayland 会看到
placeholder screen，锁屏 surface 可能失去真实输出并导致 Quickshell 崩溃。

## 三、推荐文件结构

最终插件目录建议只保留必要内容：

```text
iamcheyan.lock-screen/
├── manifest.json
├── Service.qml       # 尽量与原生 omarchy.lock 保持一致
├── LockView.qml      # 唯一的主要自定义文件
├── README.md
└── preview.png
```

`Service.qml` 应以当前系统里的原生文件为基准：

```text
/nix/store/iasz6brar7ixfvy88qcwk4cq1z1kj0wp-nixarchy-omarchy-tree/shell/plugins/lock/Service.qml
```

这个 Nix store 路径会随系统更新变化，实际操作时先通过下面命令找当前路径：

```bash
omarchy-shell --help 2>/dev/null || true
readlink -f /run/current-system/sw/bin/omarchy-shell
```

也可以从当前 shell 日志里找到 `nixarchy-omarchy-tree/shell` 路径。

不要直接编辑 `/nix/store` 中的文件。应当把原生 `Service.qml` 复制到插件目录，
然后只做极少数必要修改。

## 四、改造顺序

### 第 1 步：保存现状

先在插件目录执行：

```bash
cd ~/.config/omarchy/plugins/iamcheyan.lock-screen
git status --short
cp Service.qml Service.qml.before-minimal-refactor
cp LockView.qml LockView.qml.before-minimal-refactor
cp manifest.json manifest.json.before-minimal-refactor
```

同时备份 shell 配置：

```bash
cp ~/.config/omarchy/shell.json ~/.config/omarchy/shell.json.before-minimal-lock
cp ~/.config/omarchy/lock-screen.json ~/.config/omarchy/lock-screen.json.before-minimal-lock
```

### 第 2 步：先恢复原生 Service

把原生 `Service.qml` 作为新版本的基线。只保留以下必要调整：

- `LockView` 指向插件目录里的自定义 `LockView.qml`；
- 如果确实需要，保留自定义背景路径；
- 不加入新的 `WlSessionLock`；
- 不加入新的 `PanelWindow`；
- 不加入额外锁状态机。

如果需要修改 blank 行为，优先让 blank timer 只记录日志，不关闭 DPMS：

```qml
function runBlank() {
  logEvent("blank-skipped: keep-output-alive")
}
```

不要删除原生的 PAM、`WlSessionLock`、`sessionLock` 或解锁处理。

### 第 3 步：重写为精简 LockView

自定义 `LockView.qml` 只保留以下输入属性和信号：

```qml
property string backgroundPath: ""
property int backgroundVersion: 0
property bool fingerprintConfigured: false
property bool authenticatingPassword: false
property string failureMessage: ""
property int failedAttempts: 0
property bool inputEnabled: true
property bool loadBackground: true
property string passwordText: ""

signal submitPassword(string password)
signal passwordTextEdited(string password)
signal clearFailureRequested()
signal wakeRequested()
```

界面只需要：

1. 一个背景 `Image`；
2. 一个背景模糊效果；
3. 一个头像 `Image`；
4. 时间和日期 `Text`；
5. 用户名 `Text`；
6. 一个密码输入框；
7. 一个错误提示 `Text`。

建议先使用较保守的模糊效果：

```qml
MultiEffect {
  anchors.fill: parent
  source: background
  blurEnabled: background.status === Image.Ready
  blur: 1.0
  blurMax: 32
}
```

壁纸加载失败时必须仍然显示背景色，不要让空图片阻塞整个界面：

```qml
Rectangle {
  anchors.fill: parent
  color: "#101014"
}
```

头像建议准备回退路径：

```text
/var/lib/AccountsService/icons/<user>
~/.face
~/.face.icon
默认图标或文字图标
```

头像全部失败时，显示固定的文字或图标，不能让头像加载失败影响密码输入。

### 第 4 步：先不做复杂美化

第一次改造完成后，不要立即加回网络、电池、按钮、动画和额外特效。

先只验证：

- 锁屏能出现；
- 时间和日期显示；
- 头像失败时仍能输入密码；
- 密码错误时仍能继续输入；
- 密码正确时能解锁；
- 锁屏超过 30 秒仍保持稳定；
- shell 日志没有 `placeholder screen`、`EGL` 或 `fatal error`。

## 五、验证流程

每次修改后执行：

```bash
git diff --check
omarchy-shell lock status
```

锁屏前应看到：

```json
{
  "locked": false,
  "secure": false,
  "realScreens": 1
}
```

然后按这个顺序测试：

1. 手动锁屏；
2. 等待 10 秒；
3. 解锁；
4. 再次手动锁屏；
5. 等待超过 `blankDelaySeconds`；
6. 确认界面仍存在且没有黑屏；
7. 输入密码解锁；
8. 等待 idle timeout 自动锁屏；
9. 再次解锁。

日志检查：

```bash
journalctl --user --since "10 minutes ago" --no-pager \
  | rg -i "omarchy lock|placeholder|no outputs|EGL|fatal|Wayland|TypeError"
```

正常情况下不应出现：

```text
There are no outputs - creating placeholder screen
Could not create EGL surface
eglSwapBuffers failed
The Wayland connection experienced a fatal error
TypeError: Cannot read property 'screen' of null
```

## 六、出现问题时的恢复方法

如果只是锁屏界面异常，但 SSH 仍然可用：

```bash
omarchy-shell lock status
hyprctl -j monitors | jq '.[] | {name, dpmsStatus, solitaryBlockedBy}'
```

如果 `solitaryBlockedBy` 中出现 `LOCK`，不要继续热重载插件。先保存日志，必要时
优雅退出当前图形会话，让 SDDM 重新建立会话并清除 compositor 中的残留锁：

```bash
omarchy-system-logout
```

这个操作会结束当前图形会话，未保存的图形应用状态可能丢失，但不会删除配置文件。

如果新版本仍然不稳定，恢复备份：

```bash
cd ~/.config/omarchy/plugins/iamcheyan.lock-screen
cp Service.qml.before-minimal-refactor Service.qml
cp LockView.qml.before-minimal-refactor LockView.qml
```

然后重新启动一个全新的图形会话。不要在旧的 `LOCK` 残留状态下反复热重载。

## 七、长期维护原则

- 原生 `Service.qml` 更新时，重新对比并同步，不要长期维护一份大幅分叉的副本；
- 自定义逻辑尽量放在 `LockView.qml` 的视觉层；
- 所有外部状态都应是可选的，失败时只影响一个视觉元素；
- 不在 LockView 中调用系统命令；
- 不在 LockView 中创建第二个 Wayland surface；
- 不在锁屏期间切换 DPMS；
- 每次升级 Quickshell、Hyprland 或 Omarchy 后，重新测试“锁屏超过 blank delay”；
- 如果只想改变颜色、间距、模糊程度和头像样式，只修改 LockView，不修改 Service。
