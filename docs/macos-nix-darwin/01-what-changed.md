# 这次做了什么

## 原来的状态

仓库原本只有 NixOS 输出：

```nix
nixosConfigurations = {
  aarch64 = ...;
  hx90 = ...;
  wsl = ...;
};
```

当前 Mac 没有 Nix，也没有 Darwin 配置。Homebrew 是实际的软件安装来源，
`chezmoi` 和 `dotfiles` 负责跨平台用户配置；macOS 专属用户配置属于本仓库的
Darwin Home Manager 层。

## 现在的状态

在同一个 flake 中新增：

```nix
darwinConfigurations.macbook-m1-max =
  inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [ ./hosts/macbook-m1-max/configuration.nix ];
  };
```

因此现在有 NixOS 和 Darwin 两类输出：

```text
nixosConfigurations.aarch64
nixosConfigurations.hx90
nixosConfigurations.wsl
darwinConfigurations.macbook-m1-max
```

## 新增和修改的文件

- `flake.nix`：增加 nix-darwin 输入和 Darwin 输出；
- `flake.lock`：锁定 nix-darwin 26.05 的具体提交；
- `hosts/macbook-m1-max/configuration.nix`：声明 Apple Silicon 主机；
- `modules/darwin/base.nix`：Nix、Zsh、基础 CLI 和环境变量；
- `modules/darwin/packages.nix`：开发和诊断工具；
- `modules/darwin/homebrew.nix`：GUI cask 和特殊 Homebrew formula；
- `modules/darwin/defaults.nix`：暂时为空的 macOS defaults 安全边界；
- `modules/home-manager/darwin-user.nix`：Darwin 版最小 Home Manager 配置；
- `modules/home-manager/darwin-files/`：AeroSpace、Karabiner、Hammerspoon、skhd
  和 macOS 手动维护脚本等 macOS 专属用户文件；
- `docs/macos-nix-darwin.md`：总览操作手册；
- `docs/macos-nix-darwin/`：本学习目录。

## 主机配置的职责

主机入口负责：

- 平台为 `aarch64-darwin`；
- 主机名为 `macbook-m1-max`；
- 主要用户为 `tetsuya`；
- `system.primaryUser = "tetsuya"`，让 Homebrew 知道用户上下文；
- 启用 Darwin Home Manager；
- `system.stateVersion = 6`。

这里没有 NixOS 的 `hardware-configuration.nix`，因为 macOS 的硬件、APFS 和
Recovery 不由 nix-darwin 接管。

## 激活过程中遇到的问题

### `sudo: nix: command not found`

普通用户 shell 能通过 Nix profile 找到 `nix`，但 `sudo` 使用 root 的精简 PATH。
所以首次激活使用绝对路径：

```bash
sudo /nix/var/nix/profiles/default/bin/nix ...
```

### `/etc/bashrc` 和 `/etc/zshrc` 冲突

Nix 安装器先修改了这两个文件，nix-darwin 的安全检查发现它们有未声明内容，因而
停止激活。安装器同时创建了：

```text
/etc/bashrc.backup-before-nix
/etc/zshrc.backup-before-nix
```

恢复这两个备份后重新激活，nix-darwin 才正式接管 shell 初始化文件。以后不要手动
编辑 `/etc/bashrc` 或 `/etc/zshrc`，应该修改 flake 后重新 build/switch。

### nix-darwin 26.05 的兼容要求

旧式的：

```nix
services.nix-daemon.enable = true;
```

在当前 nix-darwin 中已经没有效果，配置中已移除。Nix daemon 会随 Nix 自动管理。
Homebrew 则需要显式声明：

```nix
system.primaryUser = "tetsuya";
```

## 当前明确没有迁移的内容

- NixOS 的 systemd、Hyprland、SDDM、PipeWire、Fcitx5 Wayland、keyd；
- Linux 硬件、Btrfs、zram、休眠和 AMD GPU 调优；
- Hammerspoon/Karabiner 的 Accessibility/Input Monitoring 授权；
- 浏览器 profile、Token、Bitwarden session、`.env`；
- Rime 私有数据、Voxtype 模型和 Agent 配置；
- Finder、Dock、Mission Control 等未经确认的 macOS defaults。

这样先建立可靠的系统层，再逐项迁移用户层，避免一次切换影响整个工作环境。
