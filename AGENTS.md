# NixOS System Configuration

本仓库是三层配置体系中的 **NixOS 系统层**。它管理需要通过 Nix 求值、构建和
切换 generation 才能生效的声明式系统配置。

## 三个主仓库的边界

| 仓库 | 可见性 | 所有权 |
|---|---|---|
| `~/nixos-config` | 私人系统仓库 | NixOS 模块、系统包和服务、内核/引导、硬件与主机差异、Nixarchy 系统接线 |
| `~/chezmoi` | PRIVATE | 用户级私人软件配置、凭据的 age 加密产物、Agent、输入法数据、终端及桌面偏好编排 |
| `~/dotfiles` | PUBLIC | 可公开复用的 Zsh、Neovim、Ranger、Vifm、Starship 和 dotlink |

判断规则：需要 `nixos-rebuild` 才能生效，或涉及 `/etc`、systemd system service、
系统包/驱动/内核/用户组的内容，必须放本仓库。只需部署到用户家目录的私人配置
放 chezmoi；可以脱离个人环境公开复用的配置放 dotfiles。不要在多个仓库复制同一
份配置。

## 修改规则

- 编辑本仓库源文件，不直接修改 `/etc/nixos` 或 `/nix/store`。
- `hardware-configuration.nix`、磁盘 UUID 和主机硬件参数按主机隔离。
- `system.stateVersion` 不随日常升级修改。
- Omarchy/Nixarchy 的系统集成属于本仓库；其用户偏好仍属于 chezmoi。
- 不提交明文密码、Token、API Key、SSH 私钥或其他凭据。
- 保留用户已有的未提交改动，不擅自覆盖或移动。

## 验证与应用

```bash
cd ~/nixos-config
nix flake check --no-build
nixos-rebuild build --flake .#hx90
sudo nixos-rebuild switch --flake .#hx90
```

更新输入时使用仓库自身的锁文件：

```bash
cd ~/nixos-config
nix flake update
sudo nixos-rebuild switch --flake .#hx90
```
