# Quickshell 路径与运行模式

本文记录 NixOS 配置中的 Quickshell 如何加载文件，以及开发模式和正式模式的边界。

## 为什么修改文件后有时没有反应

本仓库的 Quickshell 源码位于：

```text
/home/tetsuya/nixos-config/modules/quickshell
```

正式的 NixOS 配置会把这份目录复制成一个不可变的 Nix store 路径，例如：

```text
/nix/store/<hash>-quickshell-shell
```

正式运行时，Quickshell 可能从这个 store 路径读取：

```text
/nix/store/<hash>-quickshell-shell/shell.qml
/nix/store/<hash>-quickshell-shell/plugins/...
/nix/store/<hash>-quickshell-shell/third-party/...
```

`/nix/store` 不是源码目录，不能直接修改。修改仓库后，旧的 store 副本不会自动改变，因此只重启 Quickshell 仍然会启动旧版本。需要执行 `nixos-rebuild switch`，让 Nix 生成新的 store 副本并切换系统 generation。

这不是每次都重新编译所有依赖。没有变化的依赖会从 Nix 缓存复用，通常只有 Quickshell shell 目录和受影响的派生项会重新生成。

## 两种模式

## Omarchy 兼容运行时迁移模式

Quickshell 目前还保留 Omarchy 的命令名和目录契约，但运行时副本正在迁移到
本仓库的 `modules/quickshell/compat/omarchy/`。Labwc 默认继续使用旧的
Nixarchy store 副本；验证迁移副本时可以切换到本地兼容副本：

```bash
~/.local/bin/quickshell-mode runtime compat
~/.local/bin/quickshell-mode status
```

回退到原来的 Nixarchy store 副本：

```bash
~/.local/bin/quickshell-mode runtime legacy
```

两种运行时都保留 `NIXARCHY_ROOT`、`OMARCHY_PATH` 和 `omarchy-*` 命名，因此
现有 QML 与插件不需要立即改名。迁移完成并验证前，不要卸载 Nixarchy/Omarchy。

### Nix 正式模式

正式模式使用 Nix store 路径：

```text
QUICKSHELL_ROOT=/nix/store/<hash>-quickshell-shell
QUICKSHELL_PLUGINS_DIR=/nix/store/<hash>-quickshell-shell/third-party
```

适合日常稳定使用，修改 `modules/quickshell/` 后执行：

```bash
cd ~/nixos-config
nix flake check --no-build --impure
sudo nixos-rebuild switch --impure --flake .#hx90
```

切换完成后，系统启动脚本会使用新的 Quickshell store 路径。

### dev 开发模式

开发模式直接读取 Git 工作树，不需要把源码软链接进 `/nix/store`：

```text
QUICKSHELL_ROOT=/home/tetsuya/nixos-config/modules/quickshell
QUICKSHELL_PLUGINS_DIR=/home/tetsuya/nixos-config/modules/quickshell/third-party
```

切换到开发模式：

```bash
~/.local/bin/quickshell-mode dev
~/.local/bin/quickshell-mode status
```

状态应显示：

```text
Quickshell mode: dev
```

开发模式下修改 QML、manifest 或插件后，只需要让 Quickshell 重启/重新加载，不需要 `nixos-rebuild switch`。切回正式模式：

```bash
~/.local/bin/quickshell-mode nix
```

## 最重要的规则：不能混合路径

一次运行中的 Quickshell 必须满足以下条件之一：

```text
开发模式：命令行、QUICKSHELL_ROOT、QUICKSHELL_PLUGINS_DIR 全部指向仓库
正式模式：命令行、QUICKSHELL_ROOT、QUICKSHELL_PLUGINS_DIR 全部指向同一个 store 路径
```

不能出现这种混合状态：

```text
quickshell -p /home/tetsuya/nixos-config/modules/quickshell
QUICKSHELL_ROOT=/nix/store/<old-hash>-quickshell-shell
QUICKSHELL_PLUGINS_DIR=/nix/store/<old-hash>-quickshell-shell/third-party
```

这种状态会造成非常容易误判的现象：`shell.qml` 似乎使用了新文件，但插件 manifest、第三方插件或 bar widget 仍然来自旧 store 版本。之前电源按钮消失就是这个问题：运行参数看起来是仓库路径，但 `QUICKSHELL_PLUGINS_DIR` 仍然指向旧 store，旧的电源 manifest 仍把 bar 入口指向 `Panel.qml`，没有加载新的 `BarWidget.qml`。

## 如何确认实际加载路径

查看当前实例：

```bash
quickshell list --all
ps -eo pid,ppid,args | rg 'quickshell|inotifywait.*quickshell'
```

拿到 Quickshell 的 PID 后检查环境：

```bash
pid=<quickshell-pid>
tr '\0' '\n' < /proc/$pid/environ | rg '^QUICKSHELL_(ROOT|PLUGINS_DIR|CONFIG)='
tr '\0' ' ' < /proc/$pid/cmdline
```

开发模式应该全部显示 `/home/tetsuya/nixos-config/modules/quickshell`；正式模式应该全部显示同一个 `/nix/store/<hash>-quickshell-shell`。

如果命令行路径和 `QUICKSHELL_*` 环境变量不一致，先停止残留的旧 Quickshell 实例，再通过 `quickshell-mode dev` 或 `quickshell-mode nix` 选择一种模式重新启动。不要同时使用手动 `systemd-run`、labwc autostart 和旧的后台 Quickshell 进程，否则容易出现多个实例和旧环境残留。

## 为什么不使用软链接

直接修改或软链接 `/nix/store/<hash>-quickshell-shell` 不适合 Nix 配置：

- store 路径由输入内容和 hash 决定，下一次 rebuild 会生成新的路径；
- store 内容由 Nix 管理，直接替换会破坏可复现性；
- 软链接只解决路径表面问题，不能自动解决 manifest、插件目录和环境变量不一致；
- 当前配置已经提供 dev 模式，可以安全地直接使用 Git 工作树。

因此建议：开发时使用 `quickshell-mode dev`，稳定使用时使用 `quickshell-mode nix`，不要混合两种模式。
