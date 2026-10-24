# 桌面环境：从系统选项到图形会话

## 桌面配置不是单个开关

可交互桌面由多个系统服务、Wayland compositor、shell 组件和用户配置一起组成。在本仓库里，`desktop.nix` 提供共享图形栈，`workstation.nix` 定义图形工作站基线，主机入口声明机器差异，`labwc.nix` 负责把本地 Labwc 和 Anchor Shell 接入 NixOS。

```text
flake output → host configuration
                  ├── workstation.nix → SDDM / boot / user / Home Manager
                  └── desktop.nix     → 音频 / Bluetooth / 字体 / 会话
                                          └── labwc.nix → Labwc + Anchor Shell
```

## 桌面模块索引

- [桌面 profile `modules/desktop.nix`](../modules/desktop.nix)：SDDM、PipeWire、蓝牙、字体和图形组件。
- [工作站 profile `modules/workstation.nix`](../modules/workstation.nix)：共享启动器、基础策略和 Home Manager。
- [Labwc 接线 `modules/labwc.nix`](../modules/labwc.nix)：程序包、用户 session、shell 路径与会话配置。
- [Anchor Shell 说明](../modules/anchor-shell/README.md)与[架构设计](../modules/anchor-shell/ARCHITECTURE.md)：Quickshell、插件 API、开发模式与运行时目录。
- [Labwc 文档](../modules/labwc/README.md)：配置结构、主题、键位、Wofi、缩放、热角及多屏。
- [键位指南](../docs/keyd.md)：Linux keyd、桌面快捷键与 MINILA-R 输入流程。
- [锁屏故障排查](../docs/hx90-lockscreen-black-screen-incident.md)：一次 HX90 图形锁屏排错记录。
- [多显示器与 SDDM](../docs/hx90-sddm-labwc-multi-monitor.md)：登录器与桌面显示器行为。
- [Quickshell 模式和路径](../docs/quickshell-paths-and-modes.md)：开发源码与正式安装的选择方式。

## Anchor Shell 与 Omarchy 兼容层

HX90 主要桌面会话是 Labwc + Anchor Shell。Anchor Shell 是本仓库维护的 shell 应用，包含 launcher、bar、lock、clipboard、桌面图标、录屏等插件。Omarchy 兼容代码位于 `modules/anchor-shell/compat/omarchy`，为现有 desktop resources 和 helper commands 提供兼容实现；兼容资源不是独立 NixOS 配置管理器，也不意味着改动它的源码就已更新目标机器。

插件清单与通用设计见 [Anchor Shell 插件索引](../modules/anchor-shell/plugins/README.md)。具体插件说明：

- [Bar 顶栏](../modules/anchor-shell/plugins/bar/README.md)
- [Launcher 启动器](../modules/anchor-shell/plugins/launcher/README.md)
- [锁屏](../modules/anchor-shell/plugins/lock/README.md)
- [Clipboard 剪贴板](../modules/anchor-shell/plugins/clipboard/README.md)
- [桌面图标](../modules/anchor-shell/plugins/desktop-icons/README.md)
- [截图](../modules/anchor-shell/plugins/screenshot/README.md)与[屏幕录制](../modules/anchor-shell/plugins/screen-recording/README.md)
- [语音输入 Voxtype](../modules/anchor-shell/plugins/voxtype/README.md)
- [Bitwarden](../modules/anchor-shell/plugins/bitwarden/README.md)

## 修改时怎么定位

- 系统服务或系统包未启用：检查 host imports 与 `desktop.nix`。
- Labwc session、入口程序、QML 插件加载异常：检查 `labwc.nix` 和 `modules/anchor-shell`。
- 用户个人快捷键与主题偏好：先确认它由 Home Manager、chezmoi 还是插件运行时管理。
- 多屏显示问题：检查 compositor 输出设置与 shell 主屏策略，不要盲目加全局缩放选项。
- 修改后优先构建目标 flake 输出，再在实际主机验证 UI；Nix 求值成功并不等于所有外部显示器和设备运行符合预期。

本页为学习索引。具体源码、当前状态和插件文件是最终依据；机器运行日志不在此站公开。
