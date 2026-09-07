# Homebrew、Home Manager、chezmoi 与 dotfiles

## 不要把“由 Nix 安装”理解成“由 Nix 管所有东西”

Nix 擅长声明软件和系统构建，用户目录则包含登录状态、缓存、权限、数据库和机器
状态。Nix 可以安装 Firefox，但不会自动恢复 Firefox cookie；可以安装 Hammerspoon，
但不会自动获得 Accessibility 权限；可以安装 Bitwarden CLI，但不应把 session 写
进公共 flake。

## 当前 Mac 的推荐所有权

### nix-darwin

管理 Nix、基础 CLI、开发工具、GUI cask、少量 defaults 和未来的 launchd 系统服务。

### Darwin Home Manager

管理本机专属的用户文件：AeroSpace、Karabiner、Hammerspoon、skhd，以及 macOS
专用的手动维护脚本。源文件在 `modules/home-manager/darwin-files/`。

### chezmoi

继续管理跨平台私人 `.env`、Agent、Voxtype、Rime、tmux、用户服务和权限
相关流程。

### dotfiles

继续管理公共 Zsh、Neovim、Starship、Ranger/Vifm、通用别名和公开 CLI 配置。

## 迁移一个用户配置的正确顺序

例如把 Kitty 配置从 chezmoi 迁到 Home Manager：

1. 备份当前目标文件和源模板；
2. 找到 chezmoi/dotfiles 的真实所有者；
3. 从旧仓库移除该目标的生成逻辑；
4. 在 Darwin Home Manager 中声明；
5. `nix build`；
6. `darwin-rebuild switch`；
7. 关闭并重新打开 Kitty；
8. 验证字体、shell、快捷键和 session；
9. 检查 `chezmoi status`。

否则两个管理器会互相覆盖，最终状态取决于最后一次运行谁。

## PATH 和平台可移植性

共享 dotfiles 不要硬编码：

```text
/opt/homebrew/bin/nvim
/Applications/kitty.app/Contents/MacOS/kitty
/home/tetsuya/...
```

优先用 PATH 查找程序，并兼容：

```text
Apple Silicon Homebrew: /opt/homebrew
Intel Homebrew:         /usr/local
Nix:                    /nix/var/nix/profiles/default/bin
Darwin system profile:  /run/current-system/sw/bin
```

个人绝对路径、LAN 地址、密钥和 Agent 私有状态继续放 chezmoi。
