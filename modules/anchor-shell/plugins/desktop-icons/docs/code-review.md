# Desktop Icons 插件代码审查与重构计划

本文档记录 Anchor Shell 当前内置的
`desktop-icons` 插件审查结果。插件最初来自上游 Omarchy 插件，后来
加入了 Anchor Shell、Labwc、多显示器、网格布局、框选和安全校验逻辑。

后续修改以本文档为基准。除非明确说明，本文档只描述计划，不代表对应功能
已经完成。

## 当前范围

主要文件：

- `Service.qml`：插件服务、索引、持久化状态、动作和全局选择。
- `DesktopSurface.qml`：单个显示器的 PanelWindow、输入区域和布局视图。
- `DesktopIcon.qml`：单个图标、标签、拖拽和双击。
- `IconContextMenu.qml`：图标右键菜单。
- `TrustPrompt.qml`：不受信任启动器确认框。
- `DragGhost.qml`：跨显示器拖拽预览。
- `DesktopLayout.js`：持久化网格模型和跨屏移动逻辑。
- `bin/desktop-index`：桌面索引、安全校验、打开、删除、重命名和放置文件。
- `bin/add-to-desktop`：创建快捷方式或复制文件到桌面。
- `bin/create-hyperlink`：创建和打开 `.url` 快捷方式。
- `dolphin/send-to-desktop.desktop`：Dolphin 服务菜单入口。

## 必须优先修复的问题

### 1. 跨屏目标格交换不完整

状态：已修复（2026-09-23）。

`DesktopLayout.moveToScreen()` 在目标屏格子被占用时，把目标图标写回目标屏，
但使用了源屏坐标：

```js
next.screens[toScreen][targetId] = sourceCell
```

这不是完整的跨屏交换。两块屏尺寸或行数不同时，目标图标可能落到错误位置、
屏幕外或再次发生碰撞。

目标行为应明确为以下之一：

1. 空目标格：图标移动到目标屏，源屏留下空格；
2. 已占用目标格：目标图标移动到源图标原来的屏幕和格子，两个图标交换归属；
3. 或者明确采用 Windows 的重新排布策略，但必须由纯布局模型统一决定。

`DesktopLayout.moveToScreen()` 现在在跨屏目标格被占用时，会把目标图标
移动到源屏的原始格子，同时把拖拽图标放到目标屏；空目标格仍只移动拖拽图标。
同屏调用也保留交换行为，避免模型在边界情况下产生重复归属。

回归覆盖已加入 `tests/test_layout_model.js`：空目标格、跨屏占用目标格和同屏
边界调用均有断言。实际显示器上的拖拽仍需按文档末尾的手工检查执行。

### 2. 所有显示器共用第一块屏的网格参数

状态：已修复（2026-09-23）。

`Service.qml` 的 `reconcileLayout()` 将
`Quickshell.screens[0]` 的 grid 传给整个布局模型。`DesktopLayout.repair()`
也只接收一份 grid。

这在两块显示器高度、缩放或顶部栏尺寸不同的时候不正确。现在已改成：

```text
screenName -> { left, top, cellW, cellH, rows }
```

`Service.qml` 为每个输出建立 `screenName -> grid` 映射，
`DesktopLayout.normalize()`、迁移和重复格修复按屏幕使用对应 grid。像素坐标只在
UI 层转换，状态文件继续保存逻辑网格坐标；旧的单一 grid 调用仍可兼容。
布局测试已覆盖不同 `rows` 的两个显示器。

### 3. 位置文件自写事件不能只用计数抵消

状态：已修复（2026-09-23）。

`savePositions()` 通过 `positionWrites` 计数来忽略 `FileView` 的变化事件。
原子写入可能产生多个事件、合并事件或事件顺序变化，计数可能残留，导致之后
的外部修改被错误忽略。

现在保存最后一次写入的规范化 JSON：

1. 写文件前记录规范化内容；
2. 文件变化时读取并比较实际内容；
3. 内容与本地最近一次写入相同则忽略；
4. 内容不同才重新加载，不再依赖事件计数。

## 可以直接删除的不可达功能

状态：已修复（2026-09-23）。

空白桌面右键现在由 Labwc 原生菜单处理，插件自己的空白菜单已经没有实际
入口。`emptyMouse.onPressed` 会直接调用 `showRootMenu()`，因此下面这条链
是遗留代码：

- `openEmptyMenu()`；
- `menuKind === "empty"` 分支；
- `folder`、`shortcut`、`pin`、`addfiles`、空白菜单的 `refresh` 动作；
- `newFolder()`；
- `newShortcut()`；
- `pinApp()`；
- `addFiles()`；
- `addScript` 属性；
- `hyperlinkScript` 属性。

删除后，菜单只保留图标右键菜单和信任提示菜单。

另外，以下内容也确认没有有效调用者：

- `padRight` 属性；
- `layoutPos()` 函数；
- “点击空白桌面五次切换壁纸”的 `emptyClicks`、计时器和
  `switchWallpaper()`。

五连击壁纸功能已删除；壁纸切换仍由 `Super+Ctrl+Space` 提供，避免桌面空白
点击产生隐藏副作用。

## 上游文件管理器集成清理

状态：已修复（2026-09-23）。

当前系统新增了 Dolphin 的 KIO 服务菜单，并通过 Nix 提供
`add-to-desktop` wrapper。Nautilus 扩展已经删除，README 只保留 Dolphin 说明。

删除插件空白菜单后，`bin/add-to-desktop` 中只供 GTK 文件选择器使用的部分也
已经删除：`pick_paths()`、`--pick-app`、`--pick-files` 和 GTK4/Adwaita
文件选择器依赖。

Dolphin 服务菜单仍需要普通路径参数和 `--copy`。

## 需要确认后再处理的功能

### `.url` 超链接支持

状态：保留并明确为受支持功能（2026-09-23）。

`bin/create-hyperlink` 约 488 行，包含完整 GTK/Adwaita 窗口。网页快捷方式仍由
该工具支持，因此本轮不删除它。若后续确认不再需要 `.url`，
再整体删除并同步删除：

- `.url` 创建和打开逻辑；
- `desktop-index` 的 `.url` 分支；
- 对应测试和文档。

如果仍需要 `.url`，建议将打开逻辑合并进 `desktop-index`，把创建逻辑改成
独立且更小的 UI 工具，不要让主桌面服务依赖这套完整窗口代码。

### Trash 特殊处理

状态：保留（2026-09-23）。

Trash 图标识别、拖入 Trash 和右键 Trash 菜单是 Windows 风格桌面体验的一部分，
本轮确认保留，不删除。

### 预览图片和上游发布说明

状态：已清理（2026-09-23）。

仓库预览图片只服务于独立发布页，不参与 Anchor Shell 运行时；本地副本不再
保留该图片。上游仓库和原始插件路径记录在
[README.md](../README.md) 的“Upstream source and local maintenance”章节中。

`LICENSE` 和 `manifest.json` 继续保留。前者用于保留上游许可和归属，后者用于
Anchor Shell 插件加载。

## 结构优化

状态：已完成（2026-09-23）。

保留 `DesktopLayout.js` 作为纯函数模型，但把 `Service.qml` 拆成几个组件：

```text
Service.qml          # 索引、状态、动作和全局选择
DesktopLayout.js     # 纯网格模型
DesktopSurface.qml   # 单个显示器的 PanelWindow 和输入区域
DesktopIcon.qml      # 单个图标、标签、拖拽和双击
IconContextMenu.qml  # 图标右键菜单
TrustPrompt.qml      # 不受信任启动器确认框
DragGhost.qml        # 跨显示器拖拽预览
```

已按上述边界拆分，并保持以下约束：

- 持久化状态只由 `Service.qml` 管理；
- 网格交换、迁移和修复只由 `DesktopLayout.js` 管理；
- 图标组件不直接写状态文件；
- 菜单组件通过显式信号调用服务动作；
- 每个显示器使用自己的 grid，不读取其他显示器的像素参数。

## 性能和稳定性优化

### 减少无效轮询

状态：已修复（2026-09-23）。

当前 Desktop 目录已经有 `FileView` 监听，同时还有兜底 Python 索引轮询。目录
监听正常时，绝大多数轮询是无效的。现在：

- 监听事件通过 100ms debounce 合并连续事件；
- 兜底轮询改为 30 秒；
- `Process.running` 期间不再启动新的索引进程。

### 保持 Repeater 稳定

状态：已完成（2026-09-23，既有实现已验证）。

当前已经通过 `visibleItems`、`itemsMatch()` 和 `refreshVisibleItems()` 避免
纯位置变化时重建所有 delegate。后续不要把它改回每次计算新数组的直接绑定。

图标位置变化应只更新 delegate 的 `x/y`，不应重新创建图片、标签和鼠标区域。

### 图标加载规则

- SVG 主题图标同步加载；
- 不使用会缓存失败结果的异步 SVG 加载；
- 用户提供的 SVG/GIF 仍由 Python 安全层拒绝；
- 栅格预览才设置 `sourceSize`；
- 主题图标失败时显示同步 fallback。

## 测试补充计划

状态：已完成（2026-09-23）。布局测试已补充模型层覆盖；实际拖拽和右键仍按
手工清单验证。

现有测试覆盖：

- 同屏拖入空格；
- 同屏拖入已占用格并交换；
- 跨屏拖入空格；
- 跨屏拖入已占用格并交换归属；
- 两块显示器高度和缩放不同时的修复；
- 断开第二屏后合并显示；
- 第二屏恢复后原归属恢复；
- 单屏期间主动拖动图标后的归属变化；
- 旧版像素坐标迁移；
- 重复格修复；
- 外部修改位置文件不会被本地写入内容比较吞掉；
- 空白右键转发 Labwc，图标右键仍打开插件菜单。

每次修改后至少运行：

```bash
node tests/test_layout_model.js
ANCHOR_PY=$(sed -n '2p' /run/current-system/sw/bin/add-to-desktop | awk '{print $2}')
"$ANCHOR_PY" tests/test_desktop_index.py
qmlformat Service.qml DesktopSurface.qml DesktopIcon.qml IconContextMenu.qml TrustPrompt.qml DragGhost.qml
nix flake check --impure --no-build
```

同时确认：

```bash
quickshell list --all
```

运行实例必须只有一个。跨屏拖拽需要实际观察拖拽过程，不能只看位置 JSON。

## 推荐执行顺序

1. ~~修复 `moveToScreen()` 的跨屏交换和每屏独立 grid。~~
2. ~~增加布局回归测试。~~
3. ~~删除不可达空白菜单、五连击壁纸和无效属性。~~
4. ~~根据实际文件管理器删除 Nautilus 集成和 GTK 选择器。~~
5. ~~确认保留 `.url`，保留 `create-hyperlink`。~~
6. ~~将 `Service.qml` 拆成显示器、图标、菜单、信任框和拖拽 ghost 组件。~~
7. ~~降低索引轮询频率并完善位置文件内容比较。~~
