# 以后如何扩展配置

## 添加一个 Nix 包

编辑 `modules/darwin/packages.nix`：

```nix
environment.systemPackages = with pkgs; [
  # existing packages
  hyperfine
];
```

然后：

```bash
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
sudo darwin-rebuild switch --flake .#macbook-m1-max
```

不要只用用户 profile 手动安装后忘记写回 flake，否则换机时不会自动回来。

## 添加 Homebrew cask

确认名称：

```bash
brew search --cask name
```

再写入 `modules/darwin/homebrew.nix`。第一次切换保持 `cleanup = "none"`。
Cask 能安装不代表权限和用户数据已经恢复。

## 添加 macOS default

不要凭记忆直接加设置。先记录当前状态：

```bash
defaults read > /tmp/macos-defaults-before.txt
```

确认具体 key 和用户可见影响后，再写入 `modules/darwin/defaults.nix`。每个设置都
应说明对应的 System Settings 页面、当前值、修改效果和撤销方式。TCC 权限不要
仅凭 `defaults` 伪造，必须在系统设置中确认。

## 添加 launchd 服务

只有真正需要系统声明启动的服务才放 nix-darwin。新增前记录进程所有者、日志路径、
端口、是否需要 GUI session、权限需求以及停止/回滚方式。不要把 Linux systemd
unit 原样复制成 launchd 配置。

## 迁移一个用户配置到 Home Manager

一次只迁移一个应用：

```text
备份当前文件
→ 找到 chezmoi/dotfiles 所有者
→ 解除旧所有权
→ 写 Darwin Home Manager 配置
→ build
→ switch
→ 真实应用验证
→ 检查 chezmoi status
```

如果配置在 Linux、macOS 和其他机器都使用，优先继续放公共 dotfiles；只有明确
属于 macOS 或 Nix 的部分才放 Home Manager。

## 更新 nix-darwin 或 nixpkgs

当前仓库把 NixOS 和 macOS 放在同一个 nixpkgs 基线上，便于学习和保持一致。升级时：

1. 先备份并检查 Git 状态；
2. 一次只更新一个 input；
3. 先 `nix flake check --no-build`；
4. 再 Darwin build；
5. 激活后检查 generation；
6. 最后验证 NixOS host。

## 提交前检查

```bash
git status --short --branch
git diff --check
jq empty flake.lock
nix flake metadata
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
```

确认没有秘密、个人临时绝对路径、重复文件所有者或未经确认的 GUI defaults。
