# Anchor Shell / Nixarchy 脱钩迁移报告

更新时间：2026-09-22

当前策略：**只迁移，不删除 Nixarchy。** Nixarchy、原有 Hyprland/Omarchy
接线和旧目录在完整迁移验收前全部保留。

## 1. 迁移目标

本迁移的最终目标是：保留我们熟悉的顶栏、插件、锁屏、剪贴板、语音输入和
桌面辅助功能，同时逐步淘汰 Nixarchy/Omarchy 对这些功能的外部运行时依赖。

迁移后的桌面功能层命名为 **Anchor Shell**。它不绑定某一个合成器，目标是
可以由 Labwc、Sway、KDE Wayland 或其他兼容 Wayland 的会话启动。

迁移遵循两个边界：

1. Anchor Shell 的源代码和兼容脚本由本仓库管理；
2. Hyprland/Omarchy 旧会话在迁移完成前保持原样，不能因为 Labwc 的改动而被
   意外改变。

## 2. 这不是简单复制文件

迁移包含四个层次：

```text
源码归属       modules/quickshell → modules/anchor-shell
启动接线       Labwc → Anchor Shell，而不是 Nixarchy 的 share/omarchy
服务接线       omarchy-fcitx5.service → anchor-fcitx5.service
软件声明       programs.nixarchy.apps → 普通 NixOS systemPackages
```

因此，文件复制只是第一步。真正的迁移还需要修改 Nix 求值关系、启动脚本、
systemd user service 和软件声明位置。

## 3. 已完成的迁移

### 3.1 Anchor Shell 源码

当前由本仓库管理的源码位于：

```text
modules/anchor-shell/
├── plugins/       first-party 插件
├── third-party/   已迁入并实际使用的第三方插件
├── compat/        保留旧命名和脚本接口的本地兼容层
├── docs/          迁移和运行文档
└── shell.qml      Quickshell 入口
```

旧的 `modules/quickshell/` 暂时保留为回退副本，没有删除，也没有让 Hyprland
会话改用新路径。

### 3.2 Labwc 的 Quickshell 启动路径

Labwc 现在从以下两个来源选择运行内容：

```text
发布模式：/nix/store/...-anchor-shell
开发模式：/home/tetsuya/nixos-config/modules/anchor-shell
兼容资源：本仓库的 anchor-shell/compat/omarchy/
```

Labwc 不再引用：

```nix
config.programs.nixarchy.package
```

也不再把 Nixarchy 提供的 `/share/omarchy` 作为 Labwc 的 legacy fallback。

### 3.3 Fcitx5 输入法服务

Labwc 使用本仓库接线的静态 user service：

```text
anchor-fcitx5.service
```

它不会通过 `graphical-session.target` 自动启动，而是由 Labwc autostart 在当前
Wayland 会话导入 `WAYLAND_DISPLAY` 后显式启动。这样可以避免 Hyprland 会话
同时启动它并与旧的 `omarchy-fcitx5.service` 争抢 D-Bus 名称。

当前关系：

```text
Labwc       → anchor-fcitx5.service
Hyprland    → omarchy-fcitx5.service（暂时保留）
```

### 3.4 Telegram Desktop

Telegram 已从 Nixarchy 的应用选择列表迁移到普通 NixOS 包声明：

```nix
environment.systemPackages = with pkgs; [
  telegram-desktop
];
```

因此，即使以后删除 Nixarchy 的应用模块，Telegram 也不会随之消失。

### 3.5 用户配置和状态命名空间

Anchor Shell 现在使用自己的用户目录：

```text
~/.config/anchor-shell/
~/.local/state/anchor-shell/
```

Labwc 首次启动时会把不存在的布局、主题、锁屏设置、通知、天气、剪贴板和
顶栏状态从旧目录复制过去。旧目录不会被删除，Hyprland 仍可继续使用它的
原有数据。Quickshell 的 `mode`、`runtime`、用户插件目录和配置文件也已经
改为 Anchor Shell 命名空间；旧路径只作为读取和一次性迁移来源保留。

## 4. 当前运行时依赖关系

Labwc 当前的实际关系如下：

```text
Labwc
  └── labwc autostart
      ├── Anchor Shell
      │   ├── modules/anchor-shell
      │   └── compat/omarchy（本仓库副本）
      ├── anchor-fcitx5.service
      ├── Voxtype user service
      └── Wayland 工具（wtype、wl-clipboard 等）
```

其中 `NIXARCHY_ROOT`、`OMARCHY_PATH`、`omarchy-*` 和 `omarchy.*` 仍然会出现，
但在 Labwc 会话中它们指向本仓库的兼容层。这些是保留的接口名称，不代表
Labwc 仍然加载 Nixarchy 的运行时包。

## 5. 当前仍保留的 Nixarchy 依赖

Nixarchy 目前仍在系统配置中，因为 Hyprland/Omarchy 会话尚未迁移完成。主要
位置包括：

| 位置 | 当前作用 | 是否已影响 Labwc |
|---|---|---|
| `flake.nix` | 提供 Nixarchy flake input | Labwc 不再直接需要 |
| `modules/desktop.nix` | Nixarchy 模块、Omarchy 包、Hyprland 桌面接线 | 属于系统共享层，暂时保留 |
| `modules/home-manager/nixos-user.nix` | Nixarchy Home Manager 模块和 Omarchy 用户服务 | 主要服务 Hyprland |
| `hosts/hx90/configuration.nix` | Nixarchy 菜单扩展 | 旧桌面接线 |
| `hosts/hx90/nixarchy/services.nix` | 仍启用的 Nixarchy 服务目录 | 与 Labwc 无直接关系 |
| `modules/labwc.nix` | Labwc 自己的配置 | 已移除 Nixarchy package 依赖 |

因此目前的准确表述是：**Labwc 的运行时已经脱离 Nixarchy，但整个系统还没有
删除 Nixarchy，因为 Hyprland 仍使用它。**

## 6. 后续迁移批次

### 批次二：普通系统和用户服务

- 把仍有用的 `omarchy-*` systemd user service 逐项改成 Anchor 命名；
- 确认 Fcitx5、Voxtype、PipeWire、keyd 和通知服务的所有权；
- 将不依赖桌面环境的服务移到普通 NixOS/Home Manager 配置。

### 批次三：Hyprland 专用接线

- 清点 `modules/desktop.nix` 中真正属于 Hyprland 的部分；
- 把需要保留的窗口规则、主题、启动项和脚本迁移到独立的 Hyprland 模块；
- 让 Anchor Shell 和 Hyprland shell 使用不同的服务、路径和状态目录。

### 批次四：移除 Nixarchy 模块

- 移除 `inputs.nixarchy.nixosModules.nixarchy`；
- 移除 `inputs.nixarchy.homeManagerModules.nixarchy`；
- 删除 `programs.nixarchy` 配置块及剩余应用选择导入；
- 从 `flake.nix` 删除 Nixarchy input；
- 重新构建 Labwc、Hyprland、Sway/KDE 目标并进行回归测试。

批次四只是未来的删除评估阶段，不属于当前执行范围。只有在完整迁移验收、
双环境回归测试和用户明确确认后，才讨论是否删除 Nixarchy。

## 7. 本批次验证记录

已完成：

- `nixos-rebuild build --impure --flake /home/tetsuya/nixos-config#hx90`
- `sudo nixos-rebuild switch --impure --flake /home/tetsuya/nixos-config#hx90`
- `nix flake check --no-build --impure`
- Labwc 源码中不再存在 `config.programs.nixarchy.package`；
- `anchor-fcitx5.service` 已成功运行并加载 Rime；
- `omarchy-fcitx5.service` 在当前 Labwc 会话中未运行；
- Telegram 可从 `/run/current-system/sw/bin/Telegram` 启动；
- 当前 Quickshell 实例仍从 `modules/anchor-shell/shell.qml` 加载。
- 当前实例的用户配置已从 `~/.config/anchor-shell/shell.json` 读取；
- 当前用户状态目录已切换到 `~/.local/state/anchor-shell/`；
- Anchor Shell 插件注册器只扫描仓库插件和 `~/.config/anchor-shell/plugins/`，
  不扫描 Hyprland 的 `~/.config/omarchy/plugins/`。

## 8. 回滚方式

本批次没有删除旧源码。若需要回退，可以：

1. 选择上一代 NixOS generation；或
2. 恢复 `modules/labwc.nix` 的上一版本并重新执行 NixOS switch；或
3. 将 Quickshell 模式切回旧的开发副本进行对照测试。

在 Nixarchy 完全移除前，不应执行大范围垃圾回收，以便保留旧 generation 和
旧运行时作为回退依据。
