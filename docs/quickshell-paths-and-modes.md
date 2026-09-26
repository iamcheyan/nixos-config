# Anchor Shell 路径与运行模式

Labwc 的 Quickshell 源码在：

```text
/home/tetsuya/nixos-config/modules/anchor-shell
```

完整边界见 `modules/anchor-shell/ARCHITECTURE.md`。

## 两种模式

`~/.config/anchor-shell/mode` 控制启动器读哪棵树。

### nix（默认）

NixOS 把本目录复制成不可变 store 路径：

```text
QUICKSHELL_ROOT=/nix/store/<hash>-anchor-shell
```

改源码后要 `nixos-rebuild switch --impure`，再重启 shell。`/nix/store` 不能
当工作副本改。

### dev

直接读 Git 工作树：

```text
QUICKSHELL_ROOT=/home/tetsuya/nixos-config/modules/anchor-shell
```

```bash
quickshell-mode dev
quickshell-mode status
```

改 QML 后再执行一次 `quickshell-mode dev` 即可重启。切回：

```bash
quickshell-mode nix
```

用户插件始终在 `~/.config/anchor-shell/plugins/`。first-party 插件从
`QUICKSHELL_ROOT/plugins` 扫描。

## 不能混路径

一次运行里，`quickshell -p` 和 `QUICKSHELL_ROOT` 必须指向同一棵树。

```bash
quickshell list --all
pid=$(quickshell list --all | awk '/Process ID:/ {print $3; exit}')
tr '\0' ' ' < /proc/$pid/cmdline; echo
tr '\0' '\n' < /proc/$pid/environ | rg '^QUICKSHELL_|^ANCHOR_'
```

开发模式应全部是仓库路径；正式模式应全部是同一个 `...-anchor-shell`
store 路径。出现不一致时，停掉多余实例，再用 `quickshell-mode` 选一种
模式重启。不要同时用手动 `systemd-run`、autostart 和旧后台进程。

`quickshell-mode` 会杀掉当前用户下任意 Quickshell 实例。只在 Labwc 会话
里用。
