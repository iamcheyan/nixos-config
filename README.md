# Tetsuya 的多设备 NixOS Flake 配置

用一份 flake 管理多台 NixOS 机器：公共配置抽成 `modules/`，每台机器只保留
自己的硬件扫描文件和少量主机差异项。换机器时只需新增一个 `hosts/<名字>/`
目录并在 `flake.nix` 里注册一行。

本仓库只负责 **NixOS 系统层**：系统包和服务、硬件、内核、启动、用户组以及
Nixarchy 的系统接线。用户级私人编排由 `~/chezmoi` 管理，可公开复用的通用
配置由 `~/dotfiles` 管理；详细边界见 `AGENTS.md`。

## 目录结构

```
nixos-config/
├── flake.nix                  # 入口：注册所有主机，锁定 nixpkgs 版本
├── flake.lock                 # nixpkgs 的精确版本锁定（换机后照常使用）
├── modules/                   # 所有机器共享的配置模块
│   ├── core.nix               # 基础系统：引导、内核、网络、 locale、输入法、zram……
│   ├── desktop.nix            # 桌面：SDDM + Hyprland、PipeWire、字体……
│   ├── home-manager/           # NixOS 专属的用户级 Home Manager 配置
│   └── zsh.nix                # 全局 Zsh
└── hosts/                     # 每台机器一个目录
    ├── aarch64/               # ARM64 虚拟机
    └── nixos-hx90/             # HX90 工作站
```

## 四台主机现状

| 主机 | flake 名 | 状态 | 说明 |
|------|----------|------|------|
| ARM64 虚拟机 | `aarch64` | 可用 | QEMU `aarch64-linux`，GNOME、PipeWire、SPICE |
| HX90 工作站 | `hx90` | 可用 | x86_64，休眠和桌面环境 |

HX90 的 `networking.hostName` 与 flake 输出名统一为 `hx90`，因此 Nixarchy 的
`omarchy update` 即使不附加 `#hx90` 也能选中正确配置。

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
- **键盘映射**：keyd 服务由独立的 `modules/keyd.nix` 公共业务模块声明，所有主机
  使用同一份 MINILA-R 配置；详见 [`docs/keyd.md`](docs/keyd.md)。
- **zram**：zstd 压缩、占内存 50%、优先级 100（高于磁盘 swap），配
  `vm.swappiness=180`。解决 14G 内存机器冷页换出到 NVMe 后切窗口卡半秒的问题。
- **基础包**：git、curl、jq、ripgrep、python3、fnm 等。

### modules/desktop.nix — 桌面环境
- **登录**：SDDM（Wayland 模式），Breeze 主题。主题依赖 KDE QML 模块，所以
  同时启用了 Plasma 6——这台机器上 Plasma 也作为备用会话存在。
- **默认会话**：使用 Nixarchy 提供的 Wayland 桌面会话。
- **Omarchy 更新入口**：`programs.nixarchy.flake` 指向用户拥有的
  `~/nixos-config`。状态栏与 `omarchy update` 更新本仓库的 `flake.lock` 后执行
  rebuild，不使用 root 拥有的 `/etc/nixos`。
- **图形栈**：Hyprland（含 XWayland）、xdg portal、polkit、gnome-keyring、
  power-profiles-daemon。
- **音频**：PipeWire（兼容 ALSA / 32 位 / PulseAudio 客户端）。
- **蓝牙**：blueman。
- **字体**：Noto CJK、JetBrains Mono Nerd Font、emoji、图标字体。
- **桌面工具**：quickshell（任务栏）、walker（启动器）、grim/slurp/swappy
  （截图）、foot/kitty（终端）、pamixer、brightnessctl、nautilus 等。
- **两处针对性修补**：
  - `QML2_IMPORT_PATH` 指向 kirigami/qt5compat 的 `.unwrapped`，确保
    polkit 图形代理正常工作。
  - `amdgpu-dpm` 服务：AC 供电时把 Cezanne iGPU 显存频率锁 `high`、电池时
    `auto`（auto 会在 4K@scale2 合成时每秒在 400/1750MHz 之间跳，表现为掉帧），
    并用 udev 规则在电源插拔时重跑。

### modules/zsh.nix
全局启用 Zsh 和补全。用户 shell 在各主机 configuration.nix 里指定。

### HX90 主机特有的部分
- **休眠**：`boot.resumeDevice` 指向 NVMe swap 分区。因为 zram 里的页在内存
  里，直接休眠会 ENOMEM 失败，所以装了 `systemd/system-sleep/10-hibernate-zram.sh`：
  休眠前把 zram swap 整个 swapoff 到磁盘、把 image_size 调到最小；唤醒后
  重置 zram0 并重启 zram-setup 服务恢复优先级配置。
- **logind**：电源键/（若存在的）盖子动作按主机配置处理，但禁用"无人值守空闲挂起"，
  以保证 SSH 任务不会因空闲而中断。
- **snapper**：`/` 和 `/home` 各一套自动快照（小时/天/周/月保留策略），
  用于本地回滚。注释里写明：这不是加密 NAS 备份的替代品。
- **Docker + Windows VM 工具链**：docker、docker-compose、freerdp（RDP）、
  cifs-utils（SMB）、restic、btrfs-progs。

## 日常操作

### 重装后的 SSH 接管

新系统启动后，如果 Agent 要通过 SSH 接管，可以先把本仓库复制到新系统，并确认
安装时已经为用户设置密码，然后执行：

```bash
cd ~/nixos-config
./scripts/enable-ssh-bootstrap.sh
```

脚本会临时叠加 SSH、22 端口防火墙规则和密码登录配置，执行一次
`nixos-rebuild switch`，最后打印本机 IP。它不会修改仓库或 `/etc/nixos/configuration.nix`。
SSH 使用用户密码登录，禁止 root 直接登录；接管完成后建议改回密钥登录或关闭 SSH。

```bash
# 应用配置（在本机上，<name> 换成当前机器的 flake 名）
sudo nixos-rebuild switch --flake ~/nixos-config#hx90      # HX90
sudo nixos-rebuild switch --flake ~/nixos-config#aarch64   # ARM64 虚拟机

# 更新 nixpkgs 锁定（谨慎：当前刻意钉在 nixos-26.05 迁移基线）
nix flake update
sudo nixos-rebuild switch --flake ~/nixos-config#<name>

# 测试构建（不切换）
nixos-rebuild build --flake ~/nixos-config#<name>

# 回滚
sudo nixos-rebuild switch --rollback
```

在 NixOS 上，`omarchy update` 不是 Arch/pacman 更新。Nixarchy 会使用
`NIXARCHY_FLAKE=~/nixos-config` 执行 `nix flake update`，然后运行
`nixos-rebuild switch`。它更新 NixOS/Nixarchy/Omarchy/Home Manager 等 flake
输入，但不会更新 chezmoi、dotfiles 或用户运行时数据。详细范围、验证和双层回滚
方法见 [`docs/nixarchy/update-and-rollback.md`](docs/nixarchy/update-and-rollback.md)。

想系统学习 NixOS 的设计取舍和本仓库的实践方式，可从
[`docs/nixos-learning-notes.md`](docs/nixos-learning-notes.md) 开始。

## NixOS 与 chezmoi 的用户配置边界

本仓库通过 Home Manager 管理 NixOS 专属的用户配置，入口是
[`modules/home-manager/nixos-user.nix`](modules/home-manager/nixos-user.nix)。这里适合放：

- 依赖 Nix store 软件包的用户配置、用户级 systemd service；
- Nixarchy/Omarchy 的 NixOS 接线；
- 只在 NixOS 上使用的用户环境变量、GUI 默认值和配置文件。

跨发行版或跨平台的用户偏好继续由 `~/chezmoi` 管理，例如 Hyprland、Fcitx5、终端、
tmux、Voxtype 和通用脚本。一个具体文件只能由一个系统管理：迁移到 Home Manager
后必须从 chezmoi 删除对应文件，反之亦然。NixOS 的用户配置通过
`sudo nixos-rebuild switch --flake ~/nixos-config#<主机名>` 生效；chezmoi 配置仍通过
`chezmoi apply` 生效。这样在 Fedora、Arch、Debian 或 macOS 上使用 chezmoi 时，
不会依赖 NixOS 的模块或 Nix store 路径。

## 仓库地图

换机时“配置回来”不等于只部署本仓库。主要配置由以下三个仓库组成：

| 仓库 | 地址 | 管什么 | 换机时的动作 |
|---|---|---|---|
| **nixos-config**（本仓库） | `iamcheyan/nixos-config` | 系统层和桌面组件 | clone + 生成 hardware 文件 + 注册主机 + rebuild |
| **chezmoi**（PRIVATE） | `iamcheyan/chezmoi` | 用户级私人软件与自动化编排 | 认证 clone + `chezmoi apply` |
| **dotfiles**（PUBLIC） | `iamcheyan/dotfiles` | 通用 Zsh、Neovim 与公开 CLI 配置 | clone + `dotlink link` |

**不会自动回来的**（换机前自行处理）：

- `~/.ssh/`、`~/.gitconfig` —— chezmoi 刻意不管（密钥不入库）。新机器第一件事
  是手动迁移 SSH key（或先用 HTTPS + token 克隆），否则 `git@github.com:` 全部拉不动。
- 桌面运行时状态 —— 生成物，按需重新设置。
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
7. **重启后**：在 SDDM 中选择 Nixarchy 会话登录。

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

### HX90 台式机策略

HX90 是需要长期通过 SSH 运行任务的台式机，因此配置为：

- 空闲时不自动 suspend 或 hibernate：`services.logind.settings.Login.IdleAction = "ignore"`。
- 手动 suspend 和 hibernate 仍然可用；例如 `systemctl hibernate`。
- 禁用 hybrid sleep 与 suspend-then-hibernate，避免后台策略自行改变电源状态。
- hibernate 写入磁盘后使用 `HibernateMode = "shutdown"`。这台机器的固件在 ACPI S4
  阶段会因为 USB 控制器返回 `EBUSY` 导致恢复失败，所以采用快照后正常关机。
- 休眠目标是独立 NVMe swap 分区，不是 EXT4/Btrfs 文件系统里的 swapfile。当前 HX90
  的 swap UUID 是 `cfceef33-5044-4a72-8c01-c8d1f4444f00`，必须同时出现在
  `hardware-configuration.nix` 的 `swapDevices` 和 `configuration.nix` 的
  `boot.resumeDevice`。

这套台式机策略不应原样复制到笔记本：笔记本通常需要保留合盖动作，并可能需要
`suspend-then-hibernate`。复制时应按笔记本的电源管理需求单独设置 `logind`，并使用
笔记本自己的 swap UUID。

新机器要启用休眠的检查清单：

1. **装机时留出 ≥ 内存的 swap 分区**（HX90 使用约 68.4 GiB swap / 约 62 GiB RAM）。
2. `nixos-generate-config` 生成 hardware 文件后，从里面的 `swapDevices` 拿到
   swap 分区 UUID，填进该主机 `configuration.nix` 的 `boot.resumeDevice`。
3. 把 HX90 里 `environment.etc."systemd/system-sleep/10-hibernate-zram.sh"`
   那一整块复制过去——zram 在 `modules/core.nix` 是共享启用的，所以只要用
   zram 就需要这个钩子（钩子和 resumeDevice 同在 host 文件里，结构上保证同进退）。
4. **验证顺序**：`swapon --show` 确认两个 swap（zram0 优先级 100 + 磁盘分区 -1）
   → `nixos-rebuild build --flake .#主机名` → 真点一次休眠按钮走完整断电循环
   → 唤醒后确认会话还在、zram 优先级恢复 100。

电源面板只在内核支持 disk 休眠且存在非 zram 的磁盘 swap 分区时显示
Hibernate 按钮，没配 swap 的机器会自动隐藏。

## 注意事项 / 坑

- **hardware 文件绝不跨机器复制**。里面的磁盘 UUID、initrd 内核模块
  （`kvm-intel` vs `kvm-amd`）、CPU 微码（`intel` vs `amd`）都是机器专属。
- **`system.stateVersion` 不要动**。它只表示"当初安装时的 NixOS 版本"，
  升级它不会升级系统，反而可能触发一次性迁移逻辑。
- **nixpkgs 钉在 `nixos-26.05`**。这是刻意的迁移基线，新机器稳定运行之前
  不要顺手 `nix flake update`。
- **免密 sudo**：`tetsuya` 在所有机器上 `NOPASSWD: ALL`。多用户环境不适用，
  需要时改 `modules/core.nix`。
- **HX90 的空闲挂起被禁用**（logind `IdleAction=ignore`），因为它是需要保持 SSH
  在线的台式机；手动挂起/休眠仍可用，电源键和（若存在的）合盖动作仍按各自的
  `Handle*` 设置处理。

## 各主机 rebuild 速查

```bash
sudo nixos-rebuild switch --flake ~/nixos-config#hx90
sudo nixos-rebuild switch --flake ~/nixos-config#aarch64
```
