# macOS 纳入 Nix 管理

本章说明如何把当前这台 Apple Silicon Mac 纳入本仓库，以及为什么 macOS
配置和 NixOS 配置必须分开。它既是操作手册，也是以后排查和迁移时的学习笔记。

当前目标主机：

| 项目 | 当前值 |
|---|---|
| flake 输出名 | `macbook-m1-max` |
| 当前主机 | MacBook Pro M1 Max |
| 架构 | `aarch64-darwin` |
| 内存 | 64 GB |
| macOS | 26.6.2 |
| 配置入口 | `darwinConfigurations.macbook-m1-max` |
| 应用命令 | `sudo darwin-rebuild switch --flake .#macbook-m1-max` |

## 1. 这次到底引入了什么

本仓库原来只有 NixOS 输出，现在增加一个独立的 Darwin 输出：

```text
nixosConfigurations
├── aarch64
├── hx90
└── wsl

darwinConfigurations
└── macbook-m1-max
```

它们共享同一个 `flake.lock` 和 `nixpkgs` 基线，但不是同一套模块：

```text
NixOS
├── systemd / systemd-boot
├── SDDM / Hyprland
├── PipeWire / Fcitx5 Wayland
├── keyd
└── Btrfs / zram / Linux 硬件

macOS / nix-darwin
├── launchd / macOS activation
├── Homebrew formulae/casks
├── macOS defaults
├── aarch64-darwin packages
└── Apple kernel / APFS / Recovery 仍由 macOS 管理
```

`nix-darwin` 是 macOS 的系统模块层。它需要先有 Nix，然后通过 `darwinSystem`
生成配置、通过 `darwin-rebuild` 激活。macOS 没有 NixOS 那种
`hardware-configuration.nix`：Apple 的硬件、APFS 分区、Recovery 和启动链不
由本仓库接管。

## 2. 为什么不能复用 `modules/workstation.nix`

`modules/workstation.nix` 是 NixOS 工作站模块，它导入了 core、keyd、desktop、
zsh、cli、dev 和 NixOS Home Manager。里面包含很多 macOS 不存在的选项：

- NixOS systemd 服务、systemd-boot 和 zramSwap
- SDDM、Hyprland、PipeWire
- Fcitx5 Wayland text-input 接线
- Linux keyd 服务
- AMD GPU 的 `/sys/class/drm` 和 udev 规则
- Btrfs、休眠和 NixOS 硬件配置

所以本次新增 `modules/darwin/`，只把 macOS 需要的部分单独声明，而不是把
Linux 工作站模块改造成一个两边都能用的巨大条件分支。

## 3. 当前文件结构

```text
hosts/macbook-m1-max/configuration.nix
modules/darwin/base.nix
modules/darwin/packages.nix
modules/darwin/homebrew.nix
modules/darwin/defaults.nix
modules/home-manager/darwin-user.nix
```

### 主机入口

`hosts/macbook-m1-max/configuration.nix` 只声明：

- `aarch64-darwin`
- 主机名
- Darwin 模块
- Darwin 版 Home Manager
- `system.stateVersion = 6`

这里的 `system.stateVersion` 是 nix-darwin 的配置 schema 版本，不是 macOS
版本，也不是 NixOS 的 `26.05`。日常更新不要修改它。

### Darwin 基础模块

`modules/darwin/base.nix` 负责：

- Nix daemon
- flakes 和 `nix-command`
- Zsh
- Git、SSH、Neovim、chezmoi、ripgrep 等基础命令
- `EDITOR` 和 `VISUAL`

这里不启用 macOS Remote Login。以后如果需要 SSH 进入 Mac，再单独设计和验证，
不要因为 NixOS 的 `services.openssh.enable = true` 就照搬过来。当前 nix-darwin
版本会在 Nix 启用时自动管理 Nix daemon，不再需要旧式的
`services.nix-daemon.enable`。

### 软件包模块

`modules/darwin/packages.nix` 负责第一批开发和诊断工具：Python、Make、bat、
eza、btop、htop 和 Starship。它不是当前 Homebrew formula 列表的完整复制；
Homebrew 安装出来的大量底层库不应该逐项写进配置。

### Homebrew 模块

`modules/darwin/homebrew.nix` 保留当前已安装的主要 GUI cask，例如 Kitty、
Ghostty、Hammerspoon、AeroSpace、Android Studio、Bitwarden、OrbStack、VLC、
Godot 和 MonitorControl。

当前只把 `mas` 和 `ntfs-3g-mac` 保留为 Homebrew formula。普通 CLI 优先由 Nix
提供，避免同一个命令同时存在于 `/nix/store` 和 `/opt/homebrew/bin`。

主机入口中的 `system.primaryUser = "tetsuya"` 也很重要：当前 nix-darwin 的系统
激活以 root 执行，而 Homebrew 这类需要用户上下文的选项必须明确知道主要用户。

第一次激活使用：

```nix
homebrew.onActivation.cleanup = "none";
```

这表示配置不会自动删除还没有分类的旧软件。确认软件清单之后，才可以考虑收紧
清理策略。不要在不了解 `brew list` 的情况下开启清理。

### macOS defaults 模块

`modules/darwin/defaults.nix` 目前是一个空的安全边界模块。Finder、Dock、时间/单位、
Mission Control、辅助功能、输入法权限等暂时不写进去，应该先读取当前状态再逐项
声明，避免第一次激活时改变用户可见设置。

### Darwin Home Manager 模块

`modules/home-manager/darwin-user.nix` 声明 `home.stateVersion`、
`BROWSER = "open"`，并管理 macOS 专属的 AeroSpace、Karabiner、Hammerspoon、
skhd 配置以及零动画脚本。配置按文件链接，不接管 Karabiner/Hammerspoon 的整个
运行目录，因此应用自己产生的 `assets`、备份和 Spoons 仍可写入。

## 4. 第一次安装和激活

当前这台 Mac 还没有 `nix` 命令，因此仓库代码已经准备好，但还没有完成系统激活。
请在 Mac 的 Terminal.app 中亲自执行 Nix 安装器；它需要登录密码来创建 `/nix`、
Nix build users 和 LaunchDaemon，不能由无交互的 Agent 代填：

```bash
curl -L https://nixos.org/nix/install | sh -s -- --daemon
```

安装完成后重新打开终端，再执行：

```bash
cd ~/nixos-config
nix --version
nix flake check --no-build
darwin-rebuild build --flake .#macbook-m1-max
sudo darwin-rebuild switch --flake .#macbook-m1-max
```

如果 `darwin-rebuild` 尚未进入 PATH，可以使用临时入口：

```bash
sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake .#macbook-m1-max
```

第一次切换完成后检查：

```bash
command -v nix
command -v darwin-rebuild
command -v git
command -v nvim
command -v chezmoi
brew list --cask
```

然后重新打开一个登录 shell，确认 Nix profile 和 Homebrew PATH 顺序符合预期。

## 5. 日常操作

```bash
# 求值检查
nix flake check --no-build

# 只构建，不切换
darwin-rebuild build --flake .#macbook-m1-max

# 应用配置
sudo darwin-rebuild switch --flake .#macbook-m1-max

# 查看和回滚 Darwin generations
darwin-rebuild --list-generations
sudo darwin-rebuild switch --rollback
```

Darwin generation 只回滚 nix-darwin 管理的系统配置。Homebrew 应用数据、用户
目录、浏览器 profile、Agent session 和外部模型不会随它自动回滚。

## 6. 三个仓库的边界

| 内容 | 归属 |
|---|---|
| Nix、Darwin 系统包、Homebrew 声明、macOS defaults | `nixos-config` |
| NixOS 内核、硬件、systemd、Hyprland、Fcitx5、keyd | `nixos-config` |
| 跨平台 Shell、Neovim、终端配置、Rime、Voxtype、Agent | `chezmoi` / `dotfiles` |
| macOS 专属 AeroSpace、Karabiner、Hammerspoon、skhd | Darwin Home Manager |
| 密钥、Token、`.env`、Bitwarden session | 不进本仓库 |
| 浏览器 profile、模型、缓存、项目构建产物 | 不进系统 flake |

同一个目标文件只能有一个所有者。例如：

```text
软件包由 nix-darwin 管
~/.config/nvim/init.lua 由 dotfiles 管
~/.config/omarchy/... 由 chezmoi 管
~/.config/aerospace/aerospace.toml 由 Darwin Home Manager 管
~/.config/karabiner/karabiner.json 由 Darwin Home Manager 管
~/.hammerspoon/init.lua 由 Darwin Home Manager 管
Hammerspoon/Karabiner 权限由 macOS Settings 管
```

不能让 Home Manager 和 chezmoi 同时生成 `~/.config/nvim/init.lua`。

## 7. 目前明确不迁移的内容

### keyd

`modules/keyd.nix` 是 Linux 服务。macOS 继续使用现有 Karabiner、Hammerspoon
或其他 macOS 原生方案，不应该尝试通过 nix-darwin 启动 keyd。

### Fcitx5

NixOS 中的 Fcitx5 依赖 Wayland text-input、GTK/Qt bridge 和 Linux 会话。macOS
的输入法、Rime 数据和权限继续由现有 chezmoi/macOS 流程管理。

### Voxtype、本地模型和 Agent

这些内容涉及用户级权限、模型路径、音频输入、密钥和私有编排。先保持现状，等
软件包和权限边界明确后，再决定是 Homebrew、Nix package 还是 chezmoi user service。

### 本次已迁移的 macOS 用户配置

以下内容已从 `~/chezmoi` 移到 `modules/home-manager/darwin-files/`：

- AeroSpace：`~/.config/aerospace/aerospace.toml`；
- Karabiner：`~/.config/karabiner/karabiner.json`；
- Hammerspoon：`~/.hammerspoon/init.lua`；
- skhd：`~/.skhdrc`；
- 零动画脚本：`~/.local/bin/macos-zero-animation`。

这些是 macOS 专属内容，不应再通过 `chezmoi apply` 生成。Karabiner/Hammerspoon
运行目录中的缓存、自动备份和 Spoons 不进入 Git，也不由 Home Manager 覆盖。

## 8. Homebrew 与 Nix 的重复问题

迁移期间可能看到两个相同命令：

```bash
which -a git
which -a nvim
which -a python3
```

处理顺序应该是：

1. 确认配置实际调用的是哪个路径；
2. 确认版本满足项目需求；
3. 确认 chezmoi、dotfiles 和脚本没有硬编码 Homebrew 路径；
4. 再决定是否删除重复的 Homebrew formula。

公共 dotfiles 应优先使用 PATH 查找程序，不要写个人机器的绝对路径。Apple Silicon
Homebrew 前缀是 `/opt/homebrew`，Intel Mac 通常是 `/usr/local`，共享脚本应该
兼容两者。

## 9. 以后增加 macOS 配置的规则

新增设置前先问：

1. 这是系统能力、用户偏好，还是秘密？
2. 它是否依赖 macOS 权限或 GUI 当前状态？
3. 它是否会和 chezmoi/dotfiles 生成同一个文件？
4. 出错时能否通过上一个 Darwin generation 回滚？

推荐分类：

```text
系统包 / Homebrew / launchd / defaults  -> nix-darwin
用户文件 / shell / Neovim / Agent       -> chezmoi 或 dotfiles
密码 / Token / session                   -> 加密存储或手工恢复
浏览器 / 模型 / 缓存 / 数据库            -> 单独备份和迁移
```

## 10. 故障排查

### `nix` 不存在

说明 Nix 还没有安装，仓库配置还没有机会求值。先安装 Nix，再运行本章第 4 节。

### `darwin-rebuild` 不存在

使用上面的 `nix run nix-darwin/...#darwin-rebuild` 临时入口。

### Homebrew 想删除旧应用

确认 `homebrew.onActivation.cleanup` 是 `"none"`。第一次迁移不应该自动清理；
先把 `brew list --formula` 和 `brew list --cask` 分成 Nix、Homebrew、手工安装三类。

### 配置求值时报 Linux 选项错误

检查 `hosts/macbook-m1-max/configuration.nix` 的 imports，只保留 `modules/darwin/`
和 `home-manager.darwinModules`，不要导入 `modules/workstation.nix` 或
`modules/desktop.nix`。

### 应用本身无法启动

Nix 成功安装软件不代表 macOS 已授予 Accessibility、Input Monitoring、麦克风、
屏幕录制或网络扩展权限。权限必须在 macOS 的 Privacy & Security 中逐项验证，
不能把“能 build”当成“用户功能完成”。

## 11. 后续阶段

1. 在 macOS 上完成 Nix 安装、flake lock 更新和首次 Darwin build；
2. 验证 CLI、Homebrew cask、chezmoi 和 dotfiles 的协作；
3. 将确实需要声明式管理的 macOS defaults 加入 `defaults.nix`；
4. 评估 launchd 服务，不把 Linux systemd 服务照搬过来；
5. 对重复的 Homebrew formula 做逐项清理；
6. 最后再考虑把少量跨平台用户配置迁移到 Home Manager。

在这些步骤完成以前，不要删除现有 Homebrew 软件、chezmoi 模板、Rime 数据、
浏览器 profile 或 Agent 配置。

## 12. 本次接入的实际验证记录

本次接入在 2026-09-07 进行了以下验证：

```text
Nix: 2.35.2
Darwin build: 通过
Darwin output: .#darwinConfigurations.macbook-m1-max.system
首次 switch: 已完成；macOS 专属配置迁移与运行时目录恢复已完成
```

Darwin build 实际生成了 nix-darwin 26.05 的 system derivation，并验证了：

- `aarch64-darwin` 平台求值成功；
- Home Manager Darwin module 求值成功；
- Homebrew Brewfile 生成成功；
- Nix、Zsh、基础 CLI 和开发工具的 system path 求值成功；
- nix-darwin 的 launchd、Nix daemon 和 activation derivation 生成成功。

完整的：

```bash
nix flake check --no-build
```

目前还会在原有 NixOS/Nixarchy 配置上遇到失效的 `/nix/store/...-source` 路径，
错误位于既有的 `modules/home-manager/nixos-user.nix` / Nixarchy 求值链，不是
本次 Darwin 模块的错误。Darwin 专用 build 已单独通过，因此后续应分别记录：

```bash
# macOS 接入的直接验证
nix build .#darwinConfigurations.macbook-m1-max.system --no-link

# 全仓库验证；如果旧 NixOS store 缓存问题仍存在，按错误单独修复
nix flake check --no-build
```

首次 `switch` 已经由用户在本机 Terminal.app 中完成。Homebrew、Home Manager
和 launchd activation 都已执行成功。Karabiner、AeroSpace、Hammerspoon 和
skhd 的静态配置已由 Darwin Home Manager 接管；Karabiner/Hammerspoon 的运行时
目录已从迁移备份恢复。更详细的学习材料见
[`macos-nix-darwin/README.md`](macos-nix-darwin/README.md)。

以后如果需要重新激活，使用：

```bash
sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake .#macbook-m1-max
```

切换完成后，再验证 `darwin-rebuild --list-generations`、`command -v nvim`、
`brew list --cask`、新开登录 shell，以及现有 chezmoi/dotfiles 配置是否仍正常。
