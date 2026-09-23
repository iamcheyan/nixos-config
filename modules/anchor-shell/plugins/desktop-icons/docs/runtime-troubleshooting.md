# Desktop Icons：Labwc 运行时问题与修法

这份记录对应 Anchor Shell 里的 `desktop-icons` 插件
（`modules/anchor-shell/plugins/desktop-icons/`）。
以后图标、框选、跨屏拖拽再出问题，先对照这里，不要先改 Labwc。

主实现：`Service.qml`  
格子模型：`DesktopLayout.js`  
索引脚本：`bin/desktop-index`

开发时用 `quickshell-mode dev` 直接加载这份源码。改完 QML 再跑一次
`quickshell-mode dev` 才会重启 shell。`quickshell list --all` 应只剩一个实例。

当时的显示器布局（hx90）：

| 输出 | 物理分辨率 | 缩放 | 逻辑位置 |
|---|---|---|---|
| HDMI-A-1 | 1280×1024 | 1 | `(0, 0)` |
| HDMI-A-2 | 3840×2160 | 2 | `(1280, 0)` |

图标主题是 Pop，`folder`、`text-x-generic` 等主题图标在 `48x48` 目录里仍是 SVG。

---

## 1. 只能看见文件名，看不见图标

### 现象

桌面上的名字还在，图标经常空白。有时重启后短暂出现，过一会儿又没了。
4K 那块屏（HDMI-A-2，缩放 2）更容易复现。

### 原因

1. **Pop 主题图标是 SVG，却走了异步加载。**  
   `Image { asynchronous: true; cache: true }` 把解码丢到工作线程。
   Qt 的 SVG 渲染器不是线程安全的，解出来经常是空图，`status` 变成
   `Image.Error` 或 `Ready` 但像素为空。文字是 `Text`，所以文件名还在。

2. **失败结果会进 `Image.cache`。**  
   某一次异步解失败后，同一条 `source` 之后一直用那张空缓存。表现就是
   “经常看不见，而且一直看不见”，直到重启 Quickshell。

3. **`sourceSize` 曾经绑在输出的 `Screen.devicePixelRatio` 上。**  
   缩放屏上这个值在 delegate 创建时可能是 0 / 不可用，`sourceSize` 变成
   无效尺寸，图标永久空白。后来改成写死 `iconSize * 2`，4K 上仍会空白，
   因为真正的主因是异步 SVG，不是倍率公式。

4. **Repeater 被整表替换。**  
   `visibleItems` 以前是绑定：`host.itemsForScreen(...)`。布局一变
   （拖一下、存一次坐标）就会得到一个新的 JS 数组。QML Repeater 把这当成
   全新 model，拆掉再重建所有 delegate。图标重新异步加载，空白窗口又出现一次。

5. **自己写的坐标文件把自己刷新了。**  
   `savePositions()` 写 `desktop-icon-positions.json`，`FileView.watchChanges`
   立刻 `reload()` → `applyPositions()` → `layoutState` 换对象 → 又一次
   Repeater 重建。

### 修法（不要改回去）

- 图标 `Image` 用 `asynchronous: false`、`cache: false`。
- SVG 不要设 `sourceSize`（`iconIsRaster(url)` 为假时宽高都是 0）。
  栅格预览才用 `iconPixels`（`iconSize * max(devicePixelRatio)`）。
  **不要**再绑 `Screen.devicePixelRatio` 到单个 delegate 上。
- 主图加载失败时，底下叠一张同步加载的 `fallbackIcon`。
- 每个输出自己维护 `visibleItems` 数组。`refreshVisibleItems()` 只有在
  id / 名字 / 图标 / 预览 / 信任状态变化时才赋值。只改格子坐标时 Repeater
  保持原 delegate，靠 `Binding on x/y` 移动。
- `savePositions()` 用 `positionWrites` 计数。自己写入触发的
  `onFileChanged` 直接丢掉，不 `reload()`。

### 再坏时怎么查

1. 看 `iconSource()` 实际给出的路径：主题名会经 `Quickshell.iconPath` 变成
   `.svg` 文件。Pop 的 `~/.nix-profile/share/icons/Pop/48x48/places/folder.svg`
   就是例子。
2. 确认 `Service.qml` 里图标 `Image` 仍是 `asynchronous: false`、`cache: false`。
3. 拖一个图标后，图标不应闪一下空白。若闪了，检查 `visibleItems` 是否又变成
   绑定表达式、以及 `positionWrites` 是否还在挡自己的文件监视。

---

## 2. 蓝色框选只能从上往下拉

### 现象

空桌面上按住左键可以拉出一个半透明蓝框。从上往下能拉出来；从下面往上、
从右边往左、从屏幕空白处起手，框出不来。

### 原因

图层的 `mask` 决定 Wayland 输入区域。当时 mask 只包含 `inputLayer`，
而 `inputLayer` 的宽高是「最右 / 最下那颗图标」的包围盒。

图标按列从左上往下排，所以可点区域大约是左上那一竖条（当时三颗图标大约
120×362）。只有在这个矩形里按下，Quickshell 才能收到事件。按下之后
Wayland 会抓住指针，框可以拖出这个矩形——所以「从上往下能拉出来」。
在包围盒外面按下，事件直接给了 Labwc，框永远起不了手。

这是故意做成 click-through 的副作用：空白壁纸要留给 Labwc 的根菜单。
结果框选和「把文件拖到壁纸上」都只在图标附近可用。

### 修法（不要改回去）

- mask 改为覆盖整块输出：`Region { item: emptyMouse }`，`emptyMouse`
  是铺满窗口的 `MouseArea`。框选可以从任意边缘起手。
- 整块输出收走点击之后，Labwc 收不到空白处的右键。Labwc 的根菜单绑定是
  `A-space`（`modules/labwc/labwc/rc.xml`），并且 `ShowMenu` 默认
  `atCursor=true`。空白处右键因此转发给：

  ```
  wtype -M alt -k space -m alt
  ```

  见 `showRootMenu()`。插件自己的图标右键菜单不受影响（图标 `MouseArea`
  在上层）。若已经打开了插件菜单或信任对话框，右键只关闭这些界面，
  不再弹出 Labwc 菜单。
- 不要再把 mask 缩回图标包围盒。那会立刻让框选、文件拖放、五连击换壁纸
  全部退化成「只能在图标旁边用」。

### 再坏时怎么查

1. 从屏幕右下空白处按住左键往左上拉，蓝框应跟着出现。
2. 空白处右键应弹出 Labwc 根菜单（终端、运行应用等），不是无反应。
3. 若右键没菜单：先确认 `wtype` 仍在 PATH 里，再确认
   `A-space` 仍绑定 `ShowMenu root-menu`。换了快捷键就要改 `showRootMenu()`。
4. 若左键框选又只能从上往下：查 `mask` 是否又指回 `inputLayer`。

---

## 3. 按住图标跨显示器时图标消失，松开才出现

### 现象

在一块屏上按住图标拖到另一块屏，拖的过程中图标没了。松开鼠标后，
图标出现在目标屏的格子上。跨屏本身是成功的，预览不连续。

### 原因

每个输出一个 `PanelWindow`（`WlrLayer.Bottom`）。被拖的 `Item` 是源窗口的
子节点。Wayland 图层表面画不出自己输出以外的内容，图标一出屏幕边缘就被裁掉。

源窗口的 `MouseArea` 在按下后仍能收到指针事件（隐式 grab），
`lastSceneX/Y = screen.x + icon.x + mouse.x` 在另一块屏上仍然更新，
所以松开时 `screenAtPoint` 能找到目标输出并 `moveToScreen`。视觉层没有对应物。

`drag.minimum/maximum = ±2 * panel` 只是允许坐标越过边界，不能让源表面
把像素画到隔壁输出上。

### 修法（不要改回去）

根对象上有一份拖拽会话：

- `dragId` / `dragEntry` / `dragOriginScreen` / `dragHoverScreen`
- `dragSceneX` / `dragSceneY` / `dragGrabX` / `dragGrabY`

左键按下 `beginDrag()`，移动 `updateDragPointer()`（只在
`screenAtPoint` 命中输出时才改 `dragHoverScreen`，两屏夹缝里保持上一块屏，
避免闪没），松开或取消 `clearDrag()`。

指针还在源屏时，源图标自己跟着 `drag.target` 走。指针到了另一块屏时：

- 源图标 `opacity: 0`（避免卡在源屏边缘的半截残影）
- 目标屏上的 `dragGhost` 用同一份 `dragEntry`，画在
  `(dragSceneX - screen.x - grabX, dragSceneY - screen.y - grabY)`

Ghost 是纯视觉，`enabled: false`，不抢鼠标。真正的 grab 始终在源图标的
`MouseArea` 上。

松手时必须**先** `clearDrag()`，再 `moveItemToScreen()`。跨屏会把这颗图标
从源屏的 `visibleItems` 里拿掉，Repeater 立刻销毁正在跑 `onReleased` 的
delegate。若 `clearDrag()` 写在 `moveItemToScreen()` 后面，这段代码根本
执行不到：目标屏上已经有落格后的真图标，拖拽残影 `dragGhost` 还在，看起来
就是同一颗图标出现了两份。点一下别的图标或再拖一次才会走到另一条
`clearDrag()`，残影才消失。这不是图片缓存。

### 再坏时怎么查

1. 从 HDMI-A-1 按住一颗图标拖到 HDMI-A-2，拖的过程中目标屏上应一直有图标，
   不能只在松手后跳出来。
2. 若过程中又消失：查 `dragGhost.visible` 条件是否仍要求
   `dragHoverScreen === panel.screenName && dragOriginScreen !== panel.screenName`，
   以及 `updateDragPointer` 是否还在 `onPositionChanged` 里调用。
3. 坐标公式必须和 `moveItemToScreen` 用同一套：
   `scene = screen.x + icon.x + mouse.x`。Quickshell 的 `Screen.x/width`
   是逻辑像素；这块机器上 HDMI-A-2 逻辑宽约 1920（3840÷2）。不要混用物理像素。

---

## 4. 顺手修掉的、用起来会别扭的问题

这些当时没单独报，但会让桌面「很难用」。以后改键盘或拖拽时对照。

### 方向键不按格子走

`visualOrder()` 以前用 `pa.y` / `pa.x` 排序，持久化里却是 `{col, row}`。
`y` 永远是 `undefined`，排序等于没排。上下左右都只是在这个乱序数组上 ±1。

现在：

- `visualOrder` 只看当前屏的 `visibleIds`，按 `col` 再 `row` 排（列优先，
  和格子填充方向一致）。`Tab` / `Shift+Tab` 走这条顺序。
- 方向键走 `moveSelectionDirection(dx, dy)`：在同一方向上找最近的那颗，
  没有目标就不动。

### 拖拽要先拉很长才动

`drag.threshold` 以前是 36px，格子宽 96、图标 48。按住以后图标不跟手，
过了阈值才跳一下。已改成 8，和「算不算一次拖拽」的 8px 判定一致。

### 键盘选中的可能是另一块屏上的图标

`visualOrder` 以前遍历 `root.items`（全部桌面项），箭头可能选中当前屏
看不见的图标。现在只在 `itemsForScreen(screenName)` 里走。

---

## 5. 不要踩的坑

| 做法 | 后果 |
|---|---|
| 图标 `Image` 再开 `asynchronous: true` 或 `cache: true` | SVG 再次空白，且可能被缓存锁死 |
| `sourceSize` 绑 `Screen.devicePixelRatio` | 缩放屏上尺寸变 0，图标永久空白 |
| mask 缩回 `inputLayer` 包围盒 | 框选、文件拖放、五连击换壁纸只能在图标旁边用 |
| 空白右键改回插件自己的 empty 菜单，又不做转发 | 丢掉 Labwc 根菜单 |
| 跨屏只靠把源图标的 `x/y` 拖出窗口 | 源表面裁切，目标屏上看不见预览 |
| `visibleItems` 再绑成每次 new 数组 | 拖一下、存一次坐标就整表重建，图标闪没 |
| `savePositions` 后再 `reload()` 坐标文件 | 自己触发的监视把 layout 换掉，Repeater 重建 |
| 改 Labwc 来修这些 | 这些都能在 QML 里做；AGENTS.md 要求先改 QML |

安全模型保持不变：远程 URL、`data:`、`image:`、桌面上的 SVG/GIF **文件**
仍被 `desktop-index` 拒绝。主题图标走 `Quickshell.iconPath`，那是本地主题
文件，和「加载用户丢到桌面上的 SVG」不是一回事。不要为了修空白图标去放开
`sanitize_icon` 对用户 SVG 的限制。

---

## 6. 回归检查

改完 `Service.qml` 或 `DesktopLayout.js` 之后：

1. `node tests/test_layout_model.js`
2. `python3 tests/test_desktop_index.py QmlSecurityTests`  
   （完整 `test_desktop_index.py` 需要带 PyGObject 的
   `ANCHOR_SHELL_PYTHON`，系统 `python3` 没有 `gi`。）
3. `quickshell-mode dev`，确认 `quickshell list --all` 只有一个实例。
4. 两块屏上的图标图和文件名都在，过一两分钟仍在（不要只看刚启动那一下）。
5. 从屏幕下方、右侧空白处拉蓝框，能框到图标。
6. 空白处右键弹出 Labwc 根菜单；图标右键仍是插件菜单（打开 / 重命名 / 删除）。
7. 按住一颗图标从 HDMI-A-1 拖到 HDMI-A-2：拖的过程中目标屏上有跟手的图标，
   松开后落在格子上，同一块屏上只能有一份，不能留下一真一残影。再拖回来也一样。
8. 方向键只在当前屏的图标之间移动。

视觉有争议时截图，不要只看 `desktop-icon-positions.json` 判断界面是好的。
