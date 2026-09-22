# Active Window 维护规则

## 应用图标必须复用 Omarchy 的共享图标库

顶栏显示当前应用图标时，必须参考并复用
`iamcheyan.launcher` 使用的 Omarchy `AppLibrary`：

```qml
var appLibrary = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
var source = appLibrary ? appLibrary.iconSource(iconName) : ""
```

不要只把 Wayland `appId` 直接传给 `Quickshell.iconPath()`。`appId`、desktop
entry ID、startup class 和图标名可能不同，而且 Qt 的主题缓存可能找不到已经
安装的图标；`AppLibrary.iconIndex` 才是 Omarchy 启动器实际使用的可靠路径。

图标解析顺序应当是：

1. 通过 `DesktopEntries` 将窗口 `appId` 映射到 desktop entry 的 `icon` 字段；
2. 使用共享 `AppLibrary.iconSource(iconName)` 解析真实文件路径；
3. 必要时再使用 `Quickshell.iconPath()` 作为补充回退。

## 不要用首字母代替正常应用图标

首字母只能作为真实图标确实不存在或加载失败时的最后 fallback。不能因为
`Quickshell.iconPath()` 返回空，就把 `A`、`F` 等字母当作正常结果；启动器中
已有的真实图标必须在顶栏复用。

图像显示应根据 `Image.status === Image.Ready` 判断是否成功加载，不能只根据
`source` 非空判断，否则会出现顶栏空白或错误地隐藏 fallback。

## 验证

修改图标逻辑后必须：

```bash
omarchy plugin validate .
git diff --check
omarchy restart shell
```

然后至少验证 Alacritty 和 Firefox 等应用切换时，顶栏显示的是启动器中的真实
图标，而不是首字母占位符。提交前确认：

```bash
git status --short
```

工作树只应包含本次有意提交的改动，推送后应保持干净。
