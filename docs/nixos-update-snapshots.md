# NixOS 更新前自动快照方案

本文记录 HX90 的自动更新保护方案。目标是在每次正式更新前，自动保存系统、
用户目录和 NixOS generation 的对应关系；出现问题时，可以先查看记录，再选择
回滚系统配置、恢复 Btrfs 快照，或两者一起处理。

本文记录已经实现的自动化流程以及恢复边界。恢复 `/` 和 `/home` 仍然不会自动执行，
需要根据记录人工确认。

## 目标

以后正式更新统一使用：

```bash
nixos-update
```

它完成以下工作：

```text
检查当前系统和仓库状态
        ↓
记录当前 NixOS generation、flake revision 和时间
        ↓
创建 / 的 Btrfs/Snapper 快照
创建 /home 的 Btrfs/Snapper 快照
        ↓
更新 Nix flake 输入
更新 Omarchy git 插件
        ↓
构建 NixOS 配置
        ↓
切换到新的 NixOS generation
        ↓
记录成功、失败或中断状态
        ↓
按 Snapper 数量策略清理过期快照
```

如果更新失败，快照记录仍然应该保留，方便定位和恢复。

## 当前机器已确认的事实

HX90 的布局是：

```text
/dev/nvme0n1p2  Btrfs
├── /            根文件系统（顶层 Btrfs volume）
├── /home        独立 Btrfs 子卷
└── /nix         独立 Btrfs 子卷

/dev/nvme0n1p3  独立 swap 分区
```

当前已有：

- NixOS generation，可使用 `nixos-rebuild switch --rollback` 回滚系统配置；
- `/`、`/home` 和 `/nix` 的 Btrfs 子卷；
- zram + 磁盘 swap；
- `btrfs-progs`；
- Nixarchy/Omarchy 的 NixOS 更新入口。

当前已实现：

- Snapper 的 `root` 和 `home` 配置；
- `nixos-update` 自动更新前快照；
- `/var/lib/nixos-update/history/` 更新记录；
- `nixos-update list` 和 `nixos-update show <transaction-id>` 查看命令。

恢复命令仍未自动化，避免误覆盖故障发生后新产生的文件。

## 三种回滚机制的职责

### NixOS generation

```bash
nixos-rebuild list-generations
sudo nixos-rebuild switch --rollback
```

负责回滚：

- NixOS 配置；
- 系统软件包；
- 内核；
- systemd system service；
- NixOS 生成的 `/etc` 内容。

不负责回滚：

- `/home` 中普通文件；
- 浏览器数据；
- SSH key；
- 数据库和容器卷；
- 不属于 NixOS/Home Manager 的运行时状态。

### `/` 的 Btrfs/Snapper 快照

负责保存根文件系统某一时刻的状态，包括非 Nix 生成的系统文件和运行时数据。

它不能替代 NixOS generation。两者需要配对记录。

### `/home` 的 Btrfs/Snapper 快照

负责保存用户目录，包括：

- chezmoi 配置和源仓库；
- 浏览器数据；
- SSH 配置；
- 用户文档；
- 用户级 systemd 状态；
- 不由 Home Manager 管理的用户文件。

`/nix` 通常不纳入更新前快照：Nix store 是不可变内容寻址存储，旧 generation
需要的 store path 会继续保留，直到执行垃圾回收。是否备份 `/nix` 是独立的备份
策略，不放入每次更新前快照。

## Snapper 配置

系统已声明两个 Snapper 配置：

```text
root → /
home → /home
```

两个快照会使用同一个更新事务 ID，例如：

```text
update-2026-09-05T153000-generation-6
```

这样可以在记录中把两个快照配成一组：

```text
transaction = update-2026-09-05T153000-generation-6
root_snapshot = 42
home_snapshot = 17
generation_before = 6
```

快照默认使用只读模式或等价的保护策略，防止普通应用意外修改历史快照。

## `nixos-update` 行为

### 完整执行顺序

默认执行 `nixos-update` 时，实际顺序如下：

1. 查询 Nixarchy 最新正式 release，并和 `flake.nix` 当前版本比较；
2. 解析 `~/nixos-config` 和当前主机名，例如 `hx90`；
3. 检查 `flake.nix`、Snapper、Omarchy 和 `nixos-rebuild` 是否可用；
4. 检查配置仓库是否干净；有未提交改动时默认停止；
5. 使用 `systemd-inhibit` 锁住 `sleep` 和 `idle`，防止更新期间休眠；
6. 创建更新事务记录；
7. 创建 `/` 的 root 快照；
8. 创建 `/home` 的 home 快照；
9. 如发现新 Nixarchy release，在快照之后更新 `flake.nix` 的版本引用；
10. 执行 `omarchy plugin update --yes`；
11. 执行 `nix flake update --flake ~/nixos-config`；
12. 执行 `nixos-rebuild build --flake ~/nixos-config#hx90`；
13. 构建成功后执行 `sudo nixos-rebuild switch --flake ~/nixos-config#hx90`；
14. 将成功、失败、generation 和快照编号写入事务记录。

构建失败时不会切换到新系统，已创建的快照和失败记录会保留。该命令不会自动
恢复快照，也不会自动回滚 NixOS generation。

单独检查 Nixarchy release，不修改仓库或系统：

```bash
nixos-update check
```

正式执行 `nixos-update` 时，如果发现较新的 release，会在确认提示中显示旧版本
和新版本；确认后才修改 `flake.nix`。如果使用 `--yes`，则自动接受这个版本升级。

### 更新前检查

命令启动后先检查：

1. 当前是否是 NixOS；
2. 主机名是否能匹配 flake 配置；
3. `/` 和 `/home` 是否为支持快照的 Btrfs 子卷；
4. Snapper 配置是否存在；
5. `~/nixos-config` 是否有未提交改动；
6. 是否已经有另一个更新任务运行；
7. 当前磁盘剩余空间是否足够创建快照元数据；
8. 当前用户是否有可用的 sudo 权限。

发现配置仓库有未提交改动时，默认应停止，而不是把不清楚的状态标记为可恢复
基线。需要强制更新时，应提供明确的 `--allow-dirty` 选项并记录原因。

### 快照和元数据

快照前记录：

```text
主机名
开始时间
当前 NixOS generation
当前运行 kernel
flake 当前 Git revision
flake.lock 的状态
root 快照编号
home 快照编号
```

记录位置：

```text
/var/lib/nixos-update/history/
```

记录由 root 创建和维护，每个事务一份文本文件，方便 SSH 查询：

```bash
nixos-update list
nixos-update show <transaction-id>
journalctl -t nixos-update
```

### 更新 Flake

快照创建成功后，命令才执行：

```bash
nix flake update --flake ~/nixos-config
```

之后执行：

```bash
nixos-rebuild build --flake ~/nixos-config#hx90
sudo nixos-rebuild switch --flake ~/nixos-config#hx90
```

如果构建失败，应该：

- 保留快照；
- 记录失败日志；
- 不切换系统；
- 不自动恢复 `/` 或 `/home`。

### Nixarchy 是如何更新的

本仓库的 Nixarchy 不是通过 Omarchy 插件 checkout 更新的，而是 flake input：

```nix
nixarchy.url = "github:olafkfreund/nixarchy/v4.0.1-1";
```

它在系统层和 Home Manager 层分别接入：

```nix
inputs.nixarchy.nixosModules.nixarchy
inputs.nixarchy.homeManagerModules.nixarchy
```

Nixarchy 提供的包、NixOS 模块、Home Manager 模块和 `omarchy` 命令，都会从这个
flake input 构建。锁定的实际 commit 保存在 `flake.lock` 的 `nixarchy` 节点中。

因此执行：

```bash
nix flake update --flake ~/nixos-config
```

时，Nix 会按照 `flake.nix` 中的 URL 尝试更新 Nixarchy，并把解析到的 commit 和
hash 写入 `flake.lock`。如果 URL 固定在某个 release，结果仍然会停留在这个
release；随后 `nixos-rebuild build` 和 `switch` 才会让锁定的 Nixarchy 版本进入
当前系统。

### Nixarchy 的 release/tag 与本机更新

你看到的：

```text
v4.0.2-4
```

是 Nixarchy 发布的一个 release/tag，可以理解为 Nixarchy 的一个可追踪版本。它
不是我们这台机器自动订阅的“最新版本”指针。当前本仓库明确固定的是：

```nix
nixarchy.url = "github:olafkfreund/nixarchy/v4.0.1-1";
```

因此，当前执行 `nixos-update` 时，`nix flake update` 会更新其他允许更新的
flake input，但不会自动把 `v4.0.1-1` 改成 `v4.0.2-4`。这也是你上一次更新日志
里只看到 `nixpkgs` 变化、没有看到 `nixarchy` 变化的原因。

升级到 `v4.0.2-4` 需要先把 `flake.nix` 的版本引用改成：

```nix
nixarchy.url = "github:olafkfreund/nixarchy/v4.0.2-4";
```

然后再执行：

```bash
nixos-update
```

它会重新锁定 Nixarchy 的 commit，构建新版本，并在构建成功后切换系统。更精确地
只更新这个 input，也可以使用：

```bash
nix flake lock --update-input nixarchy
```

但如果 `flake.nix` 仍然指向旧的 `v4.0.1-1`，这个命令也不会跨 release 自动跳到
`v4.0.2-4`。

固定 release 的优点是可复现和可回滚：以后任何时候都能明确知道系统使用哪个
Nixarchy 版本。升级 release 属于一次需要检查、构建和测试的依赖升级，而不是每次
日常更新都无条件追踪上游最新代码。

#### 当前 `v4.0.2-4` 的兼容说明

本机升级到 `v4.0.2-4` 时，发现它依赖的
`hyprland-preview-share-picker` 尚未进入当前锁定的 NixOS 26.05 nixpkgs；同时该
版本的 Omarchy 打包检查中有一段 Python 缩进问题。为保留 NixOS 26.05 的稳定
nixpkgs 锁定，本仓库在 `modules/desktop.nix` 和 Home Manager 用户模块中提供了
本地兼容 overlay/package，并修正生成的安装阶段缩进。该兼容层不改变 Omarchy
功能，待上游和 nixpkgs 的组合不再需要时可以移除。

这里有三个容易混淆的更新动作：

```text
nix flake update
└── 按 flake.nix 的引用更新 Nixarchy 及其他 flake inputs

nixos-rebuild switch
└── 让新的 Nixarchy 包、模块和配置进入系统

omarchy plugin update
└── 更新用户目录中的 Omarchy 插件 git checkout
```

也就是说，`nixos-update` 通过两个独立步骤同时处理 Nixarchy 和 Omarchy 插件：
先执行 `omarchy plugin update --yes`，再执行 `nix flake update`，最后构建并切换
NixOS。它不会更新 chezmoi 或 `dotfiles`。

更新完成后，如果 `flake.lock` 发生变化，应检查并提交：

```bash
cd ~/nixos-config
git diff -- flake.lock
git add flake.lock
git commit -m "chore: update flake inputs"
git push
```

### Omarchy 插件更新

当前 Omarchy 4.0.1 提供：

```bash
omarchy plugin update [id] [--yes]
```

不带插件 ID 时，更新所有 git-managed 插件：

```bash
omarchy plugin update --yes
```

这一步已纳入 `nixos-update`。插件更新会修改用户目录，所以必须放在 `/home`
快照创建之后。插件自身如果遇到本地改动或验证失败，应保留失败状态并停止后续
系统切换，不能静默覆盖用户修改。

当前 `~/.config/omarchy/plugins.list` 由 chezmoi 管理，但插件 checkout 的更新
动作由 Omarchy 命令负责。两者职责不同：

```text
chezmoi
└── 记录插件清单和启用关系

omarchy plugin update
└── 更新已安装插件的 git checkout
```

### 防止自动睡眠

`nixos-update` 会使用 `systemd-inhibit` 锁住 `sleep` 和 `idle`，防止 SSH 发起的
长时间构建被桌面电源策略中断。HX90 平时的空闲自动睡眠也已禁用。

## 为什么不拦截所有 `nixos-rebuild`

NixOS 没有一个可以安全拦截所有任意 `nixos-rebuild switch` 调用的统一 pre-hook。
因此自动快照只对以下入口保证：

```bash
nixos-update
```

直接执行：

```bash
sudo nixos-rebuild switch --flake .#hx90
```

会绕过更新前快照流程。该命令仍可用于紧急修复、回滚或开发调试，但正式更新应
统一使用 `nixos-update`。

同理，`omarchy update` 仍可能直接更新 flake 并执行 NixOS switch，会绕过快照流程。
正式更新应使用 `nixos-update`；本实现不修改 `/usr/share/omarchy`，并在 Nixarchy
菜单中提供了 `NixOS Update (Snapshot)` 入口。

## 恢复流程设计

恢复不是默认自动执行的，因为恢复 `/` 或 `/home` 可能覆盖用户在故障后的新文件。
当前实现提供查看记录和快照的命令；实际恢复仍按本文的离线流程人工执行。

### 先判断问题类型

```text
桌面、内核、systemd、Nix 包异常
→ 先尝试 NixOS generation 回滚

用户文件、浏览器数据、配置文件异常
→ 根据事务记录查看 /home 快照

系统文件和用户目录都需要回到更新前
→ 回滚 generation，并从同一个事务 ID 恢复 root + home 快照
```

### 查看记录

```bash
nixos-update list
nixos-update show <transaction-id>
sudo snapper -c root list
sudo snapper -c home list
```

本次更新的事务记录示例：

```bash
nixos-update show update-20260905T151243-generation-8
```

记录中的 `root_snapshot`、`home_snapshot` 和 `generation_before` 是一组，
恢复时应优先使用同一个事务中的编号，不要只凭快照编号猜测对应关系。

### 查看快照内容

Snapper 使用 `0` 表示当前正在使用的文件系统。比较更新前快照 `1` 和当前状态：

```bash
sudo snapper -c root status 1..0
sudo snapper -c root diff 1..0

sudo snapper -c home status 1..0
sudo snapper -c home diff 1..0
```

`status` 只列出新增、删除和修改的路径，`diff` 会显示文件内容差异。快照也可以
临时挂载后以普通文件的方式查看：

```bash
sudo snapper -c home mount 1
findmnt -t btrfs | grep snapper
sudo snapper -c home umount 1
```

### NixOS generation 回滚

```bash
sudo nixos-rebuild list-generations
sudo nixos-rebuild switch --rollback
```

无法进入桌面时，从 systemd-boot 选择旧 generation。

### Btrfs 快照恢复

当前提供查看命令和单文件恢复命令；恢复整个 `/` 和 `/home` 时不自动覆盖当前文件。

如果只是误删或误改了一个用户文件，可以先查看差异，再只恢复指定路径：

```bash
sudo snapper -c home undochange 1..0 -- /home/tetsuya/.config/example.conf
```

也可以指定一个目录，但这会覆盖目录下对应的当前文件，执行前应确认路径范围：

```bash
sudo snapper -c home undochange 1..0 -- /home/tetsuya/.config/some-directory
```

`undochange` 会直接修改当前文件系统，不能当作只读查看命令。重要文件应先复制
一份到其他位置。

推荐从 NixOS 安装介质或另一套可启动系统执行恢复，在离线状态下：

1. 确认事务 ID；
2. 确认 root 和 home 快照编号属于同一事务；
3. 备份当前需要保留的新文件；
4. 恢复 `/`；
5. 恢复 `/home`；
6. 重启并选择对应的 NixOS generation；
7. 检查 SSH、网络、桌面和用户数据。

不要在尚未确认方案时直接执行：

```bash
sudo snapper -c root rollback 1
```

`rollback` 会创建新的读写快照并改变 Btrfs 默认启动子卷。它只处理对应的 Snapper
配置，不能自动同时恢复 `/home`，因此不等价于“root + home 一键恢复”。完整恢复
需要先备份故障发生后新增的文件，再分别处理 root 和 home，并选择匹配的旧 NixOS
generation 启动。

## 保留和清理策略

自动快照必须自动清理，否则会持续占用 Btrfs 空间。当前策略为：

```text
最近 10 次更新事务：保留 root + home
最近 5 次重要事务：长期保留
普通快照超过 30 天：自动清理
用户手动标记的重要快照：不自动清理
```

当前 root 和 home 使用各自的 Snapper 数量清理策略。事务记录仍然会保留两者的
对应关系，但当前清理器不保证两个配置严格成对删除；如果某个事务必须长期保留，
应同时把 root 和 home 快照标记为重要，或暂时不要运行清理。后续如有需要，再增加
按事务 ID 成对清理的辅助逻辑。

快照只保护同一块磁盘上的快速回滚，不防止硬盘损坏。重要数据仍需使用外部磁盘、
NAS、`btrfs send/receive`、restic 或 borg 做异地/离线备份。

## 实施状态与后续

以下基础功能已经实施并验证：

1. 安装并声明 Snapper；
2. 建立 `root` 和 `home` 配置；
3. 实现 `nixos-update list/show`；
4. 接入 flake 更新、插件更新、构建和 switch；
5. 加入快照清理策略。

仍待后续验证或实现：

1. 从 Live 环境实际演练 `/` 和 `/home` 恢复；
2. 根据演练结果决定是否提供恢复辅助命令；
3. 评估按事务 ID 成对清理 root/home 快照的辅助逻辑。

在恢复流程经过实际演练前，不会把自动恢复加入更新命令。
