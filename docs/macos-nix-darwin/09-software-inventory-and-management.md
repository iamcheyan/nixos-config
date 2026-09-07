# Mac 软件清单与声明式管理

本文记录如何把手动安装的软件逐步纳入 `nixos-config`。目标不是把所有内容
强行塞进 Nix，而是让每个软件有一个清晰、可复现、可验证的安装来源。

## 三种安装来源

### Nix package

适合 CLI 和开发工具，例如 `neovim`、`ripgrep`、`jq`、`python3`。声明在：

```text
modules/darwin/base.nix
modules/darwin/packages.nix
```

结果会出现在：

```text
/run/current-system/sw/bin
```

### Homebrew cask

适合普通 macOS GUI 应用，例如 Firefox、Chrome、Claude、UTM、Zed。声明在：

```text
modules/darwin/homebrew.nix
```

应用本体通常位于：

```text
/Applications
```

### Mac App Store

通过 `mas` 管理，声明在同一个 `homebrew.nix` 的 `homebrew.masApps`：

```nix
masApps = {
  "Telegram" = 747648890;
};
```

需要登录 Mac App Store，并且当前账号必须拥有对应软件。

## 本次纳管的软件

本次从 `/Applications` 和 `~/Applications` 盘点后，将存在 Homebrew Cask 的 GUI
应用加入了 `homebrew.casks`：

- Alacritty；
- AppCleaner；
- balenaEtcher；
- Cap；
- Claude；
- coconutBattery；
- CrystalFetch；
- Dropbox；
- Firefox；
- Google Chrome；
- Google Drive；
- GrandPerspective；
- HHKB Studio；
- iTerm2；
- Keka；
- Maccy；
- Microsoft Office；
- Nextcloud；
- OneDrive；
- OpenMTP；
- Snipaste；
- Tailscale；
- TigerVNC；
- UTM；
- Upscayl；
- Visual Studio Code；
- Zed；
- Zoom。

原来已经在 nix-darwin 中声明的 AeroSpace、Android 工具、Bitwarden、Ghostty、
Godot、Hammerspoon、Kitty、OrbStack、VLC 等保持不变。

Mac App Store 的当前安装列表也已经加入 `masApps`，包括 Telegram、微信、QQ、
Excel、WhatsApp、Windows App、迅雷和其他当前已安装项目。

## 为什么不是直接读取 `/Applications`

`/Applications` 只告诉我们“现在有什么”，不能告诉 Nix：

- 软件从哪里下载；
- 软件是否有合法的 Homebrew Cask；
- 当前 App 是否来自 App Store；
- 软件是否需要安装驱动或系统扩展；
- 重新安装时是否需要登录、许可证或特殊安装器。

因此管理流程是：

```text
扫描当前应用
    ↓
查找 Homebrew Cask / Mac App Store / Nix 来源
    ↓
确认应用名称和来源匹配
    ↓
写入声明
    ↓
build
    ↓
switch
    ↓
实际启动应用并验证权限、账号和插件
```

## 首次接管手动安装的 App

如果一个 App 已经手动放在 `/Applications`，但现在要改由 Homebrew Cask 管理，
不要先删除它。先检查 Cask：

```bash
brew info --cask firefox
```

然后加入 `homebrew.casks`，构建并激活：

```bash
cd ~/nixos-config
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
sudo /run/current-system/sw/bin/darwin-rebuild switch --flake .#macbook-m1-max
```

Homebrew 对已经存在的 App 可能会：

- 识别为已安装；
- 接管相同的应用文件；
- 因签名、版本或路径不一致而要求人工处理。

遇到冲突时，不要使用 `--force` 盲目覆盖。先备份应用和配置，再单独处理该软件。

## 当前明确没有自动纳管的项目

以下类型暂时保留手动管理：

- Adobe Acrobat/Photoshop 等大型 Adobe 安装器；
- Safari Web App；
- Seedmux、Hex、Miyako 等个人或定制工具；
- 某些厂商独立下载的驱动、系统扩展和硬件工具；
- 当前名称和 Cask 不确定的 OpenAI/Codex 图形应用；
- 应用本身没有 Homebrew Cask、Nix package 或 App Store 来源的项目。

它们不是“丢失”，而是明确标记为手动安装。以后如果确认有稳定的官方来源，
再加入声明。

## Homebrew 的清理策略

当前配置是：

```nix
onActivation = {
  cleanup = "none";
  autoUpdate = false;
  upgrade = false;
};
```

这意味着：

- 加入声明会安装缺失的软件；
- 不会因为声明不完整而删除其他软件；
- `darwin-rebuild switch` 不会自动升级所有 Homebrew 软件；
- App Store 应用从 `masApps` 删除后，也不会自动卸载。

这是迁移期的安全设置。只有经过完整盘点，并确认某软件不再需要，才考虑收紧
cleanup 策略。

## 软件本体和应用数据是两回事

即使软件本体已经由 Nix/Homebrew 管理，以下内容仍然可能是手动状态：

- 登录会话和 Cookie；
- License 和订阅状态；
- 浏览器 profile；
- 项目数据库和缓存；
- Hammerspoon Spoons、Karabiner backups；
- Accessibility、Input Monitoring、网络扩展权限；
- App Store 购买资格。

不要把这些数据目录直接放入 Nix store，也不要为了“完整声明”而把密码、Token
或 session 提交到 Git。

## 日常检查命令

查看 Nix 系统包：

```bash
ls /run/current-system/sw/bin
```

查看 Homebrew cask：

```bash
brew list --cask
```

查看 App Store：

```bash
mas list
```

检查某个 GUI 软件是否有 Cask：

```bash
brew search --cask 软件名
brew info --cask 软件名
```

检查软件最终由哪个路径提供：

```bash
type -a 软件命令
```

## 新增软件的推荐流程

1. 先判断是 CLI、GUI 还是 App Store 软件；
2. 优先查 Nix package 或 Homebrew Cask；
3. App Store 软件记录数字 ID；
4. 加入对应模块；
5. `nix build`；
6. `darwin-rebuild switch`；
7. 启动真实应用，验证权限、登录、插件和文件关联；
8. 再提交 Git。

不要把同一个软件同时写进 Nix、Homebrew formula 和 Homebrew cask。一个软件本体
应该只有一个主要安装来源。
