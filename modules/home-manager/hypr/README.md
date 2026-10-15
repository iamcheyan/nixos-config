# Hyprland 配置（inua shell）

本目录是 Hyprland 会话的 Lua 配置，由 Home Manager 部署到 `~/.config/hypr/`，
源文件在 `modules/home-manager/hypr/`。这个会话以 **inua** 作为桌面壳。

---

## 加载链

`hyprland.lua` 依次加载：

```text
dofile(~/.config/hypr/bootstrap.lua)   # 设置 package.path，使 require("hypr.*") 可解析
require("hypr.base.helpers")           # o.* 辅助函数（bind / window / exec_on_start…）
require("hypr.base.envs")              # Wayland / portal 环境变量
require("hypr.base.input")             # 输入默认值（布局、重复率、触控板）
require("hypr.base.windows")           # 窗口规则
require("hypr.base.looknfeel")         # 边框颜色、布局引擎、misc/cursor
require("hypr.monitors")               # 显示器（每机不同，个人维护）
require("hypr.input")                  # 个人输入覆盖（Nix 按 host 注入 kb_layout）
require("hypr.bindings")               # 个人键位
require("hypr.looknfeel")              # 个人外观覆盖（无间隙、无动画、不透明）
require("hypr.autostart")              # 会话启动项
pcall(require, "inua")                 # inua 的键位与层规则（~/.config/hypr/inua.lua）
```

`base/` 是从 Omarchy 的 `default.hypr.*` 移植过来的基础配置，因为 Hyprland 会话
不再加载 Omarchy —— 桌面壳已由 inua 提供。

---

## 两套桌面壳

| 会话 | 合成器 | 壳 | 配置来源 |
|---|---|---|---|
| Inua | Hyprland | inua | 本目录 + `~/.config/hypr/inua.lua` |
| Labwc | labwc-plus | Anchor Shell | `modules/labwc.nix` + `modules/anchor-shell/` |

inua 与 Anchor Shell 各自独立。`modules/packages/desktop-compat.nix` 只保留两个
会话共用的兼容层（历史 `omarchy-*` 辅助命令、主题目录、shell rc、xcompose、
字体、plymouth）；Omarchy 的 Quickshell 壳与其 Hyprland 配置层已移除。

---

## 文件清单

| 源文件 | 部署目标 | 说明 |
|---|---|---|
| `hyprland.lua` | `~/.config/hypr/hyprland.lua` | 入口，定义加载链 |
| `bootstrap.lua` | `~/.config/hypr/bootstrap.lua` | 设置 `package.path` |
| `base/*.lua` | `~/.config/hypr/base/*.lua` | 从 Omarchy 移植的基础配置 |
| `monitors.lua` | `~/.config/hypr/monitors.lua` | 显示器与缩放（个人维护） |
| `input.lua` | `~/.config/hypr/input.lua` | 个人输入覆盖（按 host 模板化） |
| `bindings.lua` | `~/.config/hypr/bindings.lua` | 个人键位 |
| `looknfeel.lua` | `~/.config/hypr/looknfeel.lua` | 个人外观覆盖 |
| `autostart.lua` | `~/.config/hypr/autostart.lua` | 会话启动项 |
| `hyprsunset.conf` | `~/.config/hypr/hyprsunset.conf` | 夜间色温 profile |
| `xdph.conf` | `~/.config/hypr/xdph.conf` | 屏幕共享选择器 |

光标的黑箭头 `Adwaita`（24px）在 `input.lua` 与 `base/envs.lua` 中统一设置。
