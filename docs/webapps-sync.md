# 跨平台 WebApps 双向同步系统设计与使用指南

本系统用于在 **macOS (Safari Web Apps)** 与 **Linux (Firefox 独立 Web 容器)** 之间建立全自动的双向同步中转站。无论你在哪一端新增了网页应用，均可通过中转站无缝同步至另一端，享受各自操作系统原生级的桌面体验。

---

## 1. 架构与边界划分

按照本仓库三层配置体系的规范：

| 层级 | 所在位置 | 职责说明 |
|---|---|---|
| **公开工具层** (`dotfiles`) | `~/dotfiles/scripts/sync-webapps.py` (软链接至 `~/.local/bin/sync-webapps`) | 跨平台同步核心脚本，零外部依赖（纯 Python 3 标准库）。 |
| **私人数据层** (`chezmoi`) | `~/.local/share/webapps/` (`webapps.json` & `icons/`) | 统一中转清单库与高清 PNG 图标，通过 chezmoi 实现跨设备 Git 同步。 |
| **系统配置层** (`nixos-config`) | `modules/cli.nix` / `modules/workstation.nix` / `modules/darwin/` | 提供 Python 3 运行时、Firefox 浏览器环境与系统级应用菜单集成。 |

---

## 2. 底层实现原理

### 2.1 macOS 侧：Safari Web App 的内部机制
在 macOS (Sonoma 及后续版本) 中，Safari 的“添加到程序坞”功能并非简单的 URL 快捷方式，而是生成了一个符合 macOS 规范的独立 App Bundle：
1. **存放路径**：`~/Applications/<应用名>.app`。
2. **核心元数据 (`Contents/Info.plist`)**：
   - `LSTemplateApplication = true`：声明该应用为系统模版应用。
   - `LSTemplateApplicationParameters`：指定宿主为 `com.apple.Safari.WebApp`，由系统 LaunchServices 直接拉起 WebKit 独立渲染进程。
   - `Manifest.start_url` / `WKManifestURL`：记录网页入口 URL。
   - `Manifest.theme_color` / `background_color`：主题配色。
3. **应用图标**：存放在 `Contents/Resources/ApplicationIcon.icns`。
4. **会话隔离**：Safari Web App 具有完全独立的 Cookies、LocalStorage 与网络沙盒，不与 Safari 主浏览器共享标签页。

### 2.2 Linux 侧：Firefox 独立 Web 容器与 XDG 规范
在 Linux (NixOS / Hyprland / KDE) 环境下，Web 应用遵循 FreeDesktop / XDG 桌面标准：
1. **桌面入口 (`~/.local/share/applications/webapp-<id>.desktop`)**：
   ```ini
   [Desktop Entry]
   Version=1.0
   Type=Application
   Name=ChatGPT
   Comment=Web App (ChatGPT)
   Exec=firefox --new-window "https://chatgpt.com/"
   Icon=/home/tetsuya/.local/share/icons/hicolor/512x512/apps/webapp-chatgpt.png
   Terminal=false
   StartupWMClass=webapp-chatgpt
   Categories=Network;WebBrowser;
   ```
2. **多任务与图标隔离**：
   - 通过 `StartupWMClass=webapp-<id>`，让窗口管理器与任务切换栏将其识别为独立的应用程序，而非普通 Firefox 标签页。
   - 图标统一放置在 `~/.local/share/icons/hicolor/512x512/apps/` 或引用中转图标库。

---

## 3. 中转数据库规范 (`webapps.json`)

中转数据默认存放于 `~/.local/share/webapps/`：

```text
~/.local/share/webapps/
├── webapps.json          # 核心清单数据库
└── icons/                # 高清 PNG 图标库 (512x512)
    ├── chatgpt.png
    ├── xiaohongshu.png
    └── ...
```

### `webapps.json` 数据结构示例
```json
[
  {
    "id": "chatgpt",
    "name": "ChatGPT",
    "url": "https://chatgpt.com/",
    "icon": "chatgpt.png",
    "theme_color": "#000000",
    "background_color": "#ffffff"
  },
  {
    "id": "xiaohongshu",
    "name": "小红书",
    "url": "https://www.xiaohongshu.com/explore?m_source=pwa",
    "icon": "xiaohongshu.png",
    "theme_color": null,
    "background_color": null
  }
]
```

---

## 4. 双向同步流程

```
              ┌──────────────────────────────────────────────┐
              │           中转清单库 (chezmoi)                │
              │  ~/.local/share/webapps/webapps.json         │
              │  ~/.local/share/webapps/icons/*.png          │
              └──────────────┬────────────────┬──────────────┘
                             ▲                ▲
                扫描/生成    │                │    生成/添加
                             ▼                ▼
       ┌───────────────────────────┐    ┌───────────────────────────┐
       │      macOS (Safari)       │    │       Linux (Firefox)     │
       │  ~/Applications/*.app     │    │  ~/.local/share/          │
       │  (Safari Web App Bundle)  │    │  applications/*.desktop   │
       └───────────────────────────┘    └───────────────────────────┘
```

### 流程 A：Mac $\rightarrow$ Linux（Mac 新增 Safari Web App）
1. 用户在 Safari 点击「文件 $\rightarrow$ 添加到程序坞」。
2. 运行 `sync-webapps`：
   - 扫描 `~/Applications/*.app` 中所有带有 `com.apple.Safari.WebApp` 标记的应用。
   - 读取 `Info.plist` 中的应用名称和起始 URL。
   - 调用系统命令 `sips -s format png` 将 `ApplicationIcon.icns` 无损提取为 `icons/<id>.png`。
   - 将新记录与更新合并保存至 `webapps.json`。
3. Linux 侧通过 chezmoi 同步后，运行 `sync-webapps`：
   - 自动生成对应 Linux `.desktop` 入口和图标。
   - 刷新系统应用菜单数据库 (`update-desktop-database`)。

### 流程 B：Linux $\rightarrow$ Mac（Linux 端新增 Web App）
1. 在 Linux 终端执行：
   ```bash
   sync-webapps add "DeepSeek" "https://chat.deepseek.com/"
   ```
2. Linux 本地即刻生成 `.desktop` 启动器并写入 `webapps.json`。
3. Mac 侧通过 chezmoi 同步后，运行 `sync-webapps`：
   - 脚本检测到本地缺失 `DeepSeek.app`。
   - 自动创建 `~/Applications/DeepSeek.app` 的目录结构与 `Info.plist`。
   - 调用 `sips` 与 `iconutil` 将 PNG 图标编译为 `.icns` 图标。
   - 执行 ad-hoc 签名 (`codesign --force --deep --sign -`) 并通知 LaunchServices 注册。
   - macOS Launchpad 和 Dock 即刻出现原生 Safari Web App。

---

## 5. 命令参考手册

| 命令 | 说明 |
|---|---|
| `sync-webapps` 或 `sync-webapps sync` | 执行双向同步（扫描本地环境、更新清单、生成缺失应用）。 |
| `sync-webapps list` | 查看当前已收录的所有 Web App 清单及图标状态。 |
| `sync-webapps add <名称> <URL> [--icon <PNG路径>]` | 手动注册一个新的 Web App。 |

### 使用示例

1. **查看当前所有已收录的 Web App**：
   ```bash
   sync-webapps list
   ```

2. **手动添加一个新的 Web App**：
   ```bash
   sync-webapps add "V2EX" "https://www.v2ex.com/" --icon ~/Downloads/v2ex.png
   ```

3. **双向同步并刷新**：
   ```bash
   sync-webapps
   ```

---

## 6. 注意事项与常见问题

### 6.1 macOS 权限与应用签名
- 自动生成的 `.app` 包含 `LSTemplateApplication` 标识，必须通过 `codesign --force --deep --sign -` 进行本机构建签名，否则 macOS Gatekeeper 会阻止其运行。脚本已内置自动签名处理。

### 6.2 chezmoi 数据同步建议
- 建议将 `~/.local/share/webapps` 纳入 `chezmoi` 管理：
  ```bash
  chezmoi add ~/.local/share/webapps
  ```
- 这样每次新增或扫描后，只需正常的 `chezmoi git commit / push`，所有连接的主机均可无缝拉取。

### 6.3 登录态与 Cookie
- **macOS (Safari)**：每个 Web App 拥有完全独立的沙盒存储（位于 `~/Library/Containers/`）。
- **Linux (Firefox)**：默认使用 Firefox 的主 Profile 独立窗口打开，共享 Firefox 的已有 Cookie 和登录状态；如需完全隔离 Cookie，可在脚本中扩展为 `-P "webapp-<id>"` 独立 Profile 模式。
