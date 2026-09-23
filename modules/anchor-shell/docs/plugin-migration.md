# Quickshell 插件迁移

当前使用和维护中的用户插件已经纳入本仓库的 Anchor Shell 源码树：

- `hancore.overview-workspaces`
- `hancore.voxtype-enhance`（源码位于 `modules/anchor-shell/plugins/voxtype/`）
- `iamcheyan.active-window`
- `iamcheyan.clipboard`（`modules/anchor-shell/plugins/clipboard/`）
- `iamcheyan.launcher`
- `iamcheyan.lock-screen`

插件的 manifest、目录结构、入口文件和原有 ID 保持不变，因此
`shell.json` 中的 `omarchy.*`、`iamcheyan.*`、`hancore.*` 名称继续有效。
仓库内的 `iamcheyan.clipboard` 保留了本地 Labwc 多屏定位和 backend 修复，
不会被用户目录中的旧副本覆盖。

插件注册器的搜索顺序为：

1. `modules/anchor-shell/plugins/`：仓库维护的全部插件；
2. `~/.config/anchor-shell/plugins/`：用户安装的插件。

迁移期间仍保留旧路径，方便逐个比较和回退。后续验证完成后，才会考虑停止
读取旧的 Omarchy 用户插件目录。
