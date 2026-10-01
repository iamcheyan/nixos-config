# HX90 SDDM、Labwc 与多显示器适配

本文记录 HX90 当前桌面登录、Labwc 会话、Shizuka SDDM 主题和多显示器缩放的配置约定。

## 当前设计

- 桌面会话使用 Labwc，不使用 Omarchy/Hyprland 会话。
- 登录管理器使用 Wayland 版 SDDM。
- SDDM 主题使用 Shizuka。
- Shizuka 为每个 SDDM 输出创建独立的 QML view。
- 多显示器规范：仅在 SDDM 主显示器（`primaryScreen`）上展示登录交互区（居中头像、用户名、密码框、时间与电源会话菜单），所有副显示器仅渲染纯净虚化壁纸与暗色遮罩，彻底杜绝双屏焦点争夺与视觉错乱。单显示器环境下无缝显示完整界面。
- 主题优先根据当前主显示器 QML view 的实际宽高动态计算界面比例，screenModel 只作为备用，不按 HDMI 名称写死，也不假设固定的显示器数量。
- 登录核心控件（头像、用户名、密码框）在主显示器上垂直和水平居中，时间日期在顶部居中，视觉重心稳定平衡。
- 主题缩放范围扩展为 0.5 到 2.5，完整覆盖 720p/1024x768、1280x1024 (5:4)、1080p、2K (1440p) 到 4K/5K 高清屏。小屏保持文字控件最小可读限制，大屏不再因窄范围 clamp 导致过小。
- SDDM/KWin 的 HiDPI 处理先于主题执行，因此主题使用的是逻辑分辨率，不重复乘以 devicePixelRatio。

## 多显示器缩放与居中原理

主题优先读取当前 SDDM QML view 的 root.width/root.height；只有 view 尺寸暂时不可用时，才回退到该 view 的 screenModel.geometry(0)。SDDM 为每个物理输出创建独立 view，因此每个 view 会独立计算自己的比例并完成界面居中：

    uiScale = clamp(
      min(logicalWidth / 1920, logicalHeight / 1080),
      0.5,
      2.5
    )

这意味着：

- 不依赖 HDMI-A-1、HDMI-A-2 等输出名称；
- 显示器数量变化时仍然适用；
- 不同分辨率会得到不同的界面缩放；
- 4K 屏可能因为 SDDM HiDPI 显示为逻辑分辨率，这是预期行为；
- 主题缩放不会改变显示器的物理分辨率或刷新率。

检查当前 SDDM 输出：

    journalctl -u display-manager --no-pager -b \
      | rg 'Adding view|High-DPI|shizuka'

检查当前部署的主题缩放代码：

    rg -n 'screenGeometry|screenWidth|screenHeight|uiScale' \
      /run/current-system/sw/share/sddm/themes/shizuka/Main.qml

## 构建 HX90

Labwc-plus 使用本机开发 checkout，但源码路径不写入 Nix 模块。构建时通过环境变量提供：

    export LABWC_PLUS_SOURCE="$HOME/labwc-plus"
    export NIX_CONFIG_ROOT="$HOME/nixos-config"

    cd "$NIX_CONFIG_ROOT"
    sudo env LABWC_PLUS_SOURCE="$LABWC_PLUS_SOURCE" \
      nixos-rebuild switch --impure --flake "$NIX_CONFIG_ROOT#hx90"

LABWC_PLUS_SOURCE 没有设置时，Nix 会直接报错，不会回退到某个用户的 home 路径。

--impure 是必要的，因为 Labwc-plus 源码由环境变量指向 flake 外部的本地 checkout。

验证：

    systemctl is-active display-manager
    systemctl is-enabled display-manager

修改登录主题或 SDDM 配置后，通常在下一次返回登录界面时生效。不需要为了主题修改而重启机器。

## 登录与退出

- SDDM 默认会话：labwc
- 从 Labwc 退出应返回 SDDM。
- Labwc 的退出动作使用 labwc -e，不能使用 loginctl terminate-user，后者会连同用户会话一起终止，可能导致 SDDM 黑屏。
- 如果出现登录界面黑屏，先检查 display-manager、SDDM greeter 和 KWin 日志，不要立即重启：

    systemctl status display-manager --no-pager
    journalctl -u display-manager -b --no-pager -n 200

## Sunshine + Moonlight 远程桌面

HX90 运行 Sunshine，Mac 端使用 Moonlight。连接地址以当前 DHCP 地址为准，不应永久假设某个 IP。

在 Mac 上：

1. 打开 Moonlight。
2. 添加 HX90 当前 IP 或主机名。
3. 选择 Desktop。
4. Moonlight 显示 PIN 后，在浏览器打开 Sunshine Web UI。
5. 在 Sunshine 的 PIN 页面输入 PIN，完成配对。
6. 回到 Moonlight，启动 Desktop。

建议初始参数：

- 分辨率：使用 HX90 当前显示器可用的逻辑分辨率；
- 帧率：60 FPS；
- 编码：优先 HEVC，兼容性问题时改用 H.264；
- 码率：50–80 Mbps。

首次打开 Sunshine HTTPS 页面时，自签名证书提示属于正常现象。不要把 Sunshine 用户名、密码或 PIN 写入本文档。

如果地址变化，应先确认 HX90 身份和当前地址：

    hostname
    ip -brief address

建议在路由器上为 HX90 的 Wi-Fi MAC 配置 DHCP 固定租约。

## 路径可移植性约定

配置中不应写入某个用户的绝对 home 路径，例如 /home/tetsuya/... 或 /Users/tetsuya/...。

使用以下环境变量：

- LABWC_PLUS_SOURCE：Labwc-plus 外部源码 checkout；
- NIX_CONFIG_ROOT：Nix 配置 checkout；
- DARWIN_HOME：nix-darwin 主用户 home 目录。

/run/current-system、/etc、/usr/bin 等系统标准路径属于 NixOS、systemd 或 macOS 的运行时约定，不是用户目录绑定路径，可以保留。

## 相关配置位置

- modules/desktop.nix：SDDM、Wayland greeter 和 Shizuka 主题打包；
- modules/labwc-plus.nix：Labwc-plus 外部源码环境变量；
- modules/labwc.nix：Labwc 会话和用户配置；
- modules/desktop-runtime.nix：桌面运行时与兼容工具；
- hosts/hx90/configuration.nix：HX90 主机设置；
- modules/anchor-shell/plugins/panels/power/Panel.qml：图形电源面板退出动作；
- modules/labwc/labwc/scripts/system-menu：Labwc 系统菜单退出动作。
