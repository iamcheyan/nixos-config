# 换电脑迁移

这套配置由 NixOS flake、Nixarchy、Home Manager 和 chezmoi 共同组成。换电脑时不要直接复制旧机器的硬件配置。

## 1. 安装 NixOS 并生成硬件配置

新系统启动后执行：

```bash
sudo nixos-generate-config
```

安装环境中则使用：

```bash
sudo nixos-generate-config --root /mnt
```

新的 `hardware-configuration.nix` 必须来自新机器。磁盘 UUID、CPU 微码、内核模块和显卡设置都不能直接照搬旧机器。

## 2. 获取配置仓库

```bash
git clone <nixos-config 仓库地址> ~/nixos-config
cd ~/nixos-config
```

如果仓库是私有仓库，需要先恢复 SSH key，或暂时使用 HTTPS + token。

## 3. 创建新主机

例如新主机名为 `new-laptop`：

```bash
mkdir -p ~/nixos-config/hosts/new-laptop
cp /etc/nixos/hardware-configuration.nix ~/nixos-config/hosts/new-laptop/hardware-configuration.nix
cp hosts/nixos-aarch64/configuration.nix hosts/new-laptop/configuration.nix
```

修改 `networking.hostName`，并删除不适用的 QEMU/SPICE、休眠、AMD/Intel、Docker 或 Snapper 配置。

在 `flake.nix` 注册：

```nix
new-laptop = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux"; # ARM64 机器改为 aarch64-linux
  specialArgs = { inherit inputs; };
  modules = [ ./hosts/new-laptop/configuration.nix ];
};
```

## 4. 构建并切换

```bash
sudo nixos-rebuild build --flake ~/nixos-config#new-laptop
sudo nixos-rebuild switch --flake ~/nixos-config#new-laptop
```

重启或注销后，在 SDDM 中选择 `Omarchy`。

## 5. 恢复 chezmoi

```bash
git clone <chezmoi 仓库地址> ~/chezmoi
```

如果使用 age 加密，还要恢复 `~/age.key`。然后预览并应用：

```bash
chezmoi --source=~/chezmoi diff
chezmoi --source=~/chezmoi apply
```

不要让旧 chezmoi 文件覆盖 nixarchy 的核心 `~/.config/omarchy/shell.json` 或 Omarchy 会话配置。

## 6. 恢复插件

插件记录在 `~/.config/omarchy/plugins.list`。如未自动恢复，在 Omarchy 会话中执行：

```bash
omarchy plugin add https://github.com/iamcheyan/omarchy-ctrl-swap.git --enable
omarchy plugin add https://github.com/iamcheyan/omarchy-overview-workspaces.git --enable
omarchy plugin add https://github.com/iamcheyan/omarchy-voxtype-enhance.git --enable
omarchy restart shell
```

## 7. 最终验证

```bash
uname -m
hostname
nixos-version
nix flake check --no-build
nix run github:olafkfreund/nixarchy#verify
```

## 迁移原则

- `flake.lock` 可以复用，用于保持依赖版本一致；
- `hardware-configuration.nix` 必须重新生成；
- 用户配置和插件由 chezmoi 恢复；
- NixOS generation 可以回滚系统配置，但不会完整回滚用户目录、浏览器数据、keyring 或 Docker volume。
