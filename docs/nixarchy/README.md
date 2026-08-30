# Nixarchy / Omarchy 文档

这里集中记录本配置在 NixOS 上使用 Nixarchy 的资料、操作流程、仓库地址和已知限制。

## 当前状态

- 当前机器：`aarch64`
- 架构：`aarch64-linux`
- NixOS：`26.05`
- 桌面：Nixarchy / Omarchy + Hyprland + SDDM
- 配置入口：`hosts/aarch64/configuration.nix`
- Nixarchy 版本：`v4.0.1-1`，具体 commit 见 `flake.lock`

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
- `hosts/aarch64/configuration.nix`：当前 ARM64 主机配置
