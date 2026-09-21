# Labwc 多屏快捷键定位

快捷键通过 `iamcheyan.clipboard toggleAtCursor` 调用面板。在 Labwc 下，
菜单保持屏幕右上方的固定位置，只选择鼠标当前所在的显示器。

同名 `IpcHandler` 只由一个实例接收，不能让每台显示器的 widget 各自决定
开关状态。菜单使用 Exclusive 键盘焦点时，`ToplevelManager.activeToplevel`
也不能可靠地代表鼠标刚移入的显示器。因此快捷键触发时，面板会短暂显示
每屏一个透明的 layer probe；鼠标进入哪个 probe，就选中哪个输出，然后立即
撤掉 probe。这样不需要读取全局鼠标坐标，也不需要修改 Labwc 或增加系统包。

- 未打开：在选中的显示器打开。
- 已在另一显示器打开：先在选中的显示器显示同一个面板，再关闭旧位置。
- 已在同一显示器打开：关闭。
- 无指针事件：500ms 后回退到活动窗口的 `screens` 或顶栏所在屏幕。

实现位置：

- `ClipboardPanel.qml` 的 `screenProbe`：每屏透明 layer 和 `MouseArea`；
- `toggleAtScreen()` / `acceptScreen()`：选择输出并控制面板生命周期；
- `bar/widget.qml`：把快捷键 IPC 转给当前面板，而不是让每个 widget 独立切换。

诊断实际面板状态：

```sh
quickshell -p /home/tetsuya/nixos-config/modules/quickshell ipc call iamcheyan.clipboard placement
quickshell list --all
```

2026-09-22 在 HDMI-A-1（1x）与 HDMI-A-2（2x）实测：一号屏打开后，移动到
二号屏并按一次 Ctrl+Alt+V，面板直接显示在二号屏；反向切换同样工作，
同屏再次触发会关闭。通过 `placement` IPC 返回的输出名称和截图确认，
不是只检查 QML 属性。测试使用临时 `nix run nixpkgs#wlrctl` 移动指针，
再用 `wtype` 发送实际快捷键；运行功能本身不依赖这些测试工具。

重载后应确认实例 ID/启动时间确实改变。若 `quickshell-mode dev` 仅报告重启
但实例没变，使用 `quickshell kill --id <实际实例ID>`，待旧实例退出后确认
是否由监督进程重启；没有监督进程时再启动指定源码路径，避免叠加实例。
