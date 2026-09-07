# 日常使用与更新

## 标准流程

```bash
cd ~/nixos-config

# 查看输出
nix flake show

# 求值检查
nix flake check --no-build

# 只构建，不切换当前系统
nix build .#darwinConfigurations.macbook-m1-max.system --no-link

# 确认后应用
sudo /nix/var/nix/profiles/default/bin/nix \
  --extra-experimental-features "nix-command flakes" \
  run nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake "$PWD#macbook-m1-max"
```

`check` 主要检查 flake 输出和模块求值；`build` 生成 system derivation；`switch`
才会修改 `/etc`、系统 profile、launchd 和 Homebrew 状态。

## 查看当前系统

```bash
readlink /run/current-system
/run/current-system/sw/bin/darwin-version
```

查看系统层命令：

```bash
for c in nix nvim chezmoi zellij btop starship; do
  type -a "$c"
done
```

第一次激活后要关闭旧 shell，打开新的 Terminal。已有 shell 不会自动重新读取新的
`/etc/zshrc`。临时加载 Nix 可以用：

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

## Homebrew

当前配置是：

```nix
homebrew.onActivation = {
  cleanup = "none";
  autoUpdate = false;
  upgrade = false;
};
```

含义是 switch 会安装声明的 cask/formula，但不会删除未分类软件，也不会每次
自动升级所有 Homebrew 软件。

```bash
brew list --formula
brew list --cask
brew update
brew outdated
```

Homebrew 更新和 flake 更新是两套不同的流程，不要混为一次更新。

## 更新 flake inputs

```bash
nix flake metadata
nix flake update nix-darwin
nix flake check --no-build
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
```

需要全部更新时才执行：

```bash
nix flake update
```

## 当前 shell 与 sudo PATH

普通 shell 可能能找到 `nix`，但 sudo 找不到，因为 sudo 会清理 PATH。首次激活和
任何 `sudo` 命令都可以使用：

```text
/nix/var/nix/profiles/default/bin/nix
```

激活成功并新开 Terminal 后，通常可以直接使用：

```bash
darwin-rebuild switch --flake ~/nixos-config#macbook-m1-max
```

## 免密码切换

当前 Darwin 配置还会生成一个固定目标的包装命令：

```bash
sudo darwin-rebuild-macbook
```

它只执行：

```text
darwin-rebuild switch --flake /Users/tetsuya/nixos-config#macbook-m1-max
```

不会接受额外参数，因此没有开放整个 `nix`、shell 或任意 flake 的免密码 root 权限。
第一次安装这条 sudoers 规则时，仍然要使用原来的命令输入一次 macOS 登录密码；规则
只有在该次 switch 成功后才会生效。

如果以后改了仓库路径、主机名或希望支持 rollback，需要先修改包装脚本和 sudoers 规则，
再用一次普通 sudo 激活新 generation。不要为了省事直接改成 `NOPASSWD: ALL`。
