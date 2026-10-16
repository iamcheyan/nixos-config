# Inua Windows VM：实现设计

状态：设计基线，供 implementation goal 执行。  
日期：2026-10-16。  
首批宿主系统：NixOS、Ubuntu/Debian。  
后端：Docker Compose + Dockur Windows + KVM + RDP。

## 1. 产品目标与边界

Inua 提供 Windows VM 的完整用户体验：入口、首次安装、依赖检查与引导、配置、启动、就绪状态、RDP 连接、停止、恢复和卸载。用户不需要安装 Omarchy、Anchor Shell 兼容层或 `omarchy-windows-vm`，也不需要手工编写 Compose 文件。

“功能属于 Inua”表示生命周期、状态模型、用户交互、配置格式和数据管理由 Inua 定义并维护。宿主内核 KVM、容器运行时、Docker Compose 和 RDP 客户端仍是宿主组件；Inua 不复制内核、容器引擎或 RDP 协议实现。Inua 的安装向导为支持的平台提供对应依赖路径，并在执行系统级变更前清晰说明和取得用户确认。

现有 `omarchy-windows-vm` Bash 实现只作行为和运行约束的参考。Inua 不调用它、不依赖它的路径、数据、Polkit 白名单或 `omarchy-pkg-add`。不能把用户可写脚本包装成 root 命令，也不能复用旧实现的宽泛提权方式。

## 2. 用户体验契约

抽屉 SYSTEM 组始终显示 Windows VM shell app，即使 VM 尚未配置。打开入口后显示专用管理窗口或面板，呈现明确状态和可用操作。

| 状态 | 显示与操作 |
|---|---|
| 当前平台不支持 | 说明首批只支持 NixOS 与 Ubuntu/Debian，并显示诊断信息；不尝试安装或启动 |
| 缺少宿主依赖 | 列出具体缺项、用途和平台适用的安装方式；执行带确认的安装/配置步骤，随后重新检测 |
| 未配置 | 提供首次设置流程；默认值保守，说明磁盘空间和网络下载需求 |
| 配置不完整/上次安装中断 | 保留已有数据；提供继续、修复或明确确认后重置，不误报为可启动 |
| 首次安装/Windows 初始化中 | 显示阶段、可观测进度或最近活动；允许关闭 UI 而不杀掉 VM；重新打开可恢复查看 |
| 已配置、Windows 尚未就绪 | 说明 Windows 首次下载/初始化仍在进行，禁用 RDP 启动，提供打开本机 Web 控制台的操作 |
| 已就绪且停止 | 提供启动 Windows |
| 启动中 | 显示等待状态，可取消等待；取消不隐式删除或破坏 VM |
| 运行中 | 提供连接/聚焦已有 RDP 会话和停止；重复点击不得无意创建多个会话 |
| 停止中/失败 | 显示结果、可恢复操作和不含秘密的诊断详情 |

关掉 RDP 客户端不自动停止 VM。停止和删除是分开的操作。卸载应用与删除 Windows 虚拟磁盘是不同动作；删除虚拟磁盘必须单独、明确、二次确认，并说明不可恢复的数据范围。首版必须支持安全停止与保留数据；是否提供 UI 删除在实现时按本设计的确认约束完成，不允许静默清盘。

## 3. 支持平台与依赖提供

### 3.1 统一能力检查

平台适配输出结构化检测结果，不把发行版包名泄漏到 VM 状态机。至少检测：

- OS 识别及是否在支持列表；
- CPU 虚拟化能力、`/dev/kvm` 可访问性和当前用户权限；
- Docker daemon 可连接；
- Docker Compose v2 可用；
- 容器所需网络能力可用（`/dev/net/tun`、`NET_ADMIN`）；
- 可用磁盘空间与 VM 数据目录文件系统；
- RDP 客户端可用及版本/显示缩放能力；
- Web 控制台打开能力。

检测必须区分“软件缺失”“服务未运行”“权限不足”“硬件/固件不支持”“磁盘不足”和“检测错误”，并给出可执行解释。不能只检查命令是否存在就宣称 VM 可用。

### 3.2 NixOS

提供 Inua 的 NixOS 集成模块/包接口，声明 Docker、Compose v2、FreeRDP、必要的终端/安装 UI 工具及 Inua 自身运行依赖。需要用户级 Docker 使用权时，说明将用户加入 docker 组等同于授予 root 级宿主控制能力；不能静默加组或假设其安全。优先评估不扩大交互用户权限的受限特权服务方案；若首版采用 Docker 组，必须由用户明确配置并在 UI/文档解释风险。

KVM 设备和内核模块由 NixOS 主机配置提供。Inua 检查并报告缺项，显示可复制的 NixOS 配置建议；不从运行中的桌面直接编辑系统配置或自动执行 `nixos-rebuild switch`。Docker daemon 如何启用由模块示例明确说明。依赖模块可被主机 flake 导入，不得强制要求本仓库的本机绝对路径。

### 3.3 Ubuntu/Debian

提供明确支持版本范围和包映射，检查 Docker Engine/Compose v2、FreeRDP、`/dev/kvm`、用户权限与所需工具。优先使用发行版仓库的受支持包；若 Docker 官方仓库是必要条件，说明仓库来源、签名验证和安装影响。

Inua 可展示经过版本控制的安装命令/脚本，但执行 `apt`、修改组、启用 systemd 服务等系统级操作前必须列出变更并要求用户确认。安装失败要保留错误输出供诊断，不得吞掉错误后继续。

### 3.4 安装策略

平台适配器负责生成依赖计划、执行用户已确认的安装动作和复检结果。核心 VM manager 只依赖能力接口。不要在核心包散布 distro 判断，也不要为未支持的发行版猜测包名或运行包管理器。

提供只读诊断命令（例如 `inua vm doctor`）供 UI 与终端共用。命令输出支持 JSON，错误类别稳定且文档化；普通输出面向用户。安装流程应可重复执行，已满足的依赖不重复改动。

## 4. VM 后端与生命周期

首版 Docker Compose + Dockur Windows。Compose 模型和容器参数由 Inua 管理；用户可查看实际配置，但 UI 不要求用户编辑 Compose。容器固定使用 loopback 发布 Web 控制台与 RDP 端口，默认分别为 `127.0.0.1:8006` 和 `127.0.0.1:3389`（TCP/UDP）；端口冲突必须报告并允许受控改端口，不得绑定到全网接口。

生命周期 API 至少有 `Inspect/Doctor/Configure/Install/Start/WaitReady/Connect/Stop/Remove/OpenConsole`。调用可取消、可报告进度，操作需串行化避免重复配置或并发删除。后端通过 Docker Engine/Compose 的受支持接口实现；禁止拼接 shell 命令处理用户输入。所有子进程以参数数组启动、设定超时、收集有限输出并安全终止。

状态由持久配置、Docker inspect、健康探测和 Dockur 初始化信号共同推导：

- `absent`：无 Inua 配置和受管容器；
- `configured`：配置有效且数据目录存在；
- `provisioning`：首次拉取/启动/Windows 初始化未完成；
- `ready`：客体系统通过明确的就绪判定；
- `starting`、`running`、`stopping`、`stopped`；
- `degraded`：配置、容器或依赖不一致，可诊断/恢复；
- `error`：动作失败，携带可展示的错误类别和安全诊断信息。

不能以容器存在或 `State=running` 代表 Windows 已安装完成。就绪检测需要有版本化策略和总超时，但首次安装下载可持续很久；超时只停止等待，不删除或重置容器。优先使用 Dockur 明确的健康/就绪信号，评估后备 RDP TCP 探测；不要把易变的整段日志文本作为唯一持久协议。

重复打开时若已有 Inua 启动的 RDP 客户端，聚焦已有窗口；否则创建一个连接。一个 VM 同时至多一个由 Inua 管理的连接实例。关闭客户端不停止容器。VM 的自动启动策略首版默认为关闭，用户可显式开启。

## 5. 数据、配置与凭据

所有状态位于用户 XDG 目录，不使用 `/var/lib/omarchy` 或 `~/.windows` 等旧路径：

- 持久 VM 数据：`$XDG_DATA_HOME/inua/vm/windows/`；
- 用户配置：`$XDG_CONFIG_HOME/inua/vm/windows.toml`；
- 可重建状态/操作锁：`$XDG_STATE_HOME/inua/vm/`。

默认目录权限限制为当前用户。大型虚拟磁盘使用稀疏文件时，UI 分别显示虚拟容量与实际占用；实际占用来自文件系统分配量，不是 `stat` 的逻辑长度。安装前展示预计虚拟容量、下载量范围（若可知）和当前可用空间；不要承诺固定峰值。

不采用默认密码 `admin`。首次配置由用户设置凭据，或使用 Dockur 支持的安全随机凭据机制。凭据优先存入 Secret Service；若首版必须落盘，文件权限 `0600`，目录 `0700`，提供清除/轮换能力。绝不把秘密写入日志、通知、命令行参数、桌面文件、崩溃上下文或持久 Compose 配置。FreeRDP 密码使用受保护的 stdin/凭据文件机制，并确认客户端自身不会留下明文历史。

共享目录默认关闭；启用时只共享用户明确选择的目录，并做最小权限、路径包含性和符号链接处理。VM 删除逻辑必须校验目标位于 Inua 专用数据根目录，拒绝根目录本身、符号链接跳出和挂载点误删；先停止并卸载，再列出准确删除范围并二次确认。失败时保留数据。

## 6. Inua 内部架构

- `internal/vm`：无 GTK 的生命周期状态机、配置、错误类型、进度事件和后端接口；纯 Go 单测。
- `internal/vm/docker`：Docker/Compose 后端、受管容器识别、状态/健康探测、配置生成和操作串行化。
- `internal/vm/platform`：NixOS、Ubuntu/Debian 能力检测与依赖计划/用户确认后的安装器；发行版特定代码隔离。
- 服务层：复用 `internal/desktop` 启动桌面客户端的能力；扩展必须遵守现有进程生命周期、取消和输出处理惯例，不引 GTK。
- UI：抽屉 SYSTEM shell app 和专用窗口/面板；通过服务 API 发起动作，后台进度经 `gtkx.Post`/`gtkx.Call` 更新主线程 UI。
- IPC/CLI：为 UI 和脚本提供 `inua vm status|doctor|install|start|connect|stop|console|remove`；JSON 模式提供稳定 schema/version。破坏性动作在 CLI 和 UI 两侧都有明确保护。

初始入口采用 shell app，确保未安装时仍可见。设置页暂不作为前置条件；VM 管理窗口包含首次配置和运行状态。用户可调参数限于已定义且可验证的 RAM、CPU、磁盘容量、端口和共享目录，不暴露任意 Compose YAML。

遵循 Inua 分层：状态与服务不得 import GTK，所有 UI 文案可翻译，布局同时提交 `.blp` 与生成的 `.ui`，图标使用 Phosphor 并更新图标脚本，新增文案更新 `po/inua.pot` 和各 catalog。更新 `docs/architecture.md`、面向用户的 VM 文档和 README 功能说明。

## 7. 安全、权限与故障处理

首版优先让用户态 Inua 只访问 Docker socket 的现有授权路径；必须在 UI 明确说明 Docker socket/组权限近似 root。不能为图省事增加针对任意命令的无密码 Polkit 规则，也不能把 UI 可写文件作为 root 执行目标。

若需要特权操作，设计成窄接口、root-owned、固定动作集合、严格校验的宿主服务；通过 Polkit 对具体动作授权，参数只允许数据目录内的安全标识或有限枚举。先做威胁模型和接口审查，不复用 Omarchy 的 `pkexec` 包装。

网络映射只绑定 loopback。Compose 生成器校验数值和路径，所有文件用临时文件、权限设置后原子替换。镜像标签/版本策略明确且可升级；报告镜像来源、许可和首次下载体积。升级不得隐式升级 Windows 客体或覆盖虚拟磁盘。

故障消息需区分宿主依赖、daemon、权限、KVM、网络/下载、镜像启动、Windows 初始化、RDP 和磁盘错误。诊断不收集 VM 磁盘内容或凭据。日志保留上限和脱敏规则明确；用户可导出诊断包前预览包含内容。

## 8. 测试与发布验收

自动化测试使用 fake Docker API/命令适配器和临时目录，覆盖状态转换、错误分类、并发动作、配置验证、原子写入、路径安全、凭据脱敏、端口绑定和删除保护。不要在测试中下载 Windows 镜像、连接真实数据库或要求 Docker daemon。

CI 至少编译并测试 Go 代码，验证 NixOS 模块求值/包构建；Ubuntu/Debian 安装脚本做静态检查与 mock 包管理器测试。手工集成矩阵记录实际发行版版本、KVM、Docker、RDP 客户端、冷启动、首次 Windows 初始化、重启恢复、stop/start、端口冲突和移除确认。真实 Windows 镜像集成测试需手动运行并明确标记，不作为普通 CI 隐式副作用。

发布前必须确认：

1. 新用户无 Omarchy/Anchor Shell Windows VM 组件时仍可发现入口并完成引导；
2. NixOS 与 Ubuntu/Debian 的支持/不支持依赖均被准确检测，安装动作需确认；
3. 首次初始化耗时超过普通启动超时仍可恢复查看；
4. 运行中重复点击不会创建第二个受管 RDP 会话；
5. 停止保留虚拟磁盘，删除只在明确确认后删除且目标校验有效；
6. 凭据不进入 argv、日志、通知或普通配置；
7. Web/RDP 端口仅 loopback；
8. 文档与 UI 说明镜像来源、下载/磁盘需求、权限含义和故障恢复方式。

## 9. 执行顺序

1. **协议与威胁模型**：核实 Dockur 当前受支持的配置、就绪信号、Docker/Compose 能力、FreeRDP 凭据接口；锁定状态 API 和数据/安全边界。
2. **核心状态与后端**：配置模型、能力检测接口、状态机、fake 后端测试；先不实现 UI。
3. **平台集成**：NixOS 模块/文档与 Ubuntu/Debian 检查/确认式依赖流程；在干净环境验证。
4. **安装和恢复**：数据布局、Compose 配置生成、镜像拉取、初始化等待和失败恢复。
5. **启动/停止/连接**：生命周期、重复操作合并、RDP 单实例、连接关闭语义。
6. **Inua UI/CLI/IPC**：持久抽屉入口、管理视图、可取消进度、状态刷新、CLI/JSON。
7. **清理与发布**：安全卸载、文档/翻译/图标、平台矩阵手测和发布说明。

各阶段可按实现需要在代码仓库内分多个提交，但对外验收以完整生命周期和两个声明支持的平台为准；不得把仅有 UI、仅有 mock 后端或只在 HX90 上工作的版本标为完成。

## 10. 参考资料

- 本仓库只读参考实现：[`omarchy-windows-vm`](../../modules/anchor-shell/compat/omarchy/bin/omarchy-windows-vm)；只作为既有行为和风险证据，不是运行时依赖。
- 本仓库旧部署记录：[`README.md`](README.md)；其中路径、提权规则和现有安装状态属于 HX90 旧实现，不构成 Inua 的新契约。
- Inua 仓库：`internal/shell/dock.go`、`internal/ui/drawer.go`、`internal/desktop`、`internal/ipc`、`internal/layershell`、`docs/architecture.md`、`AGENTS.md`。
