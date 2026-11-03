# Debian 远程桌面（Xfce）通过 noVNC 使用

本机（`debian.tailb4776a.ts.net`）上运行着一个 headless 的 **Xfce 会话**，通过
noVNC 流式传输到浏览器。启动器里有两个入口指向它：`Debian Desktop` 和
`webdesktop - noVNC`。

## 架构

```
┌─────────────┐    tailscale serve    ┌────────────────────────────┐
│   本机浏览器  │ ──> /xfce/vnc.html ──> │ websockify 127.0.0.1:6080  │
└─────────────┘                        └──────────────┬─────────────┘
                                                   │ unix socket
                                                   ▼
                                            Xvnc :20 (pid 1338)
                                                   │
                                                   ▼
                                         xfwm4 / xfce4-panel / xfdesktop
                                            (headless Xfce 桌面)
```

关键端口与进程：

| 端口 | 进程 | 用途 |
|------|------|------|
| `127.0.0.1:6080` | `websockify`（pid 1436） | noVNC 网页服务，对应 Xfce |
| `127.0.0.1:5900` | `Xvnc :20`（pid 1338） | 原生 VNC（Remmina/Screens 用） |
| `127.0.0.1:6082` | `websockify`（pid 88462） | **Inua Hyprland** 会话，不是 Xfce |
| `127.0.0.1:5901` | `wayvnc` | Inua Hyprland 的 VNC |

## Tailscale 路由

`tailscale serve status` 显示两条暴露的路由：

```
/debian.tailb4776a.ts.net
├── /        proxy http://127.0.0.1:80
├── /aoba    proxy http://127.0.0.1:8851
├── /xfce    proxy http://127.0.0.1:6080   ← Xfce 桌面
├── /magpie  proxy http://127.0.0.1:3426
└── /desktop proxy http://127.0.0.1:6082   ← Inua Hyprland
```

**注意：`/desktop` 不是 Xfce，是 Inua 所在的 Hyprland 会话。**

## 直接访问地址

```
https://debian.tailb4776a.ts.net/xfce/vnc.html?autoconnect=1&resize=scale
```

已验证：HTTP 200、WebSocket 升级 101、后端 `Xvnc :20` 存活。

## 启动器入口

两个入口文件，均已修正为 `/xfce/`：

- `~/.local/bin/vnc-debian` — 启动 Chromium，以 isolated profile 打开 noVNC
- `~/.local/share/applications/webapp-webdesktop-novnc.desktop` — Firefox 新窗口

对应的 `.desktop` 条目：

- `~/.local/share/applications/vncviewer.desktop` — Name: **Debian Desktop**
- `~/.local/share/applications/webapp-webdesktop-novnc.desktop` — Name: **webdesktop - noVNC**

## 服务管理

```sh
systemctl --user status webdesktop.service        # 查看状态
systemctl --user restart webdesktop.service       # 重启
systemctl --user stop webdesktop.service          # 停止
systemctl --user start webdesktop.service         # 启动
```

`webdesktop` 自带子命令：

```sh
~/.local/bin/webdesktop status   # 显示 display 号、pid、URL
~/.local/bin/webdesktop stop
~/.local/bin/webdesktop start
~/.local/bin/webdesktop logs     # tail 各组件日志
```

## 故障排查

| 症状 | 可能原因 | 处理 |
|------|----------|------|
| 页面 200 但黑屏 | `webdesktop.service` 未运行 | `systemctl --user restart webdesktop.service` |
| WebSocket 404 | 路由指向了 `/desktop`（Inua）而非 `/xfce` | 确认 URL 含 `/xfce/` |
| 启动器进的是 Inua | `vnc-debian` 或 `webapp-webdesktop-novnc.desktop` 仍指向 `/desktop/` | 按上文修正 |
| tailscale 离线 | `tailscaled` 未运行 | `systemctl --user status tailscaled` |
| 浏览器缓存导致错位 | 旧的 resize 设置 | `vnc-debian` 使用 isolated profile，不受影响 |

## 历史

原本 `vnc-debian` 指向 `/desktop/vnc.html`，而 `/desktop` 路由到 `127.0.0.1:6082`
（Inua Hyprland 的 wayvnc），所以启动器里的 "Debian Desktop" 实际打开的是
Inua 会话。已修正为 `/xfce/vnc.html`。