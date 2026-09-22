# Quickshell 迁移清单

这份清单描述“先完整迁移、暂不移除外部接线”的中间状态。迁移期间默认行为
保持不变：旧的 Nixarchy/Omarchy 运行时仍可作为回退，仓库内副本可以单独验证。

## 已纳入本仓库

- `compat/omarchy/`：当前使用的 Omarchy 运行时快照，包括 `bin/`、first-party
  shell、默认配置、命令名和 `omarchy-*` 兼容接口。
- `third-party/`：当前用户插件的完整源代码、manifest 和测试：
  `hancore.overview-workspaces`、`hancore.voxtype-enhance`、
  `iamcheyan.active-window`、`iamcheyan.clipboard`、`iamcheyan.launcher`、
  `iamcheyan.lock-screen`。
- `nixarchy-import-session-environment`：保留历史命令名，但实现已经由本仓库
  管理，不再依赖用户目录里的旧脚本。
- Quickshell 的运行时选择：`runtime legacy` 和 `runtime compat`；两者都继续
  导出 `NIXARCHY_ROOT`、`OMARCHY_PATH` 和原有 `omarchy-*` 命名。
- `quickshell-topbar`：可供 Labwc、Sway、KDE Wayland 复用的通用启动入口。
  应用启动会优先使用 `uwsm-app`，没有该命令时回退到普通 argv 启动。
- Omarchy 的统一复制/粘贴逻辑已迁入
  `modules/labwc/labwc/scripts/universal-clipboard`，保留终端使用
  Ctrl+Insert/Shift+Insert、普通应用使用 Ctrl+C/V 的行为。

## 当前仍保留的外部接线

以下内容故意暂时没有删除，也不应在迁移验证完成前删除：

- `programs.nixarchy.package` 作为 `runtime legacy` 回退；
- Home Manager 的 `inputs.nixarchy.homeManagerModules.nixarchy` 和
  `programs.nixarchy` 配置；
- `~/.config/omarchy/plugins.list` 及其原有远程仓库地址；
- PluginRegistry 对 `~/.config/omarchy/plugins/` 的兼容扫描路径。

这些项目现在不是仓库内运行时的唯一来源，但保留后可以随时回退，不改变当前
桌面会话的使用方式。

## 已完成的验证

- `nix flake check --no-build --impure` 通过；
- `nixos-rebuild build --impure --flake /home/tetsuya/nixos-config#hx90` 通过；
- 仓库内插件测试通过：overview 59 项、voxtype 27 项；
- 58 个实际 `omarchy-*` 兼容命令在仓库副本中均存在；
- 使用仓库副本启动 Quickshell 的短时 smoke test 通过，完成配置加载和插件扫描；
- 新系统闭包包含本地 `quickshell-shell`、`quickshell-omarchy-compat` 和启动脚本。
- 运行时切换会先读取实例 PID，再精确停止单个 Quickshell 实例，兼容不同
  Quickshell CLI 对 `--newest` 的差异。

## 下一阶段删除前的验收条件

1. 将运行时切到 `compat`，在真实 Labwc 会话中确认顶栏、菜单、剪贴板和插件；
2. 确认 Sway/KDE Wayland 使用 `quickshell-topbar` 时仍能加载基础顶栏；
3. 再逐项移除 Nixarchy 模块、legacy root 和远程插件安装接线；
4. 每次移除后重新执行 flake check、NixOS build、Quickshell 单实例检查和视觉检查。
