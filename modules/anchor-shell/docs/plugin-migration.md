# 插件归属

Anchor Shell 扫描两个根：

1. `modules/anchor-shell/plugins/`：仓库维护的全部插件
2. `~/.config/anchor-shell/plugins/`：用户安装的插件

不扫描 `~/.config/omarchy/plugins/`。那是 Hyprland 的目录。

迁入本目录后，manifest ID 保持不变，现有 `shell.json` 继续有效：

| 源码目录 | Runtime ID |
|---|---|
| `plugins/clipboard/` | `iamcheyan.clipboard` |
| `plugins/voxtype/` | `hancore.voxtype-enhance` |
| `plugins/desktop-icons/` | `desktop-icons` |
| `plugins/lock/` | `omarchy.lock` |
| `plugins/launcher/` | `iamcheyan.launcher` |
| `plugins/bar/widgets/` | `omarchy.workspaces`、`omarchy.active-window` 等 |

`hancore.overview-workspaces` 和独立的 `iamcheyan.active-window` 仓库副本
已经去掉。现行工作区和活动窗口是 `plugins/bar/widgets/` 里的 first-party
组件。
