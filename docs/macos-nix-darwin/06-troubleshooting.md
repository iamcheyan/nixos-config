# 安装、权限和故障排查

## `nix: command not found`

当前 shell 尚未加载 Nix profile：

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
command -v nix
```

sudo 仍可能找不到它，使用：

```bash
sudo /nix/var/nix/profiles/default/bin/nix --version
```

## `$HOME ... falling back to /var/root`

sudo 执行 Nix 时 root 的 HOME 是 `/var/root`。这是警告，不是 flake 错误。切换时
使用绝对 flake 路径：

```bash
switch --flake "$PWD#macbook-m1-max"
```

不要把 `/var/root` 下的内容误认为是 `tetsuya` 的 Home Manager 配置。

## `Unexpected files in /etc`

典型错误：

```text
Unexpected files in /etc, aborting activation
/etc/bashrc
/etc/zshrc
```

检查备份：

```bash
ls -l /etc/bashrc* /etc/zshrc*
```

如果 `.backup-before-nix` 是安装器创建的原始文件：

```bash
sudo cp -p /etc/bashrc.backup-before-nix /etc/bashrc
sudo cp -p /etc/zshrc.backup-before-nix /etc/zshrc
```

不要直接删除这两个文件，也不要覆盖备份。

## nix-darwin 选项已经没有效果

删除旧式 `services.nix-daemon.enable`。如果 Homebrew 报需要 primary user，加入：

```nix
system.primaryUser = "tetsuya";
```

## Nix 看不到新文件

Flake 默认使用 Git tree 快照，untracked 文件可能不会进入求值：

```text
Path ... is not tracked by Git
```

检查并把最终文件加入 Git；临时验证可以：

```bash
git add -N path/to/file.nix
```

这不会提交，也不会把完整内容放入 staged diff，但能让 flake 看到路径。

## `nix flake check` 与单独 Darwin build

单独验证 Darwin：

```bash
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
```

完整检查：

```bash
nix flake check --no-build
```

完整检查会同时求值已有 NixOS 输出。如果错误出现在既有的 Nixarchy/Home Manager
路径或 `/nix/store/...-source is not valid`，要单独判断是缓存/GC 问题还是代码
问题。不要因为 Darwin build 成功就声称所有 NixOS 输出都通过了。

## Homebrew 想删除应用

第一次迁移应该保持：

```nix
cleanup = "none";
```

只有完整分类 `brew list --formula` 和 `brew list --cask` 后，才考虑清理。

## `command -v` 仍然指向 Homebrew

打开新的 Terminal 后检查：

```bash
type -a nvim
type -a chezmoi
type -a zellij
ls -l /run/current-system/sw/bin/nvim
```

旧 shell 指向 `/opt/homebrew/bin` 不一定表示 nix-darwin 失败，可能只是 PATH 尚未
重新加载。

## GUI 应用无法工作

到：

```text
System Settings → Privacy & Security
```

逐项检查 Accessibility、Input Monitoring、Microphone、Screen Recording、Files
and Folders、Login Items 和 Network Extensions。必须验证真实应用行为，不能只看
应用是否能打开。
