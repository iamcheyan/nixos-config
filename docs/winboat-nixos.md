# WinBoat on NixOS（HX90）

本文记录 HX90 上 WinBoat 的 NixOS 安装方式、Docker 组检查误报，以及 Guest API 离线时的排查顺序。

## 安装方式

WinBoat 官方 README 对 NixOS 的建议是使用 `nixpkgs-unstable` 中的 `pkgs.winboat`，同时启用 Docker 并把登录用户加入 `docker` 组。不要用 `nixpkgs-unstable` 替换整台系统的 nixpkgs 基线。

HX90 保持系统输入 `nixpkgs` 锁定在 `nixos-26.05`，另外锁定独立的 `nixpkgs-unstable` 输入。当前锁定版本为 `0bb2eedc20e4739f29e8045034f2828ad7054f8f`（2026-11-01）；WinBoat 版本为 0.9.2，使用 Electron 43.8.3。

`hosts/hx90/apps.nix` 从这个独立输入安装 WinBoat。`services.inuaWindowsVm` 模块启用 Docker，并通过 `dockerUsers = [ "tetsuya" ]` 把用户加入 `docker` 组。该组能访问 root 管理的 Docker daemon，权限等价于主机 root。

应用系统配置：

```bash
cd ~/nixos-config
sudo INUA_DEV_DIR=/home/tetsuya/development/inua-wayfire nixos-rebuild switch --flake .#hx90 --impure
```

2026-11-03 已成功应用该系统切换；当前系统的 `winboat` 命令指向 nixpkgs-unstable 包。

官方参考：

- [WinBoat README：Nix 安装与先决条件](https://github.com/winboat-org/winboat#downloading)
- [nixpkgs-unstable WinBoat 包定义](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/wi/winboat/package.nix)
- [WinBoat 官方 releases（应用与 Guest Server）](https://github.com/winboat-org/winboat/releases)

## Docker 组检查误报

原先 HX90 安装的是 WinBoat 0.9.2 AppImage。它在 FHS/bwrap 隔离环境中运行；该环境的 GID 映射只有主组 `users`（GID 100），并设置 `setgroups=deny`。主机上的 `docker` GID 131 没有映射进 WinBoat，因此 AppImage 内的 `id -Gn` 看不到 `docker`，WinBoat 就把组检查标成红叉。主机账户本身确实属于 `docker` 组，Docker daemon 和 socket 也正常。

排查时，旧的长驻会话进程还带有一个已无组名的 GID 983，使其 `id -Gn` 即使包含 `docker` 也以错误码退出；用干净组列表重启后，AppImage 私有 GID 映射仍然屏蔽了 supplementary groups。因此重新登录不是有效修复。

曾尝试在 bwrap 内覆盖 `/usr/bin/id`，但该目标是 symlink，bwrap 拒绝挂载（`Can't mount on symlink destination /usr/bin/id`）；该试验已撤回。

改用 nixpkgs-unstable 的原生 Nix 包后，WinBoat 进程回到主机 user namespace，能看到 `docker` 组。使用临时配置目录启动该包时，向导通过了先决条件并进入 Hardware Configuration；没有在临时测试中安装 Windows。正式切换后，原有 WinBoat 配置仍能打开。

## Guest API Offline 与首次 Windows 安装

WinBoat 显示 `Container - Running` 只表示 Docker 容器运行；`WinBoat Guest API - Offline` 表示 Windows 客体里的 Guest Server 尚未响应。这两项状态可以同时出现，尤其是 Windows 首次下载、安装或启动期间。

### 本次观测

2026-11-03 的排查中，容器 `WinBoat` 使用 `ghcr.io/dockur/windows:6.05`，状态为 `Up`、`RestartCount=0`、`OOMKilled=false`。WinBoat 显示 Windows 11 Pro 容器运行，但 Guest API 离线。容器日志显示：

1. 正在请求简体中文 Windows 11 镜像；
2. 首次访问 `vlscppe.microsoft.com` 时出现 `Could not resolve host`；
3. Dockur 随后切换备用下载方法，日志报告下载进度到 20%；
4. 主机后续已能解析该域名；本次 VNC 映射为 `127.0.0.1:47271->8006/tcp`，HTTP 返回 200。

因此这次的 Guest API Offline 出现在 Windows 镜像下载/首次启动阶段，不能据此认定 Guest Server 已损坏。检查时没有手动替换 Guest Server，也没有重新创建或清理 Windows 客体数据。

Dockur 日志还提示 `/storage` 使用 Btrfs 可能影响 Windows Setup。这是待留意的兼容性提示，不是本次 API 离线的直接证据。

### 排查顺序

1. 容器刚启动或 Windows 首次安装时先等待。Windows 镜像下载和首次启动可能远超一分钟；确认 Windows 已进入桌面后，再给 Guest Server 一两分钟启动时间。
2. 查看容器状态和最新日志：

   ```bash
   docker ps -a --filter name=WinBoat
   docker inspect --format 'State={{.State.Status}} RestartCount={{.RestartCount}} OOM={{.State.OOMKilled}}' WinBoat
   docker logs --tail 100 --timestamps WinBoat
   docker port WinBoat 8006/tcp
   ```

   `docker port` 输出的主机端口可能每次不同。将其组成 `http://127.0.0.1:<port>`，在浏览器打开 VNC。不要把上次的临时端口写死。
3. 如果日志仍显示镜像正在下载、Windows Setup 尚未完成，继续等待；此时 Guest Server 还不能在 Windows 内运行。
4. 如果 Windows 桌面已经可用，等待后 API 仍离线，再通过 VNC 在 Windows 客体按 `Win+R`，运行 `services.msc`，检查 `WinBoatGuestServer` 服务。
5. 只有确认 Windows 已完成启动且 Guest Server 服务缺失或文件损坏时，才更新 Guest Server：在 `services.msc` 中停止 `WinBoatGuestServer`；从 [官方 releases](https://github.com/winboat-org/winboat/releases) 下载与 WinBoat 版本一致的 guest-server 压缩包；备份后替换 `C:\Program Files\WinBoat` 内容，再启动服务。若 Defender 隔离文件，先核对下载来源并查看保护历史，不要为此永久关闭 Defender。首次安装或镜像下载期间不要替换服务。
6. 更新后若应用仍无法启动，关闭 VNC 页面，再重启 WinBoat 容器。

`docker exec WinBoat powershell ...` 不是有效的宿主排查命令：WinBoat 容器运行的是 Linux/QEMU 启动环境，PowerShell 位于尚未启动完成的 Windows 客体内。Guest Server 服务检查应通过 VNC 登录客体后进行。
