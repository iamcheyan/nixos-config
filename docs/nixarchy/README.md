# Nixarchy / Omarchy 文档

这里集中记录本配置在 NixOS 上使用 Nixarchy 的资料、操作流程、仓库地址和已知限制。

## 当前状态

- 当前主力机器：`hx90`（hostname 为 `nixos`）
- 架构：`x86_64-linux`
- NixOS：`26.05`
- 桌面：Nixarchy / Omarchy + Hyprland + SDDM
- 配置入口：`hosts/nixos-hx90/configuration.nix`
- Nixarchy 版本：`v4.0.1-1`，具体 commit 见 `flake.lock`
- Omarchy 更新入口：`programs.nixarchy.flake = "/home/tetsuya/nixos-config"`

## 文档

- [安装与主机接入](setup.md)
- [换电脑迁移](migration.md)
- [更新、验证与回滚](update-and-rollback.md)
- [仓库和上游资料](references.md)
- [故障排查](troubleshooting.md)

## 相关配置

- `flake.nix`：flake 输入和主机注册
- `flake.lock`：可复现的依赖版本
- `modules/desktop.nix`：Nixarchy 桌面基础配置
- `hosts/nixos-hx90/configuration.nix`：当前 HX90 主机配置
- `hosts/aarch64/configuration.nix`：ARM64 QEMU 主机配置
