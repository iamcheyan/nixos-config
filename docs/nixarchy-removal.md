# Nixarchy 依赖移除与本机接管

## 目标和边界

HX90 保留 NixOS、Labwc + Anchor Shell、SDDM、Plasma 以及备用 Hyprland 会话。
移除的是外部 Nixarchy flake 和它的模块/overlay/应用目录生成机制。
Omarchy 的现有 shell、命令和主题仍是桌面的兼容资源；历史 `omarchy-*`、
`nixarchy-ask`、`nixarchy` skill 名不代表系统继续依赖 Nixarchy。

## 接管清单

| 功能 | 本仓库声明 |
|---|---|
| 原桌面运行包、预装应用、服务、字体、锁屏 PAM、XCompose、Plymouth、LocalSend 端口 | `modules/desktop-runtime.nix` |
| 本地兼容脚本、图标、字体、主题、解释器路径修复 | `modules/packages/desktop-compat.nix`、`normalize-desktop-compat.py` |
| 锁定的 Hyprland 与 portal | `flake.nix` 的独立 `hyprland` 输入；保留原 commit 及依赖 pin |
| Labwc / Anchor Shell 会话 | `modules/labwc.nix`、`modules/anchor-shell/` |
| QQ / 微信下载覆盖 | `hosts/hx90/apps.nix` |
| devenv、devenv-init 预设与 bash/zsh/fish 自动进入项目环境 | `modules/devenv.nix`，由 HX90 导入 |
| 全局 Agent 背景、系统 skills、GTK 主题服务、缺失默认配置初始化 | `modules/home-manager/nixos-user.nix` |
| 快照后更新、候选构建、切换、失败还原 lock、历史记录 | `scripts/nixos-update.sh`、`modules/update-snapshots.nix` |

兼容主题使用直接锁定的 Omarchy 上游源码作为资源来源，固定 revision 和 hash；
不引入 Nixarchy 模块。保留 ttfx 的固定源码与 Cargo hash 为本地 package。

## 移除与行为变化

- 删除 `inputs.nixarchy`，清除其独占的 lock 节点与 Nixarchy binary cache 声明。
- 删除生成式 `nixarchy-apps.nix` 与两套旧 apps/services/advanced 目录。
- 停止使用 `programs.nixarchy.*`，改为真实 NixOS options。
- 安装包/服务直接编辑本仓库模块，查看 diff 后 rebuild；旧菜单安装入口显示新工作流。
- `omarchy-update` 进入 `nixos-update`。更新候选来自本仓库独立 flake 输入，
  不再查询或尝试 Nixarchy release。
- 不再提供 Nixarchy 安装器的仓库初始化、云备份、local AI 交互配置或 unfreeze。
  本机此前没有启用相应后台服务；今后通过 Git、真实 NixOS options 和专项 skill 管理。
- 私人用户配置、主题状态、插件 checkout 和 chezmoi/dotfiles 保留。

保留旧 generations 作为回滚入口，未执行垃圾回收。现有 shell 进程若仍持有旧
store 资源，需要在安全的未锁屏状态重启对应用户 shell 服务或重新登录。

## 验证记录

迁移前包与 systemd 单元基线保存在本次工作临时文件
`/tmp/nixarchy-migration-baseline.json`。最终构建、应用与运行状态记录见下方完成记录。

### 完成记录（2026-09-26，HX90）

- `nix flake check --no-build --impure` 通过 aarch64、hx90、wsl 输出检查。
- HX90 完整构建、临时应用及最终 `switch --impure` 成功。
- 当前 generation：`/nix/store/cnfd07s9lspbbgdx97gv41l00ws9r121-nixos-system-hx90-26.05.20260903.a5cc6f2`。
- 当前 Labwc 进程保留；Anchor Shell 只有一个实例，已加载本地新 store 路径。
- 输入法、休眠前锁屏监视、崩溃通知服务均 active；系统与用户失败单元均为空。
- Labwc 现在显式启动休眠锁屏/崩溃监视，避免只依赖它没有启动的 graphical-session.target。
- 锁屏 IPC 能返回状态，`passwordPam=true`，识别两个屏幕；未执行交互式锁屏认证、休眠或重启。
- 五个全局背景入口和四组共 12 个系统 skill 链接由 Home Manager 部署。
- 顶层其他 flake 输入未升级，Hyprland 与迁移前保持同一实际包路径。
- `nixos-update --help` 和 `devenv-init --list` 能正常执行；未运行实际软件更新。
- 旧 `~/.config/nixarchy` 已迁入 `~/.local/state/nixos-migration/2026-09-26-nixarchy-config` 备查，不再作为配置来源。
- 未提交 Git commit，未清理旧 generations。旧终端可保留旧环境变量，重新打开终端/Agent 会话即可加载新背景。

检查日志保存在本次任务的 `/tmp/nixarchy-migration-{check,build,test,switch}.log`；
临时日志不作为长期维护源。
