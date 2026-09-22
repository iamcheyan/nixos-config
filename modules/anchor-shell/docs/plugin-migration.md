# Quickshell 插件迁移

当前使用和维护中的用户插件已经纳入本仓库的
`modules/anchor-shell/third-party/`：

- `hancore.overview-workspaces`
- `hancore.voxtype-enhance`
- `iamcheyan.active-window`
- `iamcheyan.clipboard`
- `iamcheyan.launcher`
- `iamcheyan.lock-screen`

插件的 manifest、目录结构、入口文件和原有 ID 保持不变，因此
`shell.json` 中的 `omarchy.*`、`iamcheyan.*`、`hancore.*` 名称继续有效。
仓库内的 `iamcheyan.clipboard` 保留了本地 Labwc 多屏定位和 backend 修复，
不会被用户目录中的旧副本覆盖。

插件注册器的搜索顺序保持为：

1. Quickshell 仓库内的 first-party/third-party 源；
2. `~/.config/omarchy/plugins/` 旧路径；
3. `~/.config/quickshell/plugins/` 新用户插件路径。

迁移期间仍保留旧路径，方便逐个比较和回退。后续验证完成后，才会考虑停止
读取旧的 Omarchy 用户插件目录。
