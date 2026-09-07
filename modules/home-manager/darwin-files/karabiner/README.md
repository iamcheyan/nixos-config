# Karabiner-Elements 键盘映射与配置指南

本目录包含了基于 [Karabiner-Elements](https://karabiner-elements.pqrs.org/) 的 macOS 键盘深度定制配置。通过底层内核级虚拟 HID 驱动，实现了日文键盘按键重映射、跨平台快捷键习惯统一（Control $\rightarrow$ Command 映射）以及输入法状态无缝切换。

---

## 1. 目录结构与路径映射

`karabiner.json` 现在由 `~/nixos-config` 的 Darwin Home Manager 配置进行版本控制与部署：

```text
~/.config/karabiner/ (源文件位于 ~/nixos-config/modules/home-manager/darwin-files/karabiner/)
├── karabiner.json          # 核心配置文件（当前生效的所有 Profile、按键映射、设备参数）
├── README.md               # 本文档：架构说明、规则详解、修改范例与排障手册
└── assets/                 # 规则库资产目录
    └── complex_modifications/ # 自定义复杂规则 JSON 导入目录
```

| 路径类型 | 对应路径 | 说明 |
|---|---|---|
| **nixos-config 源目录** | `~/nixos-config/modules/home-manager/darwin-files/karabiner/` | Git 仓库管理路径，所有手动编辑**必须在此进行** |
| **本机目标目录** | `~/.config/karabiner/` | Karabiner-Elements 守护进程实际读取的配置文件路径 |
| **自动备份目录** | `~/.config/karabiner/automatic_backups/` | Karabiner 在每次 GUI 改动时自动生成的历史快照（无需入库） |

---

## 2. 当前生效的配置详解

配置文件采用 `Default profile` 作为主配置方案，包含以下核心设定：

### (1) 日文英数/假名键映射（JIS Eisuu / Kana $\rightarrow$ F13 / F14）

* **规则描述**：`Map Japanese Eisuu/Kana to F13/F14`
* **映射关系**：
  * `japanese_eisuu`（空格键左侧的英数键） $\longrightarrow$ `F13`
  * `japanese_kana`（空格键右侧的假名键） $\longrightarrow$ `F14`
* **设计目的与联动原理**：
  * macOS 原生英数/假名键直接切换系统输入源时存在约 50~100ms 的切换延迟，且难以被外部输入法框架精准捕获。
  * 映射为无物理冲突的功能键 `F13` / `F14` 后，可与 **Fcitx5 / Rime / 系统快捷键** 绑定，实现「单击左键必切英文、单击右键必切中文」的绝对状态切换，彻底消除中英文切换的二义性。

---

### (2) Control 快捷键映射为 Command 快捷键（Windows/Linux 习惯统一）

* **规则描述**：`Map Control shortcuts to Command shortcuts`
* **映射关系**：

| 输入按键 (From) | 触发修饰键 (Mandatory) | 可选修饰键 (Optional) | 转换目标 (To) | 实际功能 |
|---|---|---|---|---|
| `T` | `Control + Shift` | `Caps Lock` | `Command + Shift + T` | 重新打开关闭的标签页 |
| `T` | `Control` | `Caps Lock` | `Command + T` | 新建标签页 |
| `W` | `Control + Shift` | `Caps Lock` | `Command + Shift + W` | 关闭当前窗口 |
| `W` | `Control` | `Caps Lock` | `Command + W` | 关闭当前标签页 |
| `R` | `Control + Shift` | `Caps Lock` | `Command + Shift + R` | 强制刷新页面 (Hard Reload) |
| `R` | `Control` | `Caps Lock` | `Command + R` | 刷新当前页面 (Reload) |
| `N` | `Control + Shift` | `Caps Lock` | `Command + Shift + N` | 新建无痕/隐身窗口 |
| `N` | `Control` | `Caps Lock` | `Command + N` | 新建窗口 |
| `Z` | `Control + Shift` | `Caps Lock` | `Command + Shift + Z` | 重做 (Redo) |
| `Z` | `Control` | `Caps Lock` | `Command + Z` | 撤销 (Undo) |
| `Y` | `Control` | `Caps Lock` | `Command + Y` | 重做 / 历史记录 |
| `L` | `Control` | `Caps Lock` | `Command + L` | 聚焦地址栏 (Focus URL Bar) |
| `F` | `Control` | `Caps Lock` | `Command + F` | 页面内查找 (Find in Page) |
| `S` | `Control` | `Caps Lock` | `Command + S` | 保存网页/文件 (Save) |
| `A` | `Control` | `Caps Lock` | `Command + A` | 全选 (Select All) |
| `C` | `Control` | `Caps Lock` | `Command + C` | 复制 (Copy) |
| `V` | `Control` | `Caps Lock` | `Command + V` | 粘贴 (Paste) |
| `X` | `Control` | `Caps Lock` | `Command + X` | 剪切 (Cut) |
* **设计目的**：
  * 保留跨平台（Windows / Linux / macOS）高度一致的 `Ctrl+C`、`Ctrl+V` 编辑肌肉记忆。
* 包含 `optional: ["caps_lock"]`，确保大写锁定开启时快捷键依然有效。

### (3) 左 Control 单击或长按触发 F13

`Left Control: F13 when pressed alone` 是一个全局规则，不区分内置键盘
和外接键盘：

* 单独短按并释放左 Control：当前暂时不发送任何按键（单击 F13 已停用）；
* 左 Control 持续按住超过 250ms：立即发送 `F13`，并记录长按状态；
* 左 Control 与其他键一起按：继续发送普通的 `left_control`；
* 现有的 Control 快捷键规则仍会继续处理 `Ctrl + C`、`Ctrl + V` 等组合。

这里暂时移除了 `to_if_alone`，只保留 `to_if_held_down`，并以
`left_control_long_press` 变量记录长按状态，在按键释放时清零。
长按阈值和单独按键判定阈值都是 250ms。组合键仍然保留原始 Control，
但如果先长按超过阈值再按其他键，F13 已经被触发，这是长按触发和组合键
同时存在时无法完全避免的时间边界。

---

### (4) 虚拟键盘与基础设备参数

* **虚拟键盘布局** (`virtual_hid_keyboard`)：
  * `keyboard_type_v2`: `"jis"`（声明为标准日文 JIS 键盘配列，避免 macOS 识别为 ANSI 导致按键错位）。
  * `country_code`: `0`。
* **功能键直通** (`fn_function_keys`)：
  * `F6` $\longrightarrow$ `F6`（保持原生功能键直通）。

### (5) MINILA-R Convertible 专用布局

MINILA-R 的 USB 设备信息为：

```text
Product:    MINILA-R Convertible
vendor_id:  3141 (十六进制 0c45)
product_id: 8888 (十六进制 22b8)
```

Karabiner 规则通过 `vendor_id` 和 `product_id` 限定设备，因此只影响
MINILA-R，不会改变 MacBook 内置键盘或其他外接键盘。

当前 MINILA-R 规则位于 `karabiner.json` 的
`MINILA-R Convertible layout (USB 0c45:22b8)` 中：

| MINILA-R 按键 | macOS 事件 | 当前输出 |
|---|---|---|
| 左 Option | `left_option` | 左 Command |
| 左 Command | `left_command` | 左 Option |
| 無変換 | `japanese_pc_nfer` | F13 |
| 片假名/平假名 | `japanese_pc_katakana` | 左方向键 |
| 下方 Delete | `delete_forward` | 右方向键 |
| 右 Control | `right_control` | 上方向键 |
| 右 Option | `right_option` | 下方向键 |
| 全角/半角 | `grave_accent_and_tilde` | Escape |
| Escape | `escape` | 全角/半角 |

#### 空格两侧的两个 Fn 键

MINILA-R 空格左右的两个键是键盘硬件层的左右 `Fn` 键，不是普通的
HID 键。它们由键盘固件直接参与组合键处理，单独按下时不会向 macOS
发送独立的按键事件，因此：

* Karabiner-EventViewer 中不会出现这两个键的 `key_code`；
* Karabiner 和 keyd 都不能直接把它们单独重映射成普通按键；
* 只有 `Fn + 其他键` 产生的最终组合键，才可能被 Karabiner 捕获；
* 这两个 Fn 键不能通过当前的 Karabiner JSON 配置改成独立的
  Command、Option、Control 或方向键。

这不是 chezmoi 或 Karabiner 配置丢失，而是 MINILA-R 固件的工作方式。
如果需要利用 Fn 层，应在 EventViewer 中测试实际组合，例如：

```text
左 Fn + J
右 Fn + J
左 Fn + Delete
右 Fn + Delete
```

记录组合键实际产生的 `key_code` 后，再为该组合键添加 Karabiner 规则。
如果组合键也完全没有事件，则它由键盘固件直接转换成另一个普通键，
只能对转换后的结果进行映射。

#### 设备规则的验证方式

打开 Karabiner EventViewer：

```bash
open -a Karabiner-EventViewer
```

按键时重点记录 `name.key_code`。常见的 MINILA-R 按键可能显示为：

```text
japanese_pc_nfer
japanese_pc_katakana
delete_forward
grave_accent_and_tilde
right_control
right_option
```

不要根据键帽文字猜测 `key_code`；不同键盘固件、蓝牙/USB 连接方式
以及日文/英文配列可能报告不同名称。新增规则前应先在 EventViewer
确认，并继续保留 MINILA-R 的设备条件。

---

## 3. 日常修改与维护工作流

Karabiner-Elements 支持 GUI 操作和 JSON 直接编辑两种维护方式：

### 方式一：通过 Karabiner-Elements GUI 图形界面修改（推荐初学者）

1. 打开 macOS 应用程序中的 **Karabiner-Elements**。
2. 在 **Complex Modifications**、**Simple Modifications** 或 **Function Keys** 页面中调整设置。
3. 调整完成后，Karabiner 会立即写入 `~/.config/karabiner/karabiner.json`。
4. **将改动复制回 nixos-config 源文件**：
   ```bash
   cp ~/.config/karabiner/karabiner.json ~/nixos-config/modules/home-manager/darwin-files/karabiner/karabiner.json
   cd ~/nixos-config
   git commit -m "feat(karabiner): update key mappings"
   git push
   ```

---

### 方式二：直接在 nixos-config 源目录编辑 JSON（高级用户）

1. 编辑源文件：
   ```bash
   vim ~/nixos-config/modules/home-manager/darwin-files/karabiner/karabiner.json
   ```
2. 验证 JSON 语法正确后，应用到系统：
   ```bash
   sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/nixos-config#macbook-m1-max
   ```
3. **即时热重载**：Karabiner 守护进程通过文件系统事件（fsevents）监听 `~/.config/karabiner/karabiner.json`。Home Manager 完成链接更新后，通常无需重启软件；如未生效，可在 Karabiner 中手动 reload。

---

## 4. 常用高级规则扩展范例

若需要扩充功能，可将以下代码块加入 `karabiner.json` 的 `rules` 数组中：

### 范例 A：排除特定应用程序（如终端 / Kitty 内不拦截 Ctrl+C）

默认情况下全局映射 `Ctrl+C` $\rightarrow$ `Cmd+C` 会导致终端内无法发送 `SIGINT` 中断信号。可以通过添加 `conditions` 限定仅在非终端应用生效：

```json
{
    "description": "Map Control shortcuts to Command (Exclude Terminal / Kitty)",
    "manipulators": [
        {
            "conditions": [
                {
                    "bundle_identifiers": [
                        "^net\\.kovidgoyal\\.kitty$",
                        "^com\\.apple\\.Terminal$",
                        "^com\\.googlecode\\.iterm2$"
                    ],
                    "type": "frontmost_application_unless"
                }
            ],
            "from": {
                "key_code": "c",
                "modifiers": { "mandatory": ["control"] }
            },
            "to": [{ "key_code": "c", "modifiers": ["left_command"] }],
            "type": "basic"
        }
    ]
}
```

---

### 范例 B：Caps Lock 单击为 Esc，长按为 Control（双模神键）

```json
{
    "description": "Change caps_lock to Control when held, Escape when pressed alone",
    "manipulators": [
        {
            "from": {
                "key_code": "caps_lock",
                "modifiers": { "optional": ["any"] }
            },
            "to": [{ "key_code": "left_control" }],
            "to_if_alone": [{ "key_code": "escape" }],
            "type": "basic"
        }
    ]
}
```

---

### 范例 C：增加保存 (`Ctrl+S` $\rightarrow$ `Cmd+S`) 与撤销 (`Ctrl+Z` $\rightarrow$ `Cmd+Z`)

```json
{
    "description": "Map Ctrl+S and Ctrl+Z to Cmd+S and Cmd+Z",
    "manipulators": [
        {
            "from": { "key_code": "s", "modifiers": { "mandatory": ["control"] } },
            "to": [{ "key_code": "s", "modifiers": ["left_command"] }],
            "type": "basic"
        },
        {
            "from": { "key_code": "z", "modifiers": { "mandatory": ["control"] } },
            "to": [{ "key_code": "z", "modifiers": ["left_command"] }],
            "type": "basic"
        }
    ]
}
```

---

## 5. 排障与常见问题（Troubleshooting）

### 1. 修改后按键未生效
* **检查 JSON 格式**：`jq . ~/.config/karabiner/karabiner.json` 确认无语法错误。
* **检查 Karabiner 状态**：在顶部菜单栏确认 Karabiner-Elements 正在运行。
* **查看控制台日志**：在 Karabiner GUI $\rightarrow$ **Log** 标签页查看是否有规则解析告警。

### 2. 系统升级或换机后提示权限丢失
Karabiner 依赖 macOS 底层权限。若按键完全失灵，请检查：
* **系统设置** $\rightarrow$ **隐私与安全性** $\rightarrow$ **辅助功能 (Accessibility)**：确保 `karabiner_grabber` 与 `karabiner_console_user_server` 处于勾选状态。
* **输入监控 (Input Monitoring)**：确保 `karabiner_grabber` 已授权。

### 3. 新机器一键恢复配置
在已经安装 Karabiner-Elements 的新 Mac 上：
```bash
# 1. 克隆 nixos-config 并安装 Nix
# 具体安装流程见 ~/nixos-config/docs/macos-nix-darwin/

# 2. 授权 macOS 辅助功能与输入监控权限后即刻恢复完整按键体验
```

---

*本文件由 nixos-config 的 Darwin Home Manager 配置管理，源文件路径：`~/nixos-config/modules/home-manager/darwin-files/karabiner/README.md`。*
