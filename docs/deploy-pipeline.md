# nixos-config 部署流水线（CI 校验 → 控制器调度 → 机器兜底）

本文记录这条流水线的**需求来源、实现结构、上线所需准备、设计取舍与实测验证**，
供以后换机器或故障排查时按图索骥。

> 本文含内部拓扑（主机名、私有路径、运行方式），**不发布到公网手册站**；
> 正文永远不写任何密钥值、token、公网地址或内网 IP。

---

## 1. 需求（要解决什么）

起因是日常的一个体验落差：在别的项目里刷到 CVE，回头一看 CI 已经把补丁编译好、
机器也自动更新了；而本仓库的 NixOS 配置此前只有**手动**更新路径
（`nixos-update` / `nixos-rebuild switch`）。目标是把同样的能力补齐：

1. **CI 先验证**：配置改动在合入后由 CI 求值/校验，不要等机器上构建时才发现坏了。
2. **控制器调度机器应用**：CI 通过后，由控制器决定"哪台机器、应用哪个已验证的版本"。
3. **机器兜底自更新**：控制器失联（断网、服务挂了、密钥过期）时，机器自己能跑完整
   更新，不能因为控制器不在就永久停在旧版本。
4. **日常自动跟进**：不只是手动修 CVE，还要有定时任务自动浮动依赖，吃到安全 backport。

### 硬约束（决定了实现形态）

| 约束 | 影响 |
|---|---|
| 本仓库是**私有**仓库，且 CI 需要读私有 flake input（shizuka、labwc-plus） | CI 必须注入一个可读私有库的 token |
| 宿主机**没有公网 IP**，GitHub Actions 无法直连内网 | 控制器必须有一个"可被 GitHub 访问"的入口，或改为 pull 模式 |
| 机器上常有**未提交的 feature 分支工作**（例如正在做的 Inua 分支） | 任何自动部署都**不能** `reset`/`checkout` 丢改动，必须先 stash 再恢复 |
| nixpkgs 刻意钉在 `nixos-26.05` 基线 | 自动更新只允许浮动**当前分支的 tip**（拿安全 backport），**禁止**跨大版本 |
| Inua 由 `INUA_DEV_DIR` 指向**可变本地开发树**，`vendorHash` 跟着未推送代码走 | CI 无法复现该闭包 → CI 只做求值校验，不承诺完整编译（见 §4） |

---

## 2. 实现结构

```
.github/workflows/
  ci-build.yml          CI 校验 + 成功后通知控制器
  auto-update.yml       每日浮动 flake 输入 → bot/auto-update 分支
scripts/
  nixos-apply.sh        唯一的部署入口（控制器模式 / 兜底模式）
modules/
  deploy.nix            HX90 的每日兜底 timer（哨兵门控）
hosts/hx90/configuration.nix
  imports += ../../modules/deploy.nix
docs/
  deploy-pipeline.md    本文
```

控制器一侧（不在本仓库，属 Hermes 运行时目录）：
`~/.hermes/scripts/nixos-deploy-hook.sh` —— webhook 路由脚本。

### 2.1 CI 校验（`ci-build.yml`）

- 触发：推送到 `main` 或 `bot/auto-update`，且改动命中
  `flake.nix` / `flake.lock` / `hosts/**` / `modules/**` / `*.nix`。
  纯文档改动不触发，避免误部署。
- 步骤：装 Nix（含公开 binary cache）→ 注入私有 input 凭证 →
  checkout 公开的 Inua 仓库作为 `INUA_DEV_DIR` → `nix build --dry-run --impure`
  对 hx90 toplevel 求值 → 成功则 POST 通知控制器。
- 为什么是 `nix build --dry-run` 而不是 `nix flake check --no-build`：
  `--no-build` 不会真正取回 git 类型的 flake input，而部分模块在求值期会
  `readFile "${src}/VERSION"`，于是报 `path ... is not valid`；
  `nix build --dry-run` 会先取回 input 再求值，且仍然**不编译**。

### 2.2 控制器（Hermes webhook 路由脚本）

- CI 成功后向 `HERMES_WEBHOOK_URL` 发送带 HMAC-SHA256 签名的 POST，
  payload 含 `repo / ref / sha / host / event`。
- Hermes 的 `nixos-deploy` 订阅用**路由脚本**处理（不是 agent 推理，确定性、零 LLM 成本）：
  1. 把 `scripts/nixos-apply.sh` scp 到目标机（不依赖目标机工作树里是否已有该脚本）；
  2. `systemd-run` 起一个瞬时单元，以普通用户身份执行
     `--controller --ref <ref>`；
  3. 立刻返回 `scheduled`（部署在目标机独立继续，不占 HTTP 请求、不怕 GitHub 超时）。
- 未签名请求返回 401；签名请求返回 200 并投递一条 Telegram 结果。
- 选择 webhook 而非"CI 直连 SSH"的原因：GitHub 侧只需一个 URL + 密钥，
  不必把机器 IP/SSH 凭据放进 Actions；也避免 CI 任务等待一次长时间 rebuild。

### 2.3 机器兜底（`modules/deploy.nix`）

- 每日 timer（带随机延迟、`Persistent=true`），调用
  `scripts/nixos-apply.sh --fallback`。
- 门控：脚本读取哨兵文件
  `~/.local/state/nixos-deploy/last-controller-apply` 的 mtime；
  **26 小时内控制器来过就跳过**，否则运行完整 `nixos-update`
  （浮动输入 + 更新 Omarchy 插件 + 构建 + 切换）。
- 26h 略大于一天：控制器正常时每日自动更新会刷新哨兵，兜底永不触发；
  控制器一天以上没动静，兜底才接手。

### 2.4 唯一部署入口（`scripts/nixos-apply.sh`）

两种模式，共用安全逻辑：

| | `--controller` | `--fallback` |
|---|---|---|
| 触发者 | CI → webhook → 控制器 | 本机 daily timer |
| 版本来源 | `git fetch` + `checkout --detach origin/<ref>`，**不浮动输入** | 本机 `nixos-update`（浮动输入 + 插件） |
| 语义 | 部署 CI 已验证的那一个版本，可复现 | "控制器失联了，自己跟上最新" |
| 收尾 | 写哨兵，供兜底判断 | 不写哨兵 |

共同保证：

- **绝不 `git reset --hard`**；有未提交改动先
  `git stash push --include-untracked`，结束时 `stash pop`；
  pop 失败时明确告警并保留 stash，不强行覆盖。
- 自备 PATH（NixOS 的 `git`/`sudo`/`nixos-rebuild` 在 `/run/current-system/sw/bin`
  等目录），可在最小 PATH 的 systemd 瞬时单元里运行。
- `flock` 单实例锁：控制器与兜底**不会并发 rebuild**。
- `--dry-run` 只打印计划，不改动任何东西（含不 stash）。

---

## 3. 上线所需（按顺序）

1. **GitHub Actions secrets**（仓库 Settings → Secrets）：
   - `NIX_CI_GITHUB_TOKEN`：可读私有 flake input 的 token。
   - `HERMES_WEBHOOK_URL`：指向 Hermes webhook 的**可达地址**。
   - `HERMES_WEBHOOK_SECRET`：与订阅共享的 HMAC 密钥。
     （值在本机 `~/.hermes/.env` 的 `WEBHOOK_SECRET`，不要复制进本文或聊天。）
2. **让地址可达**：Hermes webhook 默认只监听本机。需要用隧道/funnel 之类把
   该端口暴露给 GitHub，或用自托管 runner 替代。未暴露前，CI 仍会绿，
   只是 notify 步骤会打印"跳过"并正常结束。
3. **本机 Hermes 侧**：
   - `hermes config set platforms.webhook.enabled true`
   - `hermes config set platforms.webhook.extra.port 8644`
   - `.env` 里 `WEBHOOK_ENABLED/WEBHOOK_PORT/WEBHOOK_SECRET`
   - 重启 gateway 后 `curl http://127.0.0.1:8644/health` 应为 `ok`
   - `hermes webhook list` 里应有 `nixos-deploy` 订阅
4. **目标机装 timer**：一次
   `sudo nixos-rebuild switch --flake ~/nixos-config#hx90`，
   之后由流水线自行维护。
5. **端到端自检**：`gh workflow run auto-update.yml`，确认
   auto-update → `bot/auto-update` 提交 → 触发 ci-build → 绿。

---

## 4. 设计取舍与已知限制

> 这一节记录"为什么不是另一种做法"，以及哪些地方**刻意**没做到。

### 4.1 CI 只做求值校验，不做完整闭包编译

`inux.nix` 用 `INUA_DEV_DIR` 指向本机 Inua 开发树（含未提交改动），
`buildGoModule` 的 `vendorHash` 因此跟着**未推送的 go.sum** 走。
CI 从 git 拉到的 Inua 与本地树不一致，实测必然报
`hash mismatch in fixed-output derivation ... go-modules`。

因此：

- CI 的职责 = 尽早发现**配置层**错误（模块求值、option 类型、主机间冲突）。
- 完整闭包编译发生在**目标机应用时**（有真实开发树 + 本地 store 缓存）。

若要 CI 也真编译，需要把 Inua 改成**钉死 rev 的 flake input**，
并让 `vendorHash` 与之一致；代价是改动 Inua 的开发流程，属产品决策，未擅自做。

### 4.2 自动更新只浮动分支 tip

`nix flake update` 会把每个 input 更新到其**已配置 ref 的最新提交**。
由于 nixpkgs 的 ref 是 `nixos-26.05`，浮动结果是**该分支的安全 backport**，
不是升级到 26.09。这正是想要的：持续收 CVE 修复，同时保持大版本基线稳定。

### 4.3 自动更新走独立分支而不是直推 main

`auto-update.yml` 提交到 `bot/auto-update`，再由该分支的 push 触发 CI 校验。
好处：main 的历史保持"人写的变更"，机器提交单独可查、可一次性丢弃；
且 main 不会因为一次上游破坏性更新就被污染。

### 4.4 控制器为什么是脚本而不是 agent

部署是**确定性动作**：给定 ref，执行固定步骤。用 agent 推理只会引入
不确定性、token 成本和"模型决定不部署"的风险。
需要诊断时再由人或在 Telegram 结果上追查即可。

### 4.5 兜底为什么是完整 `nixos-update` 而不是"只应用已验证提交"

控制器失联时，已无"已验证版本"可谈；此时目标是**尽快吃上安全修复**。
`nixos-update` 自带快照（snapper）、构建成功才切换、失败自动回滚 flake 文件，
是这条路径上最安全的既有工具。

### 4.6 未解决的

- 控制器路径在主机关机/休眠时无法应用；恢复后要等下一次 CI 事件或兜底 timer。
- 若 `stash pop` 与目标 ref 冲突，脚本保留 stash 并告警，需要人工处理。
- webhook 入口若被替换/重建（隧道换了域名），要同步更新 `HERMES_WEBHOOK_URL`。

---

## 5. 实测验证记录

| 项目 | 做法 | 结果 |
|---|---|---|
| flake 在加入 `deploy.nix` 后仍可求值 | 独立 worktree 中 `nix flake check --no-build --impure` | 全主机通过 |
| timer / service 生成正确 | `nix eval` 读取 `timerConfig`、`serviceConfig` | `daily` + 随机 2h + persistent；`Type=oneshot`、`User=tetsuya` |
| 私有 input 鉴权 | CI 中注入 token 后求值 | 通过（此前报 rev not found，实为私有库鉴权失败） |
| CI 端到端 | push / `workflow_dispatch` | 绿；notify 未配置时安全跳过 |
| 自动更新闭环 | `gh workflow run auto-update.yml` | 生成 `bot/auto-update` 提交 → 触发 ci-build → 绿 |
| webhook 鉴权 | 签名 POST / 未签名 POST | 200 已投递 / 401 拒绝 |
| 部署脚本在最小 PATH 下可运行 | 目标机 `systemd-run` 跑一次性仓库 + 伪 ref | `git` 正常解析，在 fetch 处安全失败，未触碰系统 |
| 脚本不误伤工作树 | `--dry-run` | 不 stash、不改动 |

---

## 6. 运维手册

```bash
# 看订阅与 webhook 健康
hermes webhook list
curl -sS http://127.0.0.1:8644/health

# 看 CI
gh run list -R <owner>/nixos-config --workflow ci-build.yml --limit 5

# 手动触发一次自动更新
gh workflow run auto-update.yml -R <owner>/nixos-config --ref main

# 手动模拟控制器部署（不改工作树，只打印计划）
./scripts/nixos-apply.sh --controller --ref main --dry-run

# 目标机上查看兜底 timer / 最近一次部署
systemctl list-timers 'nixos-deploy*'
journalctl -u 'nixos-deploy*' -n 50 --no-pager

# 哨兵时间（判断控制器是否还活着）
stat -c '%y' ~/.local/state/nixos-deploy/last-controller-apply

# 回滚
sudo nixos-rebuild switch --rollback
```

紧急停用：`systemctl disable --now nixos-deploy-fallback.timer`，
并在 GitHub 删除 `HERMES_WEBHOOK_URL` secret（notify 即变安全空操作）。
