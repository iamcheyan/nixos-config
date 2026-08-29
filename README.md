# Tetsuya 的多设备 NixOS Flake 配置

用一份 flake 管理多台 NixOS 机器：公共配置抽成 `modules/`，每台机器只保留
自己的硬件扫描文件和少量主机差异项。换机器时只需新增一个 `hosts/<名字>/`
目录并在 `flake.nix` 里注册一行。

## 目录结构

```
nixos-config/
├── flake.nix                  # 入口：注册所有主机，锁定 nixpkgs 版本
├── flake.lock                 # nixpkgs 的精确版本锁定（换机后照常使用）
├── modules/                   # 所有机器共享的配置模块
│   ├── core.nix               # 基础系统：引导、内核、网络、 locale、输入法、zram……
│   ├── desktop.nix            # 桌面：SDDM + Hyprland(sumika-shell)、PipeWire、字体……
│   ├── keyd.nix               # 键盘重映射守护进程 keyd
│   └── zsh.nix                # 全局 Zsh
└── hosts/                     # 每台机器一个目录
    ├── laptop/                # 笔记本（Intel）
    ├── desktop/               # 台式机（占位，硬件文件需在本机生成）
    └── nixos-new/             # 新机器（AMD，带休眠 + snapper 快照）
```

## 四台主机现状

| 主机 | flake 名 | 状态 | 说明 |
|------|----------|------|------|
| 笔记本 | `laptop` | 可用 | Intel (kvm-intel)，btrfs 子卷 root/home/nix |
| 台式机 | `desktop` | **占位** | `hardware.nix` 是假的（`/dev/disk/by-label/nixos` ext4），上台式机前必须在本机重新生成 |
| 新机器 | `nixos-new` | 可用 | AMD (kvm-amd)，休眠、snapper 快照、Docker、Windows VM 工具链 |
| ARM64 虚拟机 | `nixos-aarch64` | 可用 | QEMU `aarch64-linux`，GNOME、PipeWire、SPICE；不加载旧 OMD/Sumika 桌面模块 |

每台主机的 `configuration.nix` 只包含：主机名、时区（Asia/Tokyo）、用户
`tetsuya`、以及该机特有的服务；其余全部 import 共享模块。

## 模块都在干什么

### modules/core.nix — 所有机器共用的底座
- **引导/内核**：systemd-boot + EFI，`linuxPackages_latest` 最新内核。
- **网络**：NetworkManager。
- **本地化**：默认 locale `zh_CN.UTF-8`，时间/货币等格式用 `ja_JP.UTF-8`。
- **输入法**：Fcitx5 + Rime（`fcitx5-rime`），走 Wayland text-input 协议
  （`waylandFrontend`），GTK 不设 `GTK_IM_MODULE`，Qt/SDL 仍走显式 IM module。
- **sudo**：`tetsuya` 免密码（单用户工作站）。
- **服务**：打印 (CUPS)、SSH、nix-ld（跑非 Nix 打包的二进制）、Firefox。
- **zram**：zstd 压缩、占内存 50%、优先级 100（高于磁盘 swap），配
  `vm.swappiness=180`。解决 14G 内存机器冷页换出到 NVMe 后切窗口卡半秒的问题。
- **基础包**：git、curl、jq、ripgrep、python3、fnm 等。

### modules/desktop.nix — 桌面环境
- **登录**：SDDM（Wayland 模式），Breeze 主题。主题依赖 KDE QML 模块，所以
  同时启用了 Plasma 6——这台机器上 Plasma 也作为备用会话存在。
- **默认会话 `sumika-shell`**：一个自定义 Wayland session 包，启动
  Hyprland 并加载 `~/development/OMD/hypr/hyprland.lua` 配置。
  ⚠️ **依赖 `~/development/OMD` 仓库存在**，否则该会话直接报错退出
  （可临时切 Plasma 会话登录）。
- **图形栈**：Hyprland（含 XWayland）、xdg portal、polkit、gnome-keyring、
  power-profiles-daemon。
- **音频**：PipeWire（兼容 ALSA / 32 位 / PulseAudio 客户端）。
- **蓝牙**：blueman。
- **字体**：Noto CJK、JetBrains Mono Nerd Font、emoji、图标字体。
- **桌面工具**：quickshell（任务栏）、walker（启动器）、grim/slurp/swappy
  （截图）、foot/kitty（终端）、pamixer、brightnessctl、nautilus 等。
- **两处针对性修补**：
  - `QML2_IMPORT_PATH` 指向 kirigami/qt5compat 的 `.unwrapped`——否则
    sumika-polkit 代理会崩溃循环、pkexec 弹窗全部失灵。
  - `amdgpu-dpm` 服务：AC 供电时把 Cezanne iGPU 显存频率锁 `high`、电池时
    `auto`（auto 会在 4K@scale2 合成时每秒在 400/1750MHz 之间跳，表现为掉帧），
    并用 udev 规则在电源插拔时重跑。

### modules/keyd.nix — 键盘重映射
keyd 守护进程。因为 NixOS 的 keyd 模块不会创建上游所需的 `keyd` 用户/组，
这里手动补上，并：
- 用 tmpfiles 创建可写的 `/etc/keyd` 目录（keyd 单元有
  `ProtectSystem=strict`，preStart 里 mkdir 会 EROFS），放入占位配置
  `omd.conf`。
- OMD 的 keyboard-remap 扩展会通过 pkexec 把真正的 `/etc/keyd/sumika.conf`
  写进去——所以这个目录必须是真的可写目录而非 Nix store 链接。
- 给 keyd 单元补 `CAP_SETGID/CAP_SETUID`（它启动时要自我降权）。

### modules/zsh.nix
全局启用 Zsh 和补全。用户 shell 在各主机 configuration.nix 里指定。

### nixos-new 主机特有的部分
- **休眠**：`boot.resumeDevice` 指向 NVMe swap 分区。因为 zram 里的页在内存
  里，直接休眠会 ENOMEM 失败，所以装了 `systemd/system-sleep/10-hibernate-zram.sh`：
  休眠前把 zram swap 整个 swapoff 到磁盘、把 image_size 调到最小；唤醒后
  重置 zram0 并重启 zram-setup 服务恢复优先级配置。
- **logind**：盖子/电源键挂起保留，但禁用"无人值守空闲挂起"——这台机器固件
  的 s2idle 唤醒可靠性还没验证过。
- **snapper**：`/` 和 `/home` 各一套自动快照（小时/天/周/月保留策略），
  用于本地回滚。注释里写明：这不是加密 NAS 备份的替代品。
- **Docker + Windows VM 工具链**：docker、docker-compose、freerdp（RDP）、
  cifs-utils（SMB）、restic、btrfs-progs。

## 日常操作

```bash
# 应用配置（在本机上，<name> 换成当前机器的 flake 名）
sudo nixos-rebuild switch --flake ~/nixos-config#laptop      # 笔记本
sudo nixos-rebuild switch --flake ~/nixos-config#nixos-new   # 新机器
sudo nixos-rebuild switch --flake ~/nixos-config#nixos-aarch64 # ARM64 虚拟机

# 更新 nixpkgs 锁定（谨慎：当前刻意钉在 nixos-26.05 迁移基线）
nix flake update
sudo nixos-rebuild switch --flake ~/nixos-config#<name>

# 测试构建（不切换）
nixos-rebuild build --flake ~/nixos-config#<name>

# 回滚
sudo nixos-rebuild switch --rollback
```

## 仓库地图：这台机器一共由四个仓库组成

换机时"配置回来"≠ 只部署本仓库。完整的机器 = 以下四件套：

| 仓库 | 地址 | 管什么 | 换机时的动作 |
|---|---|---|---|
| **nixos-config**（本仓库） | `iamcheyan/nixos-config` | 系统层：内核、驱动、SDDM、Hyprland 会话包、字体、keyd、zram、zsh | clone + 生成 hardware 文件 + 注册主机 + rebuild |
| **OMD** | `iamcheyan/oh-my-desktop` | 桌面 shell：Quickshell 栏、Hyprland lua、`sumika-*` 脚本、扩展宿主 | clone 后跑 `./Init.sh`（建 quickshell 软链、装 session） |
| **chezmoi** | `iamcheyan/chezmoi` | 用户层：`~/.config/sumika-shell/`、foot/kitty 终端、fcitx5、Firefox 等 dotfiles | clone 后 `chezmoi apply` |
| **sumika-shell-extensions** | `iamcheyan/sumika-shell-extensions` | 8 个扩展（voice、screenshot、input-method、keyboard-remap…） | clone 后按扩展文档逐个安装到 `~/.local/share/sumika-shell/extensions/` |

**不会自动回来的**（换机前自行处理）：

- `~/.ssh/`、`~/.gitconfig` —— chezmoi 刻意不管（密钥不入库）。新机器第一件事
  是手动迁移 SSH key（或先用 HTTPS + token 克隆），否则 `git@github.com:` 全部拉不动。
- 运行时状态（`~/.local/state/sumika-shell/`：当前主题/壁纸选择、keep-awake 等）
  —— 生成物，按需重选。
- 浏览器数据、keyring 密码、Docker 卷等机器本地数据 —— 与配置仓库无关。

## 换一台新机器怎么用

### 场景 A：全新安装 NixOS

1. **装系统**：用官方 ISO 正常安装（分区时参考现有机器的布局：btrfs，
   root/home/nix 三个子卷 + ESP + swap 分区，这样 hardware 文件结构一致，
   nix 子卷还能让 `/nix/store` 在重装后保留缓存）。
2. **把仓库弄到新机器上**（U 盘、SSH 或先装 git）：
   ```bash
   git clone <你的仓库地址> ~/nixos-config
   ```
3. **生成新主机的硬件文件**——这是唯一必须在本机生成的部分：
   ```bash
   # 已 chroot 进新系统时：
   nixos-generate-config --root /mnt
   # 新系统已能启动时（文件在 /etc/nixos/ 下）：
   cp /etc/nixos/hardware-configuration.nix ~/nixos-config/hosts/<新名字>/
   ```
4. **建主机目录**：复制一份现有的 `hosts/nixos-new/configuration.nix` 当模板，
   改三处：
   - `networking.hostName`
   - imports 里硬件文件名（`hardware-configuration.nix` vs `hardware.nix`）
   - 删掉新机器没有的功能（比如不是 AMD 核显就删 amdgpu 相关注释参考，
     不休眠就删 `boot.resumeDevice` 和 sleep 脚本；反过来笔记本要加）
5. **在 flake.nix 注册**，照抄现有条目：
   ```nix
   新名字 = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     modules = [ ./hosts/新名字/configuration.nix ];
   };
   ```
6. **首次构建并切换**：
   ```bash
   sudo nixos-rebuild switch --flake ~/nixos-config#新名字
   ```
7. **重启后**：登录界面默认进 `sumika-shell` 会话。前提是
   `~/development/OMD` 仓库已 clone 到位（session 脚本要求
   `~/development/OMD/hypr/hyprland.lua` 存在）。没到位之前在 SDDM 右下角
   切到 Plasma 会话用。

### 场景 B：把现有机器纳入这套配置管理

和场景 A 相同，只是第 3 步直接：
```bash
mkdir -p ~/nixos-config/hosts/旧机器名
cp /etc/nixos/hardware-configuration.nix ~/nixos-config/hosts/旧机器名/
```
然后按 4-6 步走。旧机器的 `system.stateVersion` 保持它**当初安装时**的
版本不要改（本仓库三台都是 `26.05`，因为都是 26.05 时代装的）。

## 休眠（Hibernate）跨机器的注意点

休眠是这套配置里最"机器绑定"的功能。**内存大小本身不是问题**——zram 按
百分比（50%）分配，钩子里的 `image_size` 恢复值是运行时从 `/proc/meminfo`
算的，没有任何写死的内存数值。真正的绑定点：

| 检查项 | 要求 | 不满足时会发生什么 |
|---|---|---|
| swap 分区大小 | ≳ 物理内存（swap ≥ RAM 是可靠规则） | 重负载时镜像写不下，写盘阶段失败、解冻弹回 |
| `boot.resumeDevice` UUID | 必须是**这台机器**的 swap 分区 UUID | 休眠能正常写入镜像，但开机恢复不了：直接全新启动、会话丢失（数据不坏，但等于白休眠） |
| zram 刷盘钩子 | 有 zram 就必须带 `10-hibernate-zram.sh` | zram 里的页在内存里，快照算不下会 ENOMEM 弹回（nixos-new 实测踩过） |
| Secure Boot lockdown | 关闭（或内核未进 lockdown） | lockdown 开启时内核直接禁止休眠，与本配置无关 |

新机器要启用休眠的检查清单：

1. **装机时留出 ≥ 内存的 swap 分区**（参考 nixos-new：16.5G swap / 14G RAM）。
2. `nixos-generate-config` 生成 hardware 文件后，从里面的 `swapDevices` 拿到
   swap 分区 UUID，填进该主机 `configuration.nix` 的 `boot.resumeDevice`。
3. 把 nixos-new 里 `environment.etc."systemd/system-sleep/10-hibernate-zram.sh"`
   那一整块复制过去——zram 在 `modules/core.nix` 是共享启用的，所以只要用
   zram 就需要这个钩子（钩子和 resumeDevice 同在 host 文件里，结构上保证同进退）。
4. **验证顺序**：`swapon --show` 确认两个 swap（zram0 优先级 100 + 磁盘分区 -1）
   → 真点一次休眠按钮走完整断电循环 → 唤醒后确认会话还在、zram 优先级恢复 100。

sumika-shell（OMD 仓库）侧不用配：电源面板和右键菜单只在"内核支持 disk 休眠
**且**存在非 zram 的磁盘 swap 分区"时才显示 Hibernate 按钮，没配 swap 的机器
按钮自动隐藏。

## 注意事项 / 坑

- **hardware 文件绝不跨机器复制**。里面的磁盘 UUID、initrd 内核模块
  （`kvm-intel` vs `kvm-amd`）、CPU 微码（`intel` vs `amd`）都是机器专属。
  `hosts/desktop/hardware.nix` 目前就是占位，上台式机前必须重新生成。
- **`system.stateVersion` 不要动**。它只表示"当初安装时的 NixOS 版本"，
  升级它不会升级系统，反而可能触发一次性迁移逻辑。
- **nixpkgs 钉在 `nixos-26.05`**。这是刻意的迁移基线，新机器稳定运行之前
  不要顺手 `nix flake update`。
- **sumika-shell 会话依赖 `~/development/OMD`**（Hyprland 配置、任务栏、
  keyboard-remap/keyd 扩展都来自那里）。新机器第一件事 clone 它。
- **keyd 的 `/etc/keyd`** 是 tmpfiles 建的真目录；OMD 扩展会往里写
  `sumika.conf`。手工清理时别删目录本身。
- **免密 sudo**：`tetsuya` 在所有机器上 `NOPASSWD: ALL`。多用户环境不适用，
  需要时改 `modules/core.nix`。
- **nixos-new 的空闲挂起被禁用**（logind `IdleAction=ignore`），因为该固件
  s2idle 唤醒未验证；盖子和电源键的挂起不受影响。验证稳定后可改回。

## 各主机 rebuild 速查

```bash
sudo nixos-rebuild switch --flake ~/nixos-config#laptop
sudo nixos-rebuild switch --flake ~/nixos-config#desktop
sudo nixos-rebuild switch --flake ~/nixos-config#nixos-new
```
