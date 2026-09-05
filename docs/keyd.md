# MINILA-R keyd 键位配置与扩展指南

MINILA-R Convertible 的系统级键位映射由 `modules/keyd.nix` 声明。所有主机复用同一份配置。NixOS 负责安装 keyd、生成配置、启用服务以及在配置变化后重启服务。

设备 ID 是 `0c45:22b8`。配置只匹配这个设备，不影响其他键盘。

## 配置边界：改哪里

这套快捷键分成两层，必须按职责修改：

| 内容 | 修改位置 | 作用 |
|---|---|---|
| 物理键、独立层、按键输出 | `~/nixos-config/modules/keyd.nix` | 把 MINILA-R 硬件事件转换成普通按键或组合键 |
| 桌面动作、程序命令 | `~/chezmoi/dot_config/hypr/bindings.lua` | 把按键绑定到 Omarchy/Hyprland 功能 |
| 生成结果 | `/etc/keyd/minila-r.conf` | 只读检查，禁止直接编辑 |
| 部署后的 Hyprland 配置 | `~/.config/hypr/bindings.lua` | 由 chezmoi 管理，禁止直接编辑 |

keyd 不应该直接执行截图、启动程序或修改桌面状态。它只负责键盘输入转换；需要执行命令时，在 chezmoi 的 Hyprland 绑定中完成。

## 当前完整映射

| MINILA-R 物理键 | keyd 输出 | 最终用途 |
|---|---|---|
| 左 Alt | 左 Meta | 左 Alt/左 Meta 互换 |
| 左 Meta | 左 Alt | 左 Alt/左 Meta 互换 |
| Muhenkan | 激活 `muhenkan` 层 | 独立的快捷键层 |
| Muhenkan + `V` | `Ctrl + Super + V` | Omarchy 剪贴板 |
| Muhenkan + `S` | `Print` | Omarchy 原生智能/区域截图 |
| Shift + Muhenkan + `S` | `Ctrl + Shift + Print` | 直接全屏截图并弹出 Omarchy 通知 |
| 片假名/平假名 | 左方向键 | 光标向左 |
| Delete | 右方向键 | 光标向右 |
| 右 Ctrl | 上方向键 | 光标向上 |
| 右 Alt | 下方向键 | 光标向下 |
| Grave | Escape | 交换行为 |
| Escape | Grave | 交换行为 |
| 左 Ctrl | `overload(control, f24)` | 长按是 Ctrl，单按是 F24 |

## Muhenkan 独立层

`modules/keyd.nix` 中的核心结构如下：

```ini
[main]
muhenkan = layer(muhenkan)

[muhenkan]
v = C-M-v
s = print

[muhenkan+shift]
s = C-S-print
```

按住 Muhenkan 时，keyd 在 `muhenkan` 层查找按键；如果同时按住 Shift，则优先使用 `muhenkan+shift` 层。左 Ctrl、右 Ctrl、Alt 和 Super 不会被混入这个独立层。

### 为什么截图使用 Print 和组合键

`Muhenkan + S` 直接输出真实的 `Print`，因此可以复用 Omarchy 原生的智能截图流程，不需要 F13/F14 中转。

`Shift + Muhenkan + S` 输出 `Ctrl + Shift + Print`，这是一个不会覆盖普通 `Shift + Print` 的专用组合键。它在 chezmoi 中绑定为：

```lua
o.bind(
  "CTRL + SHIFT + PRINT",
  "MINILA-R direct fullscreen screenshot",
  "omarchy-capture-screenshot fullscreen slurp"
)
```

`fullscreen slurp` 会固定截取整个屏幕，但沿用 Omarchy 原生的保存、剪贴板、缩略图通知和截图编辑入口。普通 `Shift + Print` 仍保留原来的延迟截图功能。

## 以后如何增加快捷键

### 方案一：复用已有桌面快捷键

如果目标功能已经有系统快捷键，优先让 keyd 输出真实按键。例如新增 `Muhenkan + T`，让它执行已有的 `Super + T`：

```nix
settings.muhenkan = {
  v = "C-M-v";
  s = "print";
  t = "M-t";
};
```

这里的 `M` 是 Meta/Super，`C` 是 Control，`S` 是 Shift，`G` 是 AltGr。keyd 的组合键写法使用连字符，例如 `C-M-v`、`C-S-print`。

### 方案二：绑定一个新的桌面命令

如果目标是启动程序、截图、录音或调用 Omarchy 命令，则分两步：

1. 在 `modules/keyd.nix` 中选择一个不会冲突的真实按键或组合键作为输出。
2. 在 `~/chezmoi/dot_config/hypr/bindings.lua` 中绑定这个输出并执行命令。

例如：

```nix
# ~/nixos-config/modules/keyd.nix
settings.muhenkan = {
  t = "C-S-t";
};
```

```lua
-- ~/chezmoi/dot_config/hypr/bindings.lua
hl.unbind("CTRL + SHIFT + T")
o.bind("CTRL + SHIFT + T", "MINILA-R terminal action", "your-command")
```

不要把 shell 命令写进 keyd 的 `settings`。keyd 的职责是发出按键，Hyprland 才是执行桌面命令的位置。

### 选择输出键时的规则

- 优先使用目标功能已有的真实快捷键。
- 没有现成快捷键时，使用不冲突的组合键，例如 `C-S-<key>`。
- 先检查 `omarchy menu keybindings --print` 和 `hyprctl binds -j`。
- 不要随意使用 F13/F14；它们曾经是旧方案的中转键，当前截图配置不再使用。
- 不要覆盖普通 `Print`、`Shift + Print`、`Super + Print` 等 Omarchy 原生功能，除非确实要改变它们的全局行为。
- 不要直接修改 `/etc/keyd/minila-r.conf` 或 `~/.config/hypr/bindings.lua`。

## 修改、应用和验证

### 修改 keyd 层

```bash
cd ~/nixos-config
nix flake check --no-build
sudo nixos-rebuild switch --flake .#hx90
```

NixOS 会生成 `/etc/keyd/minila-r.conf` 并重启 keyd。配置修改在重建前不会可靠地进入系统；不要只修改生成文件。

### 修改 Hyprland 动作

```bash
cd ~/chezmoi
chezmoi apply
hyprctl reload
```

如果只修改了 Hyprland 源文件，也可以使用 `chezmoi apply ~/.config/hypr/bindings.lua`。

### 检查顺序

```bash
systemctl status keyd
sudo keyd check /etc/keyd/minila-r.conf
sed -n '1,160p' /etc/keyd/minila-r.conf
omarchy menu keybindings --print
hyprctl binds -j
```

要观察实际输出事件：

```bash
sudo keyd monitor
```

本配置应看到：

- `Muhenkan + S`：`print down` / `print up`；
- `Shift + Muhenkan + S`：`leftshift`、`leftcontrol`、`print` 依次按下并释放；
- `Muhenkan + V`：`leftcontrol`、`leftmeta`、`v` 组合事件。

`keyd monitor` 会同时显示原始键盘和 `keyd virtual keyboard`。判断最终效果时关注虚拟键盘输出；判断物理按键名称时关注 `MINILA-R Convertible` 设备。

### 截图验证

```bash
find ~/图片 -maxdepth 1 -name 'screenshot-*.png' -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' | sort | tail
```

`Shift + Muhenkan + S` 成功后应生成全屏 PNG，并弹出 Omarchy 的 “Screenshot saved to clipboard and file” 通知。

## 常见问题

| 现象 | 排查方向 |
|---|---|
| 修改完全没有效果 | 确认修改的是 `nixos-config` 源文件，并完成 `nixos-rebuild switch` |
| keyd 配置语法错误 | 运行 `sudo keyd check /etc/keyd/minila-r.conf` |
| keyd 有输出但桌面没动作 | 检查 `hyprctl binds -j` 是否存在对应组合键 |
| 全屏截图没有选择框 | 这是正确行为；`fullscreen` 模式直接截取全屏 |
| 全屏截图没有明显反馈 | 使用 `slurp` 处理模式，它会复用 Omarchy 原生通知和剪贴板流程 |
| 普通 `Shift + Print` 被影响 | 检查是否错误地重绑定了 `SHIFT + PRINT`；当前专用绑定是 `CTRL + SHIFT + PRINT` |
| keyd 监听到了但 Hyprland 不识别 | 检查 keyd 输出顺序和 `hyprctl binds -j` 的 `modmask`，不要只看物理设备事件 |
