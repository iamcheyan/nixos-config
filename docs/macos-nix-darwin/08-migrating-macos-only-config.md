# macOS 专属配置迁移记录

这次迁移的目标是：让 `~/chezmoi` 尽量只保留可以跨 Linux、WSL 和其他 Unix
环境复用的用户配置；只属于 macOS 的配置放到本仓库的 Darwin Home Manager。

## 当前归属

| 内容 | 源文件 | 目标 | 管理者 |
|---|---|---|---|
| AeroSpace | `modules/home-manager/darwin-files/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` | Darwin Home Manager |
| Karabiner | `modules/home-manager/darwin-files/karabiner/karabiner.json` | `~/.config/karabiner/karabiner.json` | Darwin Home Manager |
| Hammerspoon | `modules/home-manager/darwin-files/hammerspoon/init.lua` | `~/.hammerspoon/init.lua` | Darwin Home Manager |
| skhd | `modules/home-manager/darwin-files/skhdrc` | `~/.skhdrc` | Darwin Home Manager |
| 零动画脚本 | `modules/home-manager/darwin-files/scripts/macos-zero-animation.sh` | `~/.local/bin/macos-zero-animation` | Darwin Home Manager |

## 这次实际做了什么

1. 检查了 chezmoi 源目录和当前用户目录的差异。
2. 发现 Karabiner 的 `assets`、`automatic_backups` 和 Hammerspoon 的 `Spoons`
   是应用运行时生成的数据，不是应该进入 Nix store 的静态配置。
3. 将版本化配置从 `~/chezmoi` 移到本仓库。
4. 将原来的 live 目录完整备份到：

   ```text
   ~/Library/Application Support/nixos-config/migration-backups/20260907-220647
   ```

5. Home Manager 只管理每个应用的静态配置文件，不把整个应用目录做成链接。
6. 更新 chezmoi 的 `AGENTS.md`、`README.md` 和 macOS fallback 安装脚本，避免
   以后重新把这些文件加回 chezmoi。

## 为什么不管理整个目录

Home Manager 管理目录时通常会把目标链接到 `/nix/store`。Nix store 是只读的，
而 Karabiner/Hammerspoon 需要在同一个目录中写入备份、资源和扩展。若整个目录
被链接，可能出现“应用能读取配置但不能保存设置”的问题。

因此 `darwin-user.nix` 只声明单个文件；应用自己产生的运行时目录仍保持可写。

## 日常修改方式

推荐直接编辑 flake 源文件：

```bash
cd ~/nixos-config
nvim modules/home-manager/darwin-files/karabiner/karabiner.json
```

先构建，再切换：

```bash
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
sudo /run/current-system/sw/bin/darwin-rebuild switch --flake .#macbook-m1-max
```

Karabiner GUI 可能会直接写目标文件。由于该文件现在由 Home Manager 链接到 Nix
store，长期维护时应以仓库源文件为准；GUI 更适合查看状态、测试权限和观察事件。

## 权限不属于 Nix 配置

以下权限仍要在 macOS 设置中人工确认：

- Karabiner-Elements 的 Accessibility 和 Input Monitoring；
- Hammerspoon 的 Accessibility；
- AeroSpace 的 Accessibility；
- skhd 如果启用，也需要相应的辅助功能权限。

Nix 只能安装程序和部署文件，不能安全地替用户修改 TCC 权限数据库。

## 零动画脚本的特别说明

`~/.local/bin/macos-zero-animation` 只是一个可手动执行的工具，不会在
`darwin-rebuild switch` 时自动执行。它会修改 Dock、Finder、Control Center 和
全局窗口动画设置，并重启相关进程。需要时手动运行：

```bash
~/.local/bin/macos-zero-animation
```

这类 `defaults write` 不应直接塞进 Home Manager activation，因为它们会产生
用户可见的系统行为变化，不适合在每次切换 generation 时重复执行。

## 迁移后的检查清单

- `git -C ~/chezmoi status --short` 没有意外修改；
- `nix build` 成功；
- `darwin-rebuild switch` 成功；
- 新终端中相关目标文件的 `readlink` 指向 `/nix/store`；
- `~/.config/karabiner/automatic_backups` 和 `~/.hammerspoon/Spoons` 仍可用；
- 在真实应用中测试 AeroSpace、Karabiner 和 Hammerspoon；
- 不执行 `chezmoi add` 把这些 macOS 专属文件重新收回去。

## 如果需要撤销迁移

不要直接删除 Nix generation。先停止 Home Manager 对应声明，然后从备份目录恢复
原来的 live 目录，再决定是否把源文件放回 chezmoi。当前备份是可恢复的，迁移
没有提交任何不可逆的删除操作。
