# HX90 上的虚拟机

本机把一块独立的 512 GB SSD 当虚拟机仓库，虚拟机本身由 libvirt 管理，
图形界面用 virt-manager。本文记录磁盘约定、已有虚拟机、以及踩过的坑。

- 磁盘：KODAK SSD X120 PRO 512GB（`/dev/sda`，SATA 序列号 `E503GH38400867`）
- 分区：单个 GPT 分区，ext4，标签 `VMSTORE`，UUID `674748a3-c6b1-4728-8bd0-45fb0da664f4`
- 挂载：`/mnt/VMSTORE`（`x-gvfs-show`，桌面和文件管理器可见）
- 开机自动挂载：`nofail` + `local-fs.target`

**不要整盘直通给某一台虚拟机。** 这块盘要放很多台 VM，直通会让第二个
虚拟机没有空间，也会让宿主机完全失去对盘的控制。虚拟机磁盘一律用
qcow2 镜像文件。

## 目录约定

```
/mnt/VMSTORE/
├── OS-Images/                安装 ISO，按平台分目录
│   ├── INDEX.md              文件名、大小、sha256 清单
│   ├── windows/
│   └── linux-handheld/
└── VMs/                      每台虚拟机一个目录
    ├── inua-lab/             Inua 的 Linux 测试机
    └── win98/                 Windows 98 外观的 Win10 IoT
```

## 磁盘保护

`/mnt/VMSTORE` 在运行中的机器上无法被普通用户卸载或弹出：

- udisks 的 `filesystem-unmount-others`、`filesystem-fstab`、
  `eject-media*`、`power-off-drive*` 对这块盘的序列号返回
  `polkit.Result.NO`（`hosts/hx90/configuration.nix` 的
  `security.polkit.extraConfig`）。
- root 仍然可以停挂载，用于维护和恢复。

这条规则按 `drive.serial` 匹配，而不是 `/dev/sda`：设备节点会随插拔顺序变化，
序列号不会。

## 已有的虚拟机

### inua-lab

Inua 自己的 Linux 测试机，由 Inua 的 VM 后端直接调用 QEMU 启动，不走 libvirt。
`/mnt/VMSTORE/VMs/inua-lab/disk.qcow2` 是它的系统盘，`vm.log` 是串口日志。

### win98

| | |
|---|---|
| 名称 | `win98` |
| 安装源 | `OS-Images/windows/ProjectMemphis.iso` |
| 实际系统 | Windows 10 IoT Enterprise LTSC 19044（`Edition ID: IoTEnterpriseS`） |
| 外观 | Windows 98 外壳 + Panther2K 文本安装器 |
| vCPU / 内存 | 2 / 8 GiB |
| 磁盘 | `/mnt/VMSTORE/libvirt/images/win98-fresh-verify.qcow2`，64 GiB qcow2 |
| 固件 | SeaBIOS |
| 显示 | virt-manager 控制台 / VNC `127.0.0.1:5900`（仅回环） |
| 管理 | libvirt 域 `win98`（`qemu:///system`） |
| 回退点 | 快照链 `win98-desktop-20261031` → `win98-working-desktop` → 基盘 |

**当前状态：** 客体能够启动到 Windows 98 风格桌面。RDP 暂未配置。

### win11-26h2

| | |
|---|---|
| 名称 | `win11-26h2` |
| 安装源 | `OS-Images/windows/Windows11_26H2_ja-jp_x64.iso` |
| 版本 | Windows 11 Pro ja-JP；原始安装介质标记为 26H2 |
| vCPU / 内存 | 2 / 8 GiB |
| 磁盘 | `/mnt/VMSTORE/libvirt/images/win11-26h2/win11-26h2.qcow2`，128 GiB qcow2 |
| 固件 / TPM | UEFI，libvirt emulator TPM 2.0 |
| 显示 | SPICE（仅监听 `127.0.0.1`） |
| 网络 | libvirt `default` NAT 网络，e1000e；DHCP 地址由租约查询 |
| 管理 | libvirt 域 `win11-26h2`（`qemu:///system`） |
| 用户 | `tetsuya` 本地管理员；安装后已进入 Windows 桌面 |
| 凭据 | `/home/tetsuya/.config/windows-rdp/win11-26h2-credentials`，权限 `0600` |
| RDP | 未验证可用；从宿主机连接 `192.168.122.234:3389` 超时，Windows 桌面控制台可用。 |
| 开机启动 | libvirt autostart 已启用 |
| 控制台 | `virt-viewer --connect qemu:///system --wait win11-26h2` |

Windows 已安装并进入桌面。RDP 端口检查与 `xfreerdp /auth-only` 连接测试均超时；
测试期间 DHCP 地址为 `192.168.122.234`。登录凭据已从安装应答盘复制到上面的
本地 `0600` 文件；应答 USB 的 XML 和启动脚本已删除。VMSTORE 中仍保留安装介质和
安装目录。应答 XML 中可能仍含明文密码，移动、备份或分享安装目录前应先清除该副本。

```bash
virsh -c qemu:///system domifaddr win11-26h2 --source lease
virt-viewer --connect qemu:///system --wait win11-26h2
```

## 打开 win98

应用菜单里的 **Windows 98**（`win98.desktop`）会先启动域，再用 virt-viewer
打开 GTK 图形控制台；也可以直接运行：

```bash
win98-console                       # 域未运行时会先启动
virt-viewer --connect qemu:///system --wait win98
```

virt-manager 里双击 `win98` 得到的是同一块 framebuffer，只是外面多一层管理界面。
当前使用的是有 Windows 98 外观的 Windows 10 IoT 系统；还没有配置 RDP。

## 为什么一开始没用 libvirt

这台机器最初用一次性 `systemd-run` 单元启动 QEMU。问题是在当前会话里
用 bun 运行的 agent 进程会在工具调用结束时清理自己的进程组，QEMU 因为在
同一个进程组里，每次都会在 1–3 分钟内被 SIGKILL。用 bpftrace 追踪
`signal_generate` 抓到的凶手是 `tokio-rt-worker`（bun/omp 的线程）。

当时的绕法是让 QEMU 跑在 root 的独立 systemd 单元里（`system.slice`）。
现在换成 libvirt，QEMU 同样由系统级 systemd 单元拉起，问题不复存在。

如果以后手工跑一台 QEMU，记得离开当前 shell 的进程组，或者在
`system.slice` 里起，否则会被同样的方式带走。

## 用 virt-manager 管理

`programs.virt-manager.enable` 装好 UI，默认自动连接 `qemu:///system`。
libvirtd 由 `virtualisation.libvirtd.enable` 启用，`tetsuya` 在 `libvirtd`
组里，NixOS 模块已经配好 `org.libvirt.unix.manage` 的 polkit 规则，
所以日常启停不需要 sudo。

```bash
virt-manager                        # 图形界面
virsh -c qemu:///system list --all  # 命令行
virsh -c qemu:///system start win98
virsh -c qemu:///system shutdown win98
virsh -c qemu:///system screenshot win98 /tmp/win98.ppm
```

`virsh` 不带 `-c qemu:///system` 时默认连 `qemu:///session`，那是另一个
（空的）实例，会看不到这里的虚拟机。

### 存储池 vmstore

默认池 `/var/lib/libvirt/images` 在 btrfs 根分区上，虚拟机镜像不该放那里。
已经定义好一个 dir 池指向 VMSTORE，开机自动启动：

```bash
virsh -c qemu:///system pool-info vmstore
# Capacity: 468.38 GiB / Available: 440.37 GiB
```

新建虚拟机时在 virt-manager 的 storage 页选 `vmstore`，镜像就落在
`/mnt/VMSTORE/libvirt/images/`。

### 域定义要点

域定义由 libvirt 管理，Windows 11 文件位于
`/mnt/VMSTORE/libvirt/images/win11-26h2/`；修改后使用 `virsh define` 应用。

- Windows 11 当前使用 PIIX IDE 系统盘以保证 Windows Setup 有内置驱动。
- `qemu.swtpm.enable = true` 为 Win11 提供 TPM 2.0 emulator。
- NAT 网络不对 LAN 暴露来宾端口。
- 虚拟机 SPICE 控制台只监听 `127.0.0.1`。

`qemu.runAsRoot = true` 是 NixOS libvirt 配置，`/mnt/VMSTORE` 上的镜像因此
不需要额外改属主。

## 与 Inua 的关系

Inua 有自己的 VM 后端（`internal/vm`），直接调 QEMU，不做 libvirt 客户端。
两个后端共用同一块 VMSTORE 盘，但各自管理自己的目录：

- Inua：`VMs/<name>/`（例如 `VMs/inua-lab/`）
- libvirt：`libvirt/images/`（存储池 `vmstore`）

不要用两个后端操作同一个 qcow2：QEMU 的镜像锁会报
`Failed to get shared "write" lock`。

## 排错

```bash
systemctl status libvirtd
journalctl -u libvirtd -b --no-pager | tail -50
virsh -c qemu:///system list --all
virsh -c qemu:///system domblklist win98
```

`virsh` 连接失败、报 `authentication unavailable` 时，检查
`security.polkit.enable` 和当前用户是否在 `libvirtd` 组。

虚拟机启动但画面全黑时，先用
`virsh -c qemu:///system screenshot win98 /tmp/s.ppm` 抓一张客体画面，
再 `journalctl -u libvirtd -b` 看有没有固件或磁盘错误。固件选错是最常见的
原因（BIOS 镜像用了 UEFI 配置）。`win98` 的 ISO 只支持 BIOS，所以域里给的是
SeaBIOS，没有 pflash。
