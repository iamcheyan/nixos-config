# 更新、验证与回滚

## `omarchy update` 在 NixOS 上做什么

Nixarchy 替换了 Omarchy 原本面向 Arch/pacman 的更新器。本机执行
`omarchy update` 时，实际按以下顺序运行：

1. 从 `NIXARCHY_FLAKE` 取得配置目录。本仓库通过
   `programs.nixarchy.flake` 将它声明为 `/home/tetsuya/nixos-config`。
2. 检查目录存在且当前用户可写，因为下一步会改写 `flake.lock`。
3. 询问是否继续；回答 `y` 后执行：

   ```bash
   nix flake update --flake /home/tetsuya/nixos-config
   ```

4. 更新成功后执行：

   ```bash
   sudo nixos-rebuild switch --flake /home/tetsuya/nixos-config
   ```

   未写 `#主机名` 时，`nixos-rebuild` 按 hostname `hx90` 选择
   `nixosConfigurations.hx90`；显式手动操作时仍推荐写 `#hx90`，更容易审计。
5. 构建成功后创建并激活新的 NixOS generation。旧 generation 仍保留在启动
   菜单，可用于回滚。

它不会运行 pacman、AUR 或 Omarchy 的 Arch migration，也不会创建 Snapper
快照；NixOS generation 本身承担系统回滚能力。

## 会更新哪些内容

`nix flake update` 检查 `flake.nix` 可达的全部输入，并把找到的新 revision 写入
`flake.lock`。本仓库的主要输入是：

| 输入 | 更新影响 |
|---|---|
| `nixpkgs` | NixOS 基础系统、内核及声明在模块里的软件包版本 |
| `nixarchy` | NixOS/Home Manager 集成、NixOS 专用 Omarchy 命令和模块行为 |
| `omarchy` | 经 Nixarchy 打包的 Omarchy Shell、命令、默认配置和主题资源 |
| `home-manager` | 用户级声明式配置模块及其激活逻辑 |
| 传递输入 | Hyprland、Aquamarine、xdg-desktop-portal-hyprland、Zen Browser 等依赖 |

输入使用 `follows` 时会共享同一个 nixpkgs；锁文件中同名带后缀的节点是不同依赖
图节点，不应手工编辑。某次更新不一定改变所有节点：远端 revision 没有变化、被
固定到 tag，或者跟随其他输入时，锁文件会保持不变。

更新后的 rebuild 会重新求值整个系统，但 Nix 只构建或下载发生变化的
derivation；未变化的内容直接复用 `/nix/store`。

### 为什么只改一个锁节点也可能下载很多包

锁文件的变更行数不等于软件包变更数量。`nixpkgs` 位于依赖图根部，它的一个
revision 决定内核、glibc、systemd、Firefox、桌面库和绝大多数系统包。因此即使
`git diff flake.lock` 只显示 `nixpkgs` 前移，也可能产生数百个新 derivation。

构建输出中的 `copying path ... from https://cache.nixos.org` 表示下载官方二进制
缓存，不是全部在本机编译。下载完成的 store path 是不可变缓存；中止构建后仍可在
下次构建中复用。只有 `nixos-rebuild switch` 成功后，新闭包才成为当前系统。

## 不会更新哪些内容

- `~/chezmoi`、`~/dotfiles` 及其 Git 子模块；它们有各自的更新与提交流程。
- 浏览器资料、数据库、容器卷、keyring、Rime 用户数据等运行时数据。
- 不在 NixOS/Home Manager 声明中的手动安装软件或用户级包管理器内容。
- `system.stateVersion`；它是兼容性基线，不应随更新提高。
- NixOS 大版本分支。本仓库固定在 `nixos-26.05`，普通更新只在该分支内前移。

## 更新前后的推荐检查

更新前保证工作区干净，避免无法区分配置修改和锁文件更新：

```bash
cd ~/nixos-config
git status --short
```

如果希望先看规模而不直接切换，不使用一体化的 `omarchy update`，改为手动分步：

```bash
cd ~/nixos-config
nix flake update
git diff -- flake.lock
nixos-rebuild build --flake .#hx90
```

`build` 会显示计划构建/下载的 derivation，但不会激活系统。规模不合适时可以
`Ctrl-C` 停止，再决定保留还是恢复 `flake.lock`；确认构建成功后才运行：

```bash
sudo nixos-rebuild switch --flake .#hx90
```

更新后检查究竟有哪些输入变化：

```bash
git diff -- flake.lock
nix flake metadata
nix flake check --no-build
nixos-rebuild build --flake .#hx90
```

确认桌面、网络、音频、输入法和关键程序正常后提交锁文件：

```bash
git add flake.lock
git commit -m "chore: update NixOS flake inputs"
git push origin main
```

如果 rebuild 失败，`flake.lock` 仍可能已经被改写；应先检查失败原因或恢复锁文件，
不要把失败的更新直接提交。

## 只更新一个输入

需要缩小变更范围时，可只更新指定输入：

```bash
cd ~/nixos-config
nix flake update nixarchy
# 或：nix flake update nixpkgs
nix flake check --no-build
nixos-rebuild build --flake .#hx90
sudo nixos-rebuild switch --flake .#hx90
```

只更新 Nixarchy 也可能连带更新它未 `follows` 的传递输入。始终以
`git diff -- flake.lock` 为准。

## 回滚的两个层次

系统激活出问题时，回到上一 generation：

```bash
sudo nixos-rebuild switch --rollback
```

无法进入桌面时，可在 systemd-boot 启动菜单选择上一代。generation 回滚只改变
当前运行系统，不会自动恢复 Git 工作树中的 `flake.lock`。若确认本次输入更新不应
保留，再在仓库中恢复锁文件，然后重新构建：

```bash
git diff -- flake.lock
git restore flake.lock       # 仅在明确要丢弃未提交更新时使用
nixos-rebuild build --flake .#hx90
sudo nixos-rebuild switch --flake .#hx90
```

如果锁文件已经提交，优先用 `git revert <commit>` 留下可审计记录，而不是重写
历史。系统 generation 不会回滚用户目录运行时数据、浏览器资料、keyring 或容器卷。

## 常见路径问题

若出现：

```text
/etc/nixos is not writable by tetsuya
```

先检查：

```bash
echo "$NIXARCHY_FLAKE"
```

正确值是 `/home/tetsuya/nixos-config`。刚执行过 `nixos-rebuild switch` 的旧终端
可能仍继承旧环境，可临时运行：

```bash
NIXARCHY_FLAKE="$HOME/nixos-config" omarchy update
```

完整注销并重新登录后会话会读取新值。不要把 `/etc/nixos` 改为用户所有；它不是
本机实际使用的 flake 仓库。
