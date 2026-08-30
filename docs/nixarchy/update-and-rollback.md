# 更新、验证与回滚

## 推荐更新流程

先只更新 Nixarchy：

```bash
cd /home/tetsuya/nixos-config
nix flake lock --update-input nixarchy
nix flake check --no-build
sudo nixos-rebuild build --flake .#aarch64
sudo nixos-rebuild switch --flake .#aarch64
```

更新前后可查看：

```bash
git diff -- flake.lock
git status --short
```

## 更新全部依赖

风险更高：

```bash
nix flake update
nix flake check --no-build
sudo nixos-rebuild build --flake .#aarch64
sudo nixos-rebuild switch --flake .#aarch64
```

## 会话验证

进入 Omarchy 会话后运行：

```bash
nix run github:olafkfreund/nixarchy#verify
```

## 回滚

```bash
sudo nixos-rebuild switch --rollback
```

也可以在 systemd-boot 启动菜单选择上一代 NixOS generation。系统配置和软件可回滚，但用户目录运行时状态、浏览器数据、keyring 和外部服务数据不一定回滚。

## 提交锁定结果

```bash
git add flake.nix flake.lock hosts modules docs/nixarchy
git commit -m "chore: update nixarchy"
```
