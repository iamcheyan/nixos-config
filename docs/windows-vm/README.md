# Omarchy Windows VM（NixOS hx90）

## 当前状态

Windows VM 安装器原本在写入配置阶段失败，错误是：

```text
omarchy-windows-vm: refusing to run a non-root-owned command as root
❌ Failed to write the Windows VM configuration.
```

这不是实际的文件所有权错误，而是上游脚本把可信提权目标硬编码为
`/usr/bin/omarchy-windows-vm`。NixOS 中该路径不存在；程序实际位于
`/nix/store`，并通过 `/run/current-system/sw/bin` 暴露。

本仓库通过 `modules/packages/nixarchy-omarchy.nix` 在 Nix 包构建阶段补丁化
Omarchy，不修改上游仓库源码。补丁包含：

- 使用当前脚本的 canonical Nix store 路径作为 `pkexec` 目标，并保留 root
  所有权和不可写检查；
- 允许 Nix store 自身合法的 `root: nixbld`、sticky `1775` 边界，同时不放宽
  store 内具体路径的所有权检查；
- root 侧 PATH 加入 NixOS 的 `/run/current-system/sw/bin` 和
  `/run/wrappers/bin`；
- 将旧式 `docker-compose` 调用改为 NixOS 提供的 `docker compose`；
- 将 `timeout` 和 `find` 改为 NixOS system profile 中的绝对路径。

此外，`modules/desktop.nix` 配置了一条精确的 Polkit 规则：只允许本地登录的
`tetsuya` 用户无密码调用 root-owned 的
`*/share/omarchy/bin/omarchy-windows-vm`。它不会放开其他 `pkexec` 程序；这是因为
上游 helper 的 root-owned Compose 写入阶段固定使用 `pkexec`。

系统层和 Home Manager 层都引用同一个包覆盖，避免 CLI、菜单和用户服务使用
不同版本的 Omarchy。

## 应用配置

在 `~/nixos-config` 中执行：

```bash
nix flake check --no-build
nixos-rebuild build --flake .#hx90
sudo nixos-rebuild switch --flake .#hx90
```

切换成功后重新打开安装器：

```bash
omarchy-windows-vm install
```

也可以从 Omarchy 菜单中的 Windows 项目启动。安装器会写入 root-owned 的
`/var/lib/omarchy/windows/docker-compose.yml`，用户自己的凭据保存在：

```text
~/.config/windows/credentials
```

该文件应保持 `0600` 权限，不要提交到 Git。

## 安装后的常用命令

```bash
omarchy-windows-vm status
omarchy-windows-vm launch
omarchy-windows-vm stop
```

本次实际验证使用了安装器默认配置：4 GiB RAM、2 个 CPU 核心、64 GiB 虚拟磁盘、
Windows 用户名 `docker`。安装器已成功完成提权、写入 Compose 并启动容器；随后
Dockur 开始下载约 8.47 GiB 的 Windows 11 25H2 ISO。

首次安装会下载 Windows 镜像，可能需要较长时间，并会打开
`http://127.0.0.1:8006` 查看安装进度。

当前主机的 `/home` 位于 Btrfs，Dockur 会显示 Btrfs storage warning。这是上游
对 Windows Setup 的兼容性提示，不是容器启动失败；本机容器启动、KVM、3389 和
8006 监听均已验证正常。

## 验证清单

安装前先确认：

```bash
test -e /dev/kvm
systemctl is-active docker
systemctl is-active polkit
docker compose version
df -h "$HOME"
```

安装器通过配置写入阶段后，再确认：

```bash
sudo stat -c '%U:%G %a %n' /var/lib/omarchy/windows/docker-compose.yml
stat -c '%U:%G %a %n' ~/.config/windows/credentials
omarchy-windows-vm status
```

## 已知的无关日志

本次诊断中系统没有 failed systemd unit，Docker 和 Polkit 都是 active，磁盘和
内存也充足。启动日志中的 Home Manager 一次失败和 D-Bus 重复服务名与 Windows
VM 写配置失败不是同一条故障链。此次 Home Manager 失败是既有
`~/.gtkrc-2.0.hm-backup` 与默认备份后缀冲突；配置已改用
`hm-backup-nixos`，原文件没有删除或覆盖。
