# macOS 的 Nix / nix-darwin 学习手册

这组文档记录把当前 Mac 纳入本仓库管理的完整过程，也作为以后维护这台机器的
操作手册。建议按顺序阅读：

1. [这次做了什么](./01-what-changed.md)
2. [配置结构与职责边界](./02-architecture.md)
3. [日常使用与更新](./03-daily-operations.md)
4. [Homebrew、Home Manager 与 chezmoi](./04-ownership-and-boundaries.md)
5. [generation、回滚与安全](./05-generations-and-rollback.md)
6. [安装、权限和故障排查](./06-troubleshooting.md)
7. [以后如何扩展配置](./07-how-to-extend.md)
8. [macOS 专属配置迁移记录](./08-migrating-macos-only-config.md)
9. [Mac 软件清单与声明式管理](./09-software-inventory-and-management.md)
10. [Home Manager 配置归属审计](./10-home-manager-config-audit.md)

总入口文档仍然是 [`../macos-nix-darwin.md`](../macos-nix-darwin.md)。本目录提供
更细的学习材料，不替代仓库顶层的 `AGENTS.md`。

## 当前状态

截至 2026-09-07：

- Nix 2.35.2 已安装；
- nix-darwin 26.05 已激活；
- 当前 Darwin system link 指向 `darwin-system-26.05.c3e90c8`；
- Darwin 配置 build 已通过；
- Homebrew 的 Brewfile 依赖已安装/确认完成；
- Home Manager 已完成 `tetsuya` 用户激活、文件链接和 LaunchAgents 设置；
- 现有 Homebrew、dotfiles、用户数据和应用运行时目录没有被整体删除；本次明确将
  macOS 专属配置源文件从 chezmoi 迁移到了本仓库。

## 一句话理解

这台 Mac 现在不是“变成了 NixOS”，而是：

```text
Apple macOS 仍然负责内核、APFS、Recovery、系统更新和硬件
        │
        └── nix-darwin 负责声明式系统层
              ├── Nix 与系统 profile
              ├── Nix 包
              ├── Homebrew formula/cask
              ├── 部分 macOS defaults
              ├── launchd / activation
              └── Darwin generation
```

用户文件和秘密仍然由 `chezmoi` / `dotfiles` 管理，不是所有东西都要塞进 Nix。
