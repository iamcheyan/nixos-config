# Hammerspoon 桌面自动化与辅助配置

本目录包含了基于 [Hammerspoon](https://www.hammerspoon.org/) 的 macOS 辅助功能扩展配置。

---

## 1. 职责与增强功能

* **像素级记忆最大化/还原 (`Option + F`)**：
  * 完美记忆当前浮动窗口的屏幕原始坐标 `(X, Y)` 与大小 `(W, H)`；
  * 按一次将窗口铺满全屏，再次按下 **100% 像素级复原到之前的自定义位置与大小**（解决 AeroSpace 平铺模式重置到左上角的问题）。
* **IPC 桥接支持**：`hs.ipc` 支持终端命令行交互。

---

## 2. 快捷键速查

| 快捷键 | 功能 | 说明 |
|---|---|---|
| **`Option(Alt) + F`** | **窗口最大化 / 还原** | 记住原始 (X, Y) 坐标与尺寸，按第二次完美复原 |

---

## 3. 文件清单与部署目标

| 源文件 (nixos-config) | 部署目标 | 说明 |
|---|---|---|
| `modules/home-manager/darwin-files/hammerspoon/init.lua` | `~/.hammerspoon/init.lua` | Hammerspoon 启动脚本 |
| `modules/home-manager/darwin-files/hammerspoon/README.md` | 本文件 | 模块说明 |
