# nixos-config 部署流水线（CI 构建 → 控制器调度 → 机器兜底）

## 三个角色

1. **CI 构建**（`ci-build.yml`）
   推送到 `main` 或 `bot/auto-update` 且改动涉及 `flake.nix` / `flake.lock` /
   `hosts/**` / `modules/**` / `*.nix` 时，在 GitHub runner 上
   `nixos-rebuild build --impure --flake .#hx90`（含 Inua，靠 `INUA_DEV_DIR`
   指向 checkout 出的 iamcheyan/inua）。构建成功才进入下一步。
   纯文档改动不会触发构建，因此不会误部署。

2. **控制器（Hermes webhook → OMP agent）**
   CI 成功后向 `HERMES_WEBHOOK_URL` 发送带 HMAC 签名的 POST（payload 含
   `repo/ref/sha/host`）。Hermes 收到后派一个 agent SSH 到 HX90，运行
   `scripts/nixos-apply.sh --controller --ref <ref>`：
   - 把未提交改动 `git stash`（保护在做的 feature 分支 WIP）；
   - `git fetch` + `checkout --detach origin/<ref>`（用 CI 验证过的闭包，
     不再浮动输入）；
   - `sudo nixos-rebuild switch`；
   - 写入哨兵文件 `~/.local/state/nixos-deploy/last-controller-apply`。

3. **机器兜底（`modules/deploy.nix` 的 daily timer）**
   仅当控制器哨兵超过 26 小时未更新时，运行
   `scripts/nixos-apply.sh --fallback`，即完整 `nixos-update`
   （浮动 flake 输入 + 更新 Omarchy 插件 + 构建 + 切换）。控制器在线时
   兜底永远跳过。

## 关键安全点

- 两个路径都经过 `scripts/nixos-apply.sh`，**绝不使用 `git reset --hard`**；
  未提交改动一律 stash 并在结束后 pop 回去。
- 控制器确定性部署 CI 验证过的 ref；兜底才浮动输入。二者用 `flock` 互斥，
  不会并发 rebuild。
- 自动更新只浮动**当前跟踪分支的 tip**（拿到 26.05 安全 backport），
  不会把 nixpkgs 升到新大版本。

## 需要的密令（GitHub Actions secrets）

- `HERMES_WEBHOOK_URL`：暴露到公网、指向 Hermes gateway webhook 的地址。
- `HERMES_WEBHOOK_SECRET`：与 Hermes webhook 订阅共享的 HMAC 密钥。
- `NIX_CI_GITHUB_TOKEN`：能读取 `iamcheyan/inua` 的 token（inua 为私有库时必需）。

## 启用步骤

1. 在 GitHub 仓库 Settings → Secrets 填入上述三个 secret。
2. 在 HX90 上 `sudo nixos-rebuild switch --flake ~/nixos-config#hx90` 一次，
   安装 daily 兜底 timer（之后由流水线自行维护）。
3. 暴露 Hermes webhook 端口（cloudflared / tailscale serve）并确认
   `hermes webhook list` 中 `nixos-deploy` 订阅已存在。
4. 手动 `gh workflow run auto-update.yml` 验证一次端到端。
