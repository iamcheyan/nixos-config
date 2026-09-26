# Quickshell 插件迁移

剪贴板与 Voxtype 插件已从本目录的 `third-party/` 迁入
`modules/anchor-shell/plugins/clipboard/` 和
`modules/anchor-shell/plugins/voxtype/`，随后删除了 Quickshell 的旧源码副本。
它们的 manifest ID 保持为 `iamcheyan.clipboard` 与
`hancore.voxtype-enhance`；当前 Labwc 会话由 Anchor Shell 加载这两个插件。

插件注册器的搜索顺序保持为：

1. Quickshell 仓库内的 first-party 源；
2. `~/.config/omarchy/plugins/` 旧路径；
3. `~/.config/quickshell/plugins/` 新用户插件路径。

旧的 Omarchy 用户插件目录作为兼容扫描路径保留。
