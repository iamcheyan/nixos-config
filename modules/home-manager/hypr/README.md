# Hyprland 动态平铺 Wayland 合成器配置

本目录包含了 Linux / Wayland 下 [Hyprland](https://hyprland.org/) 桌面环境的个人键位绑定与系统集成配置。

---

## 1. 核心模块与分离原则

* **键盘快捷键 (`bindings.lua`)**：
  * 管理日常窗口操作、语音输入开关（`F9` 绑定 `voxtype record toggle`）、截图命令等；
  * 由 post-apply 维护软链接，外部修改可在 apply 时同步回源文件。
* **硬件显示器解耦 (`monitors.lua`)**：
  * 本地独占，已被 `.chezmoiignore` 忽略，避免不同机器的多显示器分辨率与缩放比例冲突。
* **光标与输入规范**：统一指定经典黑色 `Adwaita`（24px）光标。

---

## 2. 文件清单与部署

| 源文件 (chezmoi) | 部署目标 | 说明 |
|---|---|---|
| `dot_config/hypr/bindings.lua` | `~/.config/hypr/bindings.lua` | 快捷键与绑定配置 |
| `dot_config/hypr/README.md` | 本文件 | 模块说明 |

