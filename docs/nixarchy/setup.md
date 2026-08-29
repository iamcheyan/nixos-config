# 安装与主机接入

## 当前主机

本机是 ARM64 QEMU/NixOS 主机，应使用：

```bash
sudo nixos-rebuild build --flake /home/tetsuya/nixos-config#nixos-aarch64
sudo nixos-rebuild switch --flake /home/tetsuya/nixos-config#nixos-aarch64
```

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

ARM64 主机额外保留 SPICE、QEMU guest 和音频/视频用户组配置。

## 应用选择

Omarchy 菜单中的应用选择会写入 `~/.config/nixarchy/apps.nix`。应用变更后运行：

```bash
nixarchy-apply
sudo nixos-rebuild switch --flake /home/tetsuya/nixos-config#nixos-aarch64
```

如果生成了 `nixarchy-apps.nix`，必须确保它被主机配置导入，否则选择不会真正安装。
