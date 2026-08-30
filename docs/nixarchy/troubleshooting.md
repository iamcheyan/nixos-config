# 故障排查

## 确认主机和架构

```bash
uname -m
hostname
nixos-version
```

当前 HX90 主机的 flake 名是 `hx90`；ARM64 QEMU 主机是 `aarch64`。
`flake.nix` 还提供 `nixos` 作为 HX90 的 hostname 别名，供不带 `#hx90` 的
`omarchy update` 使用。

## 只检查配置

```bash
nix flake check --no-build
nixos-rebuild build --flake /home/tetsuya/nixos-config#hx90
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

如果错误指向 `/etc/nixos`，说明启动命令的旧会话仍携带错误变量：

```bash
echo "$NIXARCHY_FLAKE"
NIXARCHY_FLAKE="$HOME/nixos-config" omarchy update
```

正确持久配置位于 `modules/desktop.nix` 的 `programs.nixarchy.flake`。不要修改
`/etc/nixos` 所有权，也不要直接编辑 `/nix/store` 中的更新脚本。

## ARM64 注意事项

Nixarchy 提供 `aarch64-linux` 包和检查，但实际图形输出仍取决于 QEMU 图形设备；VM 检查通过不代表 GPU 加速、蓝牙或音频一定正常。
