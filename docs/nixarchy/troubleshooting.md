# 故障排查

## 确认主机和架构

```bash
uname -m
hostname
nixos-version
```

当前 ARM64 主机的 flake 名是 `nixos-aarch64`，不是 `nixos-new`。

## 只检查配置

```bash
nix flake check --no-build
sudo nixos-rebuild build --flake /home/tetsuya/nixos-config#nixos-aarch64
```

## 登录界面没有 Omarchy

```bash
ls /run/current-system/sw/share/wayland-sessions/
systemctl status display-manager
```

## 黑屏或 QuickShell 没启动

```bash
journalctl --user -b --no-pager | rg -i 'omarchy|quickshell|hyprland|qml'
nix run github:olafkfreund/nixarchy#verify
```

## 更新失败

先查看锁文件变化，不要连续更新多个输入：

```bash
git diff -- flake.lock
git diff
```

如果已切换到坏的 generation，使用 `sudo nixos-rebuild switch --rollback` 或从 systemd-boot 选择上一代。

## ARM64 注意事项

Nixarchy 提供 `aarch64-linux` 包和检查，但实际图形输出仍取决于 QEMU 图形设备；VM 检查通过不代表 GPU 加速、蓝牙或音频一定正常。
