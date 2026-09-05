# 故障排查

## 确认主机和架构

```bash
uname -m
hostname
nixos-version
```

当前 HX90 主机的 flake 名是 `hx90`；ARM64 QEMU 主机是 `aarch64`。
HX90 的 hostname 也必须是 `hx90`，这样不带 `#hx90` 的 `omarchy update` 才能
自动选择 `nixosConfigurations.hx90`。

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

## 命令行工具报 bad interpreter: /bin/bash 或 mise 错误

在执行 `omarchy update` 后，Omarchy 可能会自动调用 `omarchy-mise-install` 为各类 agent 与 CLI（如 `codex`、`claude`、`gemini`、`omp`、`opencode` 等）在 `~/.local/bin/` 生成 wrapper 脚本。

### 1. `bad interpreter: /bin/bash: 没有那个文件或目录`

- **原因**：Omarchy 生成的 wrapper 脚本硬编码了 `#!/bin/bash` 作为 Shebang。NixOS 默认仅有 `/bin/sh` 与 `/usr/bin/env`，不存在原生的 `/bin/bash`。
- **配置修复**：`modules/core.nix` 已配置 `system.activationScripts.binbash`：
  ```nix
  system.activationScripts.binbash = ''
    mkdir -m 0755 -p /bin
    ln -sfn "${pkgs.bashInteractive}/bin/bash" /bin/bash
  '';
  ```
  该设置保证在所有 NixOS 主机与后续 rebuild 中 `/bin/bash` 始终常驻。
- **用户空间修复**：也可以批量将 `~/.local/bin/*` 脚本的 Shebang 替换为通用的 `#!/usr/bin/env bash`。

### 2. Mise 报错: `Invalid date or duration: 0`

- **原因**：Omarchy wrapper 脚本中包含了 `export MISE_MINIMUM_RELEASE_AGE=0`，而特定版本的 Mise 要求时长格式（如 `0s`、`0d`），裸写 `0` 会导致解析失败退出。
- **修复方法**：将脚本中的 `export MISE_MINIMUM_RELEASE_AGE=0` 改为 `export MISE_MINIMUM_RELEASE_AGE=0s`：
  ```bash
  sed -i 's/export MISE_MINIMUM_RELEASE_AGE=0$/export MISE_MINIMUM_RELEASE_AGE=0s/' ~/.local/bin/*
  ```

## ARM64 注意事项

Nixarchy 提供 `aarch64-linux` 包和检查，但实际图形输出仍取决于 QEMU 图形设备；VM 检查通过不代表 GPU 加速、蓝牙或音频一定正常。
