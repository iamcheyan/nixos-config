# 配置结构与职责边界

## 三层模型

```text
系统层       ~/nixos-config
Darwin 用户层 ~/nixos-config/modules/home-manager/darwin-files
跨平台私有层 ~/chezmoi
公共配置层   ~/dotfiles
```

### `nixos-config`

适合放 Nix、nix-darwin、NixOS、系统包、Homebrew 声明、launchd、系统用户、
NixOS 内核/硬件/桌面接线，以及不含秘密的系统环境变量。

### `chezmoi`

继续放跨平台私人 shell 编排、Agent、Rime、Voxtype、tmux、用户级服务、
age 加密文件和秘密入口。

### `dotfiles`

继续放可以公开复用的 Zsh、Neovim、Starship、Ranger/Vifm、通用别名和公开脚本。

公共仓库不能出现个人绝对路径、LAN 地址、API key、Token 或 Agent 私有配置。

## 软件包所有权

| 类型 | 首选所有者 | 示例 |
|---|---|---|
| 通用 CLI | Nix | `ripgrep`、`fd`、`jq`、`neovim` |
| Apple GUI 应用 | Homebrew cask | Kitty、Ghostty、Hammerspoon |
| 跨平台私人配置文件 | chezmoi | Agent、Voxtype、Rime、通用 shell |
| macOS 专属用户文件 | Darwin Home Manager | AeroSpace、Karabiner、Hammerspoon、skhd |
| 公共配置文件 | dotfiles | Zsh、Neovim、Starship |
| 密钥和 session | 加密存储/手工恢复 | `.env`、Bitwarden session |
| 缓存和构建产物 | 应用或项目自己管理 | `node_modules`、`.cache` |

避免同一个 CLI 同时由 Nix 和 Homebrew 安装。检查所有候选路径：

```bash
type -a nvim
type -a chezmoi
type -a zellij
```

当前 shell 仍显示 `/opt/homebrew/bin` 不一定表示 nix-darwin 失败，可能只是旧
shell 尚未重新加载 PATH。打开新的 Terminal 后再次检查。

## nix-darwin 与 macOS 的边界

```text
nix-darwin 管理：Nix profile、系统包、Homebrew 声明、部分 defaults、launchd
Apple 管理：XNU 内核、APFS、Recovery、固件、硬件驱动、系统更新、TCC 数据库
```

因此 build 成功不等于 Hammerspoon 已获得 Accessibility，也不等于浏览器已经
登录、麦克风已授权或 Voxtype 模型已经存在。这些必须单独验证真实行为。

## Home Manager 的位置

Home Manager 可以管理 `home.packages`、shell 环境、dotfiles、用户服务和 XDG
配置。本仓库的 Darwin 入口只生成明确属于 macOS 的用户文件；跨平台文件和秘密
仍不迁入这里。

迁移某个配置时必须：

```text
确定唯一所有者
→ 从原仓库/模板移除旧生成方式
→ build
→ switch
→ 打开真实应用验证
```

不要让 Home Manager 和 chezmoi 同时生成同一个路径。
