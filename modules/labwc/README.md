# Labwc 桌面会话配置与资产库 (modules/labwc)

本目录是本系统 **Labwc (Wayland 窗口管理器)** 桌面会话的声明式配置文件与辅助资产源码库。

由 [`modules/labwc.nix`](file:///home/tetsuya/nixos-config/modules/labwc.nix) 通过 Home Manager 统一分发并部署到用户的 `~/.config/` 和 `~/.local/` 标准路径中。

---

## 目录组织结构与分工

```text
modules/labwc/
├── labwc/                     # Labwc 核心配置文件与脚本
│   ├── rc.xml                 # 窗口管理器核心配置（快捷键、窗口规则、主题、平铺逻辑）
│   ├── menu.xml               # 桌面右键 Openbox 风格系统菜单
│   ├── environment            # Wayland 桌面全局环境变量
│   ├── environment.d/         # 环境变量片段（如 90-keyboard.env 键盘配置）
│   ├── keybinds/              # 快捷键预设配置片段
│   ├── scripts/               # Labwc 专属辅助与控制脚本
│   │   ├── set-wallpaper      # 桌面壁纸渲染与启动脚本（调用 swaybg）
│   │   ├── wallpaper          # Wofi 交互式壁纸选择器（检索 ~/wallpapers）
│   │   ├── reload             # Labwc 与 Quickshell 热重载脚本（带进程守护）
│   │   ├── quickshell         # Quickshell 顶栏与面板统一拉起入口
│   │   ├── quickshell-mode    # Quickshell 运行模式切换（dev/nix）
│   │   ├── system-menu        # 关机、重启、挂起、注销等系统电源控制
│   │   ├── audio              # 音量控制与快捷弹窗
│   │   ├── brightness         # 屏幕亮度调节脚本
│   │   ├── scale / scale-menu # 显示器缩放与 HiDPI 控制
│   │   ├── theme-switch       # 窗口与 GTK 主题切换
│   │   ├── gaps               # 窗口间隙动态微调
│   │   └── screenshot*        # 截屏与录屏辅助工具
│   └── themes/                # Labwc 窗口标题栏与边框装饰主题
│       ├── BL-Lithium-dark/   # 极简暗色边框主题
│       └── Adwaita-Labwc-dark/# GNOME Adwaita 风格暗色边框主题
├── wofi/                      # Wofi 应用程序启动器与交互弹窗
│   ├── app-launcher           # 应用搜索与启动器入口
│   ├── config / config-popos  # 布局参数与窗口大小定义
│   ├── style.css              # 主应用启动器 CSS 暗色美化样式
│   ├── cliphist.css           # 剪贴板历史搜索弹窗专用样式
│   ├── menu.css               # 快捷菜单弹窗样式
│   └── power-dialog.css       # 电源操作弹窗样式
├── cliphist/                  # Cliphist 剪贴板历史集成
│   ├── cliphist-wofi          # 基于 Wofi 的交互式剪贴板历史选择器 (Win+V)
│   ├── cliphist-fuzzel        # 基于 Fuzzel 的极简剪贴板选择器
│   └── config                 # 剪贴板守护参数
├── mako/                      # Mako 通知守护进程配置
│   └── config                 # 桌面通知样式（圆角、透明度、超时与颜色）
├── fuzzel/                    # Fuzzel 极简启动器配置
│   └── fuzzel.ini             # 备用极速启动器配色与字体
```

---

## 部署映射关系 (Deployment Map)

在 [`modules/labwc.nix`](file:///home/tetsuya/nixos-config/modules/labwc.nix) 中，通过 Home Manager 声明式建立如下映射：

| 仓库源码路径 (`modules/labwc/`) | 用户家目录目标路径 | 部署性质 |
|---|---|---|
| `labwc/rc.xml` | `~/.config/labwc/rc.xml` | 声明式只读链接 |
| `labwc/menu.xml` | `~/.config/labwc/menu.xml` | 声明式只读链接 |
| `labwc/environment` | `~/.config/labwc/environment` | 声明式只读链接 |
| `labwc/environment.d/` | `~/.config/labwc/environment.d/` | 声明式只读链接 |
| `labwc/keybinds/` | `~/.config/labwc/keybinds/` | 声明式只读链接 |
| `labwc/scripts/` | `~/.config/labwc/scripts/` | 声明式可执行链接目录 |
| `labwc/scripts/quickshell-mode`| `~/.local/bin/quickshell-mode` | 用户全局 CLI 工具 |
| `labwc/themes/*` | `~/.local/share/themes/*` | GTK/Labwc 主题目录 |
| `wofi/` | `~/.config/wofi/` | Wofi 样式与配置文件 |
| `cliphist/` | `~/.config/cliphist/` | 剪贴板工具配置 |
| `mako/config` | `~/.config/mako/config` | 通知守护进程配置 |
| `fuzzel/fuzzel.ini` | `~/.config/fuzzel/fuzzel.ini` | 轻量启动器配置 |

---

## 核心机制与协同工作原理

### 1. 桌面启动链 (Autostart Lifecycle)
1. Labwc 启动并读取 `rc.xml` 解析按键绑定与多显示器规则。
2. Labwc 执行 `~/.config/labwc/autostart`：
   - 导入 D-Bus / systemd 用户会话环境变量。
   - 启动壁纸渲染：执行 `~/.config/labwc/scripts/set-wallpaper wayland`，拉起 `swaybg` 常驻后台。
   - 启动状态栏：执行 `~/.config/labwc/scripts/quickshell`，拉起 Quickshell Top Bar。
   - 启动桌面守护程序：`swaync` (通知中心)、`nm-applet` (网络托盘)、`fcitx5` (输入法)、`cliphist` (剪贴板监听)。

### 2. 壁纸管理体系 (Wallpaper System)
- **壁纸存放目录**：`~/wallpapers/`（由用户自由存放常用壁纸图片）。
- **当前壁纸状态记录**：`~/.local/state/labwc/wallpaper`（记录当前选择的壁纸完整绝对路径）。
- **选壁纸操作**：通过桌面右键菜单或调用 `~/.config/labwc/scripts/wallpaper`，弹出 Wofi 图片列表，选择后自动将绝对路径持久化写入状态文件，并通过 `swaybg` 无缝切换背景。
- **开机/重载自愈**：`set-wallpaper` 优先读取状态文件中的壁纸，若不存在则自动扫描 `~/wallpapers/` 中的第一张图片作为兜底，无需在代码仓库中打包体积庞大的二进制图片。

### 3. 热重载机制 (Live Reload)
- 执行 `~/.config/labwc/scripts/reload`（或右键菜单中点击 **Reload Configuration**）：
  - 向 Labwc 进程发送 `SIGHUP` 信号，实时重新加载 `rc.xml` 和 `menu.xml`。
  - 通过 `disown` 保护重启 `swaybg` 壁纸和 `quickshell` 顶栏，避免进程在子 Shell 退出时被误杀。

---

## 修改与维护指南

1. **修改窗口规则或快捷键**：
   - 编辑 [`modules/labwc/labwc/rc.xml`](file:///home/tetsuya/nixos-config/modules/labwc/labwc/rc.xml)。
2. **修改桌面右键菜单**：
   - 编辑 [`modules/labwc/labwc/menu.xml`](file:///home/tetsuya/nixos-config/modules/labwc/labwc/menu.xml)。
3. **修改或增加辅助脚本**：
   - 在 [`modules/labwc/labwc/scripts/`](file:///home/tetsuya/nixos-config/modules/labwc/labwc/scripts/) 下添加或编辑。
4. **使修改生效**：
   ```bash
   cd ~/nixos-config
   git add modules/labwc
   sudo nixos-rebuild switch --impure --flake /home/tetsuya/nixos-config#hx90
   ```
