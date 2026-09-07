# AeroSpace 虚拟工作区配置与操作指南

本目录包含了基于 [AeroSpace](https://github.com/nikitabobko/AeroSpace) 的 macOS 虚拟工作区（Virtual Workspaces）核心配置与高级扩展指南。

---

## 1. 架构与设计原则

* **纯浮动工作区模式 (Pure Floating Mode)**：
  * 全局禁用了自动平铺（Tiling），保留 macOS 原生自由拖拽、缩放窗口的浮动习惯。
  * 仅利用 AeroSpace 强大的**虚拟工作区树**与**内存隐藏/唤醒机制**，实现类似 Linux i3 / Hyprland 的多桌面切换体验。
* **彻底解决 macOS 原生 Spaces 缺陷**：
  * **零动画瞬间切换**（1~5ms 瞬时换帧，无任何左右滑动延迟）；
  * **窗口绝对不跟随**（切工作区时，当前窗口 100% 留在原地，绝不跟随跨工作区）；
  * **前台应用切 Tab 屏蔽**（`Cmd+1~9` 不会触发浏览器/编辑器的标签页切换）；
  * **完全无需禁用 SIP**（基于官方 Accessibility API，系统升级稳定）。

---

## 2. 快捷键速查表 (Cheat Sheet)

### (1) 跨工作区切换与窗口传送
| 快捷键 | 对应操作 | 行为说明 |
|---|---|---|
| **`Cmd + 1 ~ 9`** | `workspace 1 ~ 9` | **秒切工作区 1 ~ 9**（当前程序绝不跟随，前台应用不切 Tab） |
| **`Option(Alt) + \``** | `workspace-back-and-forth` | **在“最近使用的工作区”与“当前工作区”之间来回闪切** |
| **`Cmd + Shift + 1 ~ 9`** | `move-node-to-workspace N --focus-follows-window` | **将当前窗口发送到工作区 N**（并跟随切换过去） |
| **`Cmd + Ctrl + 1 ~ 9`** | `move-node-to-workspace N` | **静默将当前窗口发送到工作区 N**（自己留在原地） |

### (2) 窗口状态与焦点闪切
| 快捷键 | 对应模块 | 行为说明 |
|---|---|---|
| **`Option(Alt) + F`** | Hammerspoon 增强 | **切换窗口最大化 / 还原**（完美记忆原始坐标 X, Y 与尺寸，绝不跑偏到左上角） |
| **`Option(Alt) + Tab`** | AeroSpace | **在“当前窗口”与“上一个激活的窗口”之间瞬间来回闪切**（支持同工作区与跨工作区，如工作区 2 的 Kitty $\leftrightarrow$ 工作区 4 的 Telegram） |
| **`Option(Alt) + Shift + Tab`** | AeroSpace | **同上（窗口级 Back-and-Forth 闪切）** |

### (3) 配置重载
| 快捷键 | 功能 |
|---|---|
| **`Cmd + Shift + R`** | 重新加载 `aerospace.toml` 配置文件 |

---

## 3. 应用自动归位路由 (App Routing)

当前已配置的开机/启动自动归位规则：

| 应用程序类别 | 包含软件 | 自动归位目标 | 窗口模式 |
|---|---|---|---|
| **终端开发环境** | **Kitty** (`net.kovidgoyal.kitty`), **Alacritty** (`org.alacritty`) | **工作区 2** | 纯浮动 |
| **虚拟机与沙箱** | **UTM** (`com.utmapp.UTM`) | **工作区 3** | 纯浮动 |
| **社交通讯软件** | **Telegram** (`ru.keepcoder.Telegram`), **WeChat 微信** (`com.tencent.xinWeChat`), **QQ** (`com.tencent.qq`), **Discord** (`com.hnc.Discord`) | **工作区 4** | 纯浮动 |
| **其他常规应用** | 浏览器、编辑器、音乐等 | 当前激活工作区 | 纯浮动 |

---

## 4. 文件清单与部署目标

| 源文件 (nixos-config) | 部署目标 | 说明 |
|---|---|---|
| `modules/home-manager/darwin-files/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` | AeroSpace 主配置文件 |
| `modules/home-manager/darwin-files/aerospace/README.md` | 本文件 | 模块说明、快捷键与高级玩法手册 |

---

## 5. 常用维护命令

```bash
# 检查配置语法是否正确
aerospace reload-config --dry-run

# 立即应用并重新加载配置
aerospace reload-config

# 查看当前所有工作区与窗口分布
aerospace list-workspaces --all
aerospace list-windows --all
```
