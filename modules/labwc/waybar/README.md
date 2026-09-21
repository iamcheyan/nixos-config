# Waybar 配置说明

Waybar 是 Sway 窗口管理器使用的顶部状态栏。

## 文件结构

- `sway/config.jsonc` - Sway 使用的配置
- `sway-wsl/config.jsonc` - WSL 下测试 Sway 时使用的轻量配置
- `style.css` - Waybar 样式文件（颜色、字体、间距等）
- `scripts/` - 公共脚本（音量、蓝牙等）

## 常用操作

### 重启 Waybar
修改配置或样式后，运行以下命令重新加载：
```bash
pkill waybar && waybar &
```

### 编辑配置
```bash
# 编辑 Sway 的 Waybar 配置
vim ~/.config/waybar/sway/config.jsonc

# 编辑样式
vim ~/.config/waybar/style.css
```

### 查看日志
如果 Waybar 出现问题，可以在终端直接运行查看错误信息：
```bash
waybar
```

### 左侧模块
- **custom/launcher** - 应用启动器（点击打开 launcher 脚本）
- **wlr/taskbar** - 窗口任务栏（显示当前打开的窗口）

### 中间模块
- **clock** - 时钟显示（格式：年-月-日 时:分）

### 右侧模块
- **tray** - 系统托盘
- **custom/cliphist** - 剪贴板历史（左键粘贴，右键打开历史）
- **custom/screenshot** - 截图（左键区域截图，右键打开菜单）
- **custom/kazamo** - Kazamo 语音输入法切换
- **pulseaudio** - 音量控制
- **bluetooth** - 蓝牙状态
- **cpu** - CPU 使用率
- **memory** - 内存使用率
- **custom/power** - 电源菜单（左键系统菜单，右键重启菜单）

## 样式自定义

当前样式特点：
- 背景色：黑色 (`#000000`)
- 文字颜色：白色
- 模块间距：适中
- 透明度：模块背景透明

### 修改背景色
编辑 `style.css` 中的 `window#waybar` 部分：
```css
window#waybar {
    background-color: #000000;  /* 修改这里 */
    color: #ffffff;
}
```

### 修改模块样式
每个模块都有对应的 CSS 选择器，例如：
- `#clock` - 时钟
- `#battery` - 电池
- `#network` - 网络
- `#pulseaudio` - 音量

## 故障排除

### Waybar 没有显示
1. 检查 Waybar 是否在运行：`pgrep waybar`
2. 手动启动查看错误：`waybar`
3. 检查配置文件语法：确保 JSON 格式正确

### 样式没有生效
1. 确保 CSS 语法正确
2. 重启 Waybar：`pkill waybar && waybar &`
3. 检查是否有缓存问题

## 参考资源

- [Waybar Wiki](https://github.com/Alexays/Waybar/wiki)
- [配置示例](https://github.com/Alexays/Waybar/wiki/Examples)
