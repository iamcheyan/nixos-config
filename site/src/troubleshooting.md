# 排错与安全更新

## 更新不是一个动作

`flake update` 改锁文件；`nixos-rebuild build` 构建候选系统；`switch` 激活候选 generation。故障可能来自不同层：Nix 语法/模块求值、包构建、systemd 启动、图形会话、某台设备的硬件。先用日志和目标构建定位层级，再决定回滚 generation 或恢复文件快照。

## 建议的变更循环

```bash
cd ~/nixos-config
nix flake check --no-build
nixos-rebuild build --flake .#hx90
```

通过后再切换：

```bash
sudo nixos-rebuild switch --flake .#hx90
```

正式系统更新优先调用 `nixos-update`，查看 [`更新前快照手册`](../docs/nixos-update-snapshots.md)。不要对 WSL 或 ARM 主机误用 hx90 输出；主机输出清单见[架构页](architecture.md)。

## 三种恢复方式分别解决什么

1. **NixOS generation / boot rollback**：新系统闭包不能启动或系统级配置失效时，恢复以前的 Nix store 闭包。
2. **根文件系统 Btrfs/Snapper 快照**：回看/恢复快照覆盖的 `/` 数据。
3. **家目录快照**：恢复用户文件状态。

三者不是替代关系。generation 不等于数据备份；回滚 `/home` 可能丢弃快照之后的个人文件。快照不等于异机 NAS 备份。

完整步骤：[快照创建、记录格式与恢复流程](../docs/nixos-update-snapshots.md)。

## 排错入口

- [MINILA-R/keyd 按键链](../docs/keyd.md)：先区分键盘输出与桌面层绑定。
- [Labwc 多屏与 SDDM](../docs/hx90-sddm-labwc-multi-monitor.md)：登录阶段和已登录会话分别检查。
- [锁屏黑屏记录](../docs/hx90-lockscreen-black-screen-incident.md)：系统锁屏、显示输出与 compositor 分层诊断。
- [Quickshell 路径和运行模式](../docs/quickshell-paths-and-modes.md)：源码开发运行与 store 安装模式。
- [AI 环境接线](../docs/agent-environment.md)：系统路径、用户环境和 session 生效时间。
- [WSL 操作](../docs/wsl.md)：共享模块与本地 impure 扩展。

机器私有日志或含内部路径、设备 ID、硬件细节的诊断记录不会复制到公共网页；需在本机仓库或系统日志中查看。

## 改动前检查

- 确认工作区与目标主机，不重置用户未提交修改。
- 找到 option 的定义与所有导入它的主机。
- 确认 hostname 和 flake output 名称，确认 target architecture。
- 硬件 UUID、boot.resumeDevice、GPU、内核和 stateVersion 不照抄到另一台设备。
- 改变输入版本前确认目标 branch、受影响主机和回滚办法。
- 配置检查成功后，保留 build 输出；只有用户确实希望生效时才 `switch`。
