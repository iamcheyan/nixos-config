# 安装与主机接入

## 当前主力主机

HX90 对应 flake 名 `hx90`，应使用：

```bash
nixos-rebuild build --flake /home/tetsuya/nixos-config#hx90
sudo nixos-rebuild switch --flake /home/tetsuya/nixos-config#hx90
```

ARM64 QEMU 主机改用 `#aarch64`。`build` 不需要 root；只有激活 system
generation 的 `switch` 需要 `sudo`。

切换后注销，在 SDDM 中选择 `Omarchy` 会话。

## 初次检查

```bash
uname -m
hostname
nixos-version
nix run github:olafkfreund/nixarchy#doctor
```

`doctor` 只读检查当前系统，不会修改配置。

## 配置组成

NixOS 模块负责系统服务、Hyprland、SDDM、字体和 Omarchy 运行时；Home Manager 模块负责用户侧配置、主题状态和应用选择。

ARM64 主机额外保留 SPICE、QEMU guest 和音频/视频用户组配置；HX90 保留休眠、
AMD 图形和工作站相关配置。

## 应用选择

Omarchy 菜单中的应用选择会写入 `~/.config/nixarchy/apps.nix`。应用变更后运行：

```bash
nixarchy-apply
sudo nixos-rebuild switch --flake /home/tetsuya/nixos-config#hx90
```

如果生成了 `nixarchy-apps.nix`，必须确保它被主机配置导入，否则选择不会真正安装。
