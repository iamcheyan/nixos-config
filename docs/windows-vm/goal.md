# Goal：在 Inua 中实现跨发行版 Windows VM 管理

## Goal

在 Inua 中实现可交付给其他用户使用的 Windows VM 功能。用户通过 Inua 发现、配置、安装、启动、连接、停止、恢复和按确认移除 Windows VM；不依赖 Omarchy、Anchor Shell 兼容层或 `omarchy-windows-vm`。首批支持 NixOS 与 Ubuntu/Debian，使用 Docker Compose + Dockur Windows + KVM + RDP。实现设计与行为契约见 [`inua-integration.md`](inua-integration.md)，本 goal 与该设计共同构成验收要求。

“由 Inua 实现”指 Inua 拥有 UI、生命周期、状态、配置、安全边界和宿主依赖引导；Docker、Compose、KVM、RDP 仍是平台运行组件。不能把这些平台依赖假定为预装，也不能静默执行系统级变更。

## 仓库与工作边界

主实现仓库：Inua 仓库（独立 checkout）。
NixOS 集成仓库：本仓库；只放可复用 NixOS 模块、平台文档和主机集成，不把维护者机器路径写入可分发模块。
旧实现 `modules/anchor-shell/compat/omarchy/bin/omarchy-windows-vm` 仅作只读行为参考。新功能不得执行或包装该脚本，不依赖其文件、Polkit 规则、数据目录或菜单状态。
保留两仓库现有用户改动；不得触碰现有 Windows 客体磁盘或旧 VM 数据来做普通构建/测试。

## 分支与工作区

本功能必须在独立功能分支开发，不直接提交到 `master`/`main`，也不叠加到无关 PR 分支。
Inua 仓库从 `upstream/master` 创建 `feat/windows-vm`；现有截图快捷键 PR 分支保持独立。若分支名已存在，先检查内容并选择不冲突的新名称，不覆盖已有分支。
NixOS 集成仓库从其当前主开发分支创建 `feat/inua-windows-vm`，只增加可复用集成、平台文档和验证配置。
开始实现前确认两仓库工作区干净；若有未提交改动，保留它们并使用独立 worktree，不 stash、覆盖或混入功能分支。
两个分支分别提交、审查；Inua 核心 PR 与 NixOS 集成 PR 通过明确的模块/CLI 契约关联。Ubuntu/Debian 适配器和文档随 Inua 主仓库交付。
功能分支可随阶段提交；合并前更新目标分支、解决冲突并重新运行受影响验证。不得把个人本机状态或绝对路径作为可分发配置。

## 必须交付

### 1. 支持平台与依赖

- 声明 NixOS、Ubuntu/Debian 的明确支持范围和依赖映射。
- 定义统一能力检测：OS、KVM/设备权限、Docker daemon、Compose v2、TUN/NET_ADMIN、磁盘空间/文件系统、RDP 客户端和 Web 控制台。
- 缺依赖时说明缺项、原因和平台适用的安装方案；任何 apt、NixOS 系统配置、服务启用或权限/组变更都必须在展示变更并取得用户确认后执行。
- NixOS 提供可由用户 flake 导入的模块/包集成；不得要求用户使用维护者机器的绝对路径。
- Ubuntu/Debian 提供可复现、来源可信的依赖引导。不能悄悄加入 docker 组；若设计允许该模式，明确告知其近似 root 的权限并由用户选择。
- 提供只读 `inua vm doctor` 和机器可读 JSON 输出，供 UI 与 CLI 共用。

### 2. VM 核心

- 在 Inua 中实现 Docker Compose + Dockur 后端、配置模型、受管容器识别和生命周期状态机。
- 状态至少区分未配置、配置不完整、首次初始化中、已就绪、启动中、运行中、停止中、已停止、降级/错误。
- 首次 Windows 镜像下载/初始化可长时间运行；UI 可关闭后恢复查看，超时/取消等待不能删除或重置 VM。
- 安装、启动、停止、连接等重复/并发请求有定义且安全；重复入口操作聚焦现有 RDP 会话，不创建无限会话。
- RDP 客户端退出不隐式停止 VM；默认不自动启动 VM。
- Compose 端口默认仅绑定 loopback；冲突需诊断并允许安全配置其他端口。

### 3. 数据与安全

- 使用 `$XDG_DATA_HOME/inua/vm/windows`、`$XDG_CONFIG_HOME/inua/vm/windows.toml`、`$XDG_STATE_HOME/inua/vm`，不得复用 `/var/lib/omarchy/windows` 或旧 `~/.windows` 路径。
- 显示稀疏磁盘虚拟容量与实际占用，安装前检查磁盘余量。
- 不使用默认弱密码；秘密存入 Secret Service，或首版经安全评审后以严格权限保存。不得通过 argv、日志、通知、崩溃信息或普通配置泄漏秘密。
- 安装、配置与恢复保留用户数据；停止和移除是分离动作。移除必须验证目标目录边界、处理符号链接/挂载点风险、展示删除范围并二次确认。
- 不增加任意命令无密码提权，不运行用户可写提权脚本，不开放非 loopback 端口。
- 依赖来源、Dockur 镜像/tag、下载量、权限风险和升级/回滚语义均有文档说明。

### 4. Inua 产品界面与接口

- 抽屉 SYSTEM 组始终显示 Windows VM shell app；未安装时入口也存在。
- 提供管理视图：状态、依赖诊断、首次设置、初始化进度、Web 控制台、启动/连接/停止及受保护移除。
- 服务和状态不依赖 GTK；遵循 Inua 现有 `internal/desktop`、`internal/ipc`、`gtkx.Post/Call` 分层。
- 提供 `inua vm status|doctor|install|start|connect|stop|console|remove` CLI；JSON schema 版本化，错误类别稳定。
- 文案可翻译，更新 `.pot` 与 catalogs；Blueprint `.blp` 和生成 `.ui` 同步；Phosphor 图标同步更新图标脚本及资源。
- 更新 README、架构文档和面向用户的 VM 文档；清楚区分受支持平台、前置条件、授权影响、下载/磁盘需求、初始化等待和恢复方法。

## 验收标准

1. 在没有旧 Omarchy/Anchor Shell VM 组件的 NixOS 与 Ubuntu/Debian 环境中，Inua 入口均可见；未支持系统会给出解释，不猜测安装命令。
2. 两个平台的能力检测能分别报告软件缺失、daemon 未运行、权限不足、无 KVM、空间不足和检测错误；安装计划可预览，执行需要确认。
3. 核心生命周期可用 fake Docker 后端与临时目录测试，不要求普通自动化测试下载 Windows 镜像或连接真实 Docker daemon。
4. 首次安装能拉取并持续初始化；等待超时后状态可恢复查看；未就绪时不能声称可连接。
5. 已配置 VM 可启动、连接、关闭客户端后继续运行、停止后保留数据，再次启动恢复。
6. 重复点击复用/聚焦已有 RDP 客户端；并发操作不会重复创建或删除资源。
7. 端口只监听 loopback；秘密不出现在 argv、日志、通知和普通配置；移除路径攻击测试拒绝越界、符号链接和危险挂载情况。
8. 数据删除前 UI 与 CLI 都展示准确目标并要求明确确认；取消或失败后用户数据仍在。
9. NixOS 模块能被独立 flake 导入并求值/构建；Ubuntu/Debian 安装流程在干净 VM 或明确记录的干净环境验证，覆盖取消和失败恢复。
10. 实际 Dockur/Windows 集成手测记录冷启动、首次安装、长时间初始化、重启恢复、RDP、多显示器缩放、stop/start、端口冲突与数据保留。未运行的组合明确列为未验证，不能宣称完整支持。
11. Inua 常规构建、行为测试、Go vet、生成文件和翻译检查通过；交付说明列出实际执行的命令和结果。

## 实施阶段

1. **查证协议与威胁模型**：核对 Dockur 当前配置、镜像许可/标签、健康信号、Compose/Docker API、FreeRDP 凭据传递与 NixOS/Debian 平台能力；形成短 ADR，锁定数据/权限/状态契约。
2. **核心 API 与状态机**：实现结构化错误、状态转换、操作协调、配置校验、fake backend 与边界测试。
3. **平台能力适配**：实现 NixOS 和 Ubuntu/Debian detector、依赖计划、确认式执行与 doctor 输出；在干净环境验证。
4. **Docker/Dockur 后端**：实现安全 Compose 生成、镜像准备、容器状态/就绪探测、安装进度、恢复、stop/start 和 loopback 网络。
5. **连接与凭据**：Secret Service/受保护凭据、FreeRDP 单实例、聚焦/重连、显示缩放和进程取消。
6. **Inua UI/CLI/IPC**：抽屉入口、管理视图、状态刷新和取消、CLI 子命令及 JSON schema。
7. **平台包与文档**：发布 NixOS 集成模块、Ubuntu/Debian 引导文档、用户文档、翻译、图标与架构记录。
8. **端到端验证与交付**：在两个平台的干净环境和实际 VM 上按验收矩阵手测；修复发现的问题，移除脚手架，报告未覆盖平台。

## 执行规则

- 每阶段完成后继续推进下一个阶段，直到上述验收条件全部满足；不能把设计、mock、单平台实现或 UI scaffold 当作 goal 完成。
- 若外部信息（例如 Dockur 协议或凭据接口）不明确，先查一手资料并记录版本/来源；禁止依据猜测实现安全关键行为。
- 任何破坏性 VM 数据操作都只能在明确隔离的测试数据目录执行；不得拿 HX90 现有 Windows VM 数据作测试对象。
- 需要用户产品选择时，先交付可审阅的默认设计，再集中询问真正阻塞实现的差异；一般实现决策依文档中的推荐值执行。
- 完成时汇总代码仓库、NixOS 集成仓库、支持平台验证证据、测试结果和仍未验证的环境。
