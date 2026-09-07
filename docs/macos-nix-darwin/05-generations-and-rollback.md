# generation、回滚与安全

## 什么是 generation

每次 nix-darwin 激活都会产生新的系统 profile，通常包括系统包、`/etc` 生成文件、
shell 初始化、launchd plist、Home Manager 生成和当前配置的构建产物。

旧 generation 通常仍然保留，所以配置错误时可以回到之前的系统 profile。

## 切换前检查

```bash
cd ~/nixos-config
git status --short --branch
git diff -- flake.nix flake.lock hosts modules docs
nix flake check --no-build
nix build .#darwinConfigurations.macbook-m1-max.system --no-link
```

## 查看和回滚

```bash
sudo /run/current-system/sw/bin/darwin-rebuild --list-generations
sudo /run/current-system/sw/bin/darwin-rebuild switch --rollback
```

具体版本的参数以帮助为准：

```bash
/run/current-system/sw/bin/darwin-rebuild --help
```

## 回滚的边界

Darwin generation 可以回滚 Nix 包、`/etc` 生成内容、Home Manager 激活内容和
launchd 声明。它不会自动回滚：

- Homebrew 应用写入的用户数据；
- 浏览器 profile；
- SSH key、Bitwarden session、`.env`；
- 模型、缓存、项目源码和构建目录；
- macOS TCC 授权数据库；
- macOS 系统升级。

所以 generation 是配置回滚，不是整机备份。重要数据仍需独立备份。

## 不要急着清理旧 generation

完成新 Terminal、CLI、Homebrew GUI、Home Manager、输入法、浏览器和 Agent 的
真实验证后，再考虑清理。切换成功不等于所有用户功能都已完成。

## 秘密与日志

不要把 `.env`、SSH 私钥、Bitwarden session、浏览器 cookie、API key 或个人机器
序列号贴进 issue、提交或学习文档。命令输出可以保留错误类型，但应删除敏感值。
