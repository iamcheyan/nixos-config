# macOS 配置的 Home Manager 管理审计

> 审计日期：2026-09-07

## 结论

当前 Darwin Home Manager 已经管理：

| 配置 | 目标路径 |
|---|---|
| AeroSpace | `~/.config/aerospace/aerospace.toml` |
| Karabiner-Elements | `~/.config/karabiner/karabiner.json` |
| Hammerspoon | `~/.hammerspoon/init.lua` |
| 当前 skhd 入口 | `~/.skhdrc` |
| macOS 动画脚本 | `~/.local/bin/macos-zero-animation` |

本次重新核对后，之前遗漏的优先项是：

1. `chezmoi/dot_config/executable_dot_yabairc`：旧 yabai 配置，应归档或清理。
2. `chezmoi/dot_config/scripts/iCloud/icloud-backup.sh`：明确的 macOS 专属维护脚本，适合迁移到 Darwin Home Manager。
3. `dot_config/aerospace/`：当前 chezmoi 工作树和 Git 跟踪列表中已经不存在；当前 AeroSpace 配置由 Home Manager 接管。

## 重要的路径辨析

`chezmoi` 使用 `dot_config` 表示目标目录 `~/.config`。因此：

```text
源文件：chezmoi/dot_config/executable_dot_yabairc
目标：  ~/.config/.yabairc
```

它不是 `~/.yabairc`。无论目标路径是哪一个，这份配置都调用 `yabai -m`，而现在窗口管理已经统一使用 AeroSpace，所以它属于旧的 macOS 专属配置，不应继续作为公共用户配置保留。

确认路径和所有者：

```bash
chezmoi source-path "$HOME/.config/.yabairc"
chezmoi source-path "$HOME/.yabairc"
ls -ld "$HOME/.config/aerospace"
```

## 优先项一：旧 yabai 配置

源文件：

```text
~/chezmoi/dot_config/executable_dot_yabairc
```

它包含 `yabai -m config`、`bsp` 布局、窗口间距以及 `sudo yabai --load-sa` 相关内容，属于纯 macOS 配置，并且与当前 AeroSpace 方案重复。

当前建议：

- 不要迁移到 Home Manager 继续启用；
- 先确认 yabai 进程、Homebrew 包和 LaunchAgent 都没有使用它；
- 保留一份 Git 历史即可，工作配置从 chezmoi 中清理；
- 如果确实需要回退 yabai，再从 Git 历史恢复，而不是让两套窗口管理器同时存在。

检查命令：

```bash
pgrep -alf yabai
brew list --formula | grep -E '^yabai$'
launchctl list | grep -i yabai
```

注意：`~/.config/.skhdrc` 也是旧配置；当前真正的 `~/.skhdrc` 已由 Home Manager 管理，不能把这两份同时交给不同工具。

## 优先项二：iCloud 到 NAS 备份脚本

源文件：

```text
~/chezmoi/dot_config/scripts/iCloud/icloud-backup.sh
```

它具有明确的 macOS-only 特征：

- 使用 `~/Library/Mobile Documents/com~apple~CloudDocs`；
- 使用 `/Volumes/NAS/Backups/iCloud`；
- 明确检查 `uname -s == Darwin`；
- 使用 `rsync --delete` 将 iCloud Drive 同步到 NAS。

这类“macOS 专属、静态脚本、需要随 Darwin 主机一起部署”的内容，确实适合迁移到：

```text
modules/home-manager/darwin-files/scripts/icloud-backup.sh
```

并通过 Home Manager 部署为：

```text
~/.local/bin/icloud-backup.sh
```

迁移前必须注意 `rsync --delete` 是有破坏性的：目标 NAS 目录必须确认正确挂载，不能把“未挂载时的错误路径”当作备份目标。当前脚本已经有目录存在检查，但实际迁移后仍要先用 `bash -n` 和一次不带 `--delete` 的 dry-run 验证。

推荐迁移流程：

```bash
mkdir -p /tmp/icloud-backup-migration
cp ~/chezmoi/dot_config/scripts/iCloud/icloud-backup.sh \
  /tmp/icloud-backup-migration/icloud-backup.sh
bash -n /tmp/icloud-backup-migration/icloud-backup.sh
```

然后把内容放进 Nix 仓库源文件，增加：

```nix
home.file.".local/bin/icloud-backup.sh" = {
  source = ./darwin-files/scripts/icloud-backup.sh;
  executable = true;
};
```

成功 `build`、`switch` 并验证新脚本后，再从 chezmoi 删除旧源文件。不能先删除 chezmoi 源文件再验证 Home Manager，否则会出现脚本暂时消失的窗口。

## 优先项三：AeroSpace 残留

目前本机实测：

- `~/chezmoi` 中没有 `dot_config/aerospace/`；
- `git ls-files` 没有 AeroSpace 路径；
- `~/.config/aerospace/aerospace.toml` 是指向 Nix store 的 Home Manager 链接。

因此当前不需要再次迁移 AeroSpace。若在旧报告或旧提交中看到 `dot_config/aerospace/`，应把它视为已完成迁移的历史痕迹；不要重新添加到 chezmoi。

检查命令：

```bash
cd ~/chezmoi
git ls-files | rg '(^|/)aerospace' || true
ls -l ~/.config/aerospace/aerospace.toml
```

## 其他配置的归属

### 适合共享 Home Manager，但不应放进 Darwin 专属模块

Zed、Kitty、Ghostty、Neovim、tmux、Zellij、Yazi、Starship、Ranger、Vifm 都是跨平台配置。它们技术上可以用 Home Manager 管理，但应新建共享模块，同时给 NixOS 和 macOS 导入：

```text
modules/home-manager/common/
├── shell.nix
├── terminal.nix
├── editor.nix
└── cli-tools.nix
```

当前这些配置已经分别属于公共 `dotfiles` 或私人 `chezmoi`，暂不迁移，避免出现两个所有者。

### 继续由 chezmoi 管理更合适

以下内容含有私人编排、模板或机器差异：

- `~/.config/opencode`；
- `~/.config/hex`；
- `~/.config/omnyssh`；
- `~/.zshrc` 及其 shell 启动链；
- Agent 脚本、aliases 和私有环境变量。

### 不应作为普通 Home Manager 文件

不要把下面这些内容提交或直接接管：

- Token、API Key、SSH 私钥、`.env`；
- Codex/浏览器/应用登录状态；
- `chezmoistate.boltdb`；
- 应用数据库、索引、缓存、日志；
- Karabiner/Hammerspoon 的运行时目录；
- macOS 辅助功能、输入监控、麦克风等 TCC 权限；
- App Store 沙盒和应用账户状态。

Home Manager 能管理文件和部分 LaunchAgent，但不能代替 macOS 的授权流程。

## 推荐执行顺序

1. 先清理或归档旧 yabai 源文件。
2. 把 iCloud 备份脚本迁移到 Darwin Home Manager，先 build，再 switch，再验证。
3. 确认 chezmoi 中没有 AeroSpace 残留。
4. 以后再单独评估 cmux、Sasayaki、Kilo 等未被管理的配置。
5. 若要迁移 Zed/Kitty/Neovim 等，建立共享 Home Manager 模块，不要塞到 Darwin-only 模块。

## 常用检查与验证

```bash
# 查看 Home Manager 链接
ls -l ~/.config/aerospace/aerospace.toml ~/.config/karabiner/karabiner.json
ls -l ~/.hammerspoon/init.lua ~/.skhdrc

# 查看 chezmoi 所有者（必须使用绝对路径）
chezmoi source-path "$HOME/.config/zed/settings.json"
chezmoi source-path "$HOME/.config/cmux/cmux.json"

# 构建但不切换
cd ~/nixos-config
nix flake check --no-build
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
```

本次审计本身没有删除、移动或覆盖任何文件；真正迁移脚本或清理 yabai 时，应继续保持“备份 → 新管理器 build → switch → 可见行为验证 → 删除旧所有者”的顺序。
