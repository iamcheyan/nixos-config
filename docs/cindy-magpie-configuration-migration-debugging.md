# Cindy 的 Magpie 供应商配置、迁移与排错记录

记录日期：2026-10-16。本文记录 HX90 上已经配置好的 Magpie 供应商迁移到 Debian 的过程，包括错误操作、最终修复和验证范围，供以后迁移时直接参考。

## 1. 最终结果与问题原因

目标是把 **HX90 本机已经配置好的 `Magpie (Debian)` 供应商复制到 Debian 的 Cindy**，保留供应商 ID、地址、协议、模型和模型参数。迁移对象是这一个供应商。

最终保留的供应商 ID 是 `magpie-debian`，地址为：

```text
https://debian.tailb4776a.ts.net:8444/v1
```

三个运行时都使用这个供应商：Claude Code、Codex、Pi。上游协议都是 OpenAI Chat Completions；Codex 在 Cindy 内通过兼容桥接使用该协议。

这次故障的直接原因有两部分：

1. 复制数据库中的供应商记录后，当前 Cindy 进程的运行时供应商目录没有同步更新。界面显示了供应商和模型，创建对话时仍报供应商不存在。
2. 在当前登录账号的编辑界面中，Claude Code 显示已有保存的密钥，但 **Codex、Pi 的密钥输入框为空**。供应商配置的复制没有同时完成这两个运行时在当前账号下的密钥保存。

修复方式是在当前已登录的 Cindy 中编辑这条已复制的供应商，给三个运行时保存经过上游验证的有效密钥。保存后日志出现：

```text
[provider-service] custom providers merged into active catalog { count: 1 }
```

随后在同一个 Debian Cindy 窗口中新建了测试对话：

| 项目 | 实际值 |
|---|---|
| 供应商 | Magpie (Debian)，`magpie-debian` |
| 模型 | default，`group/default` |
| 运行时 | Pi |
| 测试会话 | `302c52ea` |
| 提示词 | `Connection test only. Do not use tools. Reply exactly: Debian Magpie default works.` |
| 实际回复 | `Debian Magpie default works.` |

这是实际 Cindy 对话成功的证据。Claude Code 和 Codex 的密钥已保存，但这次最终验收没有分别创建它们的测试对话。也没有在最后成功后再次重启，不能把本次结果扩展为“所有运行时和重启后的登录持久性都已测试”。

## 2. 环境与配置归属

### 2.1 两台机器不同

| 项目 | HX90 源机器 | Debian 目标机器 |
|---|---|---|
| 系统 | NixOS，Labwc / Anchor Shell | Debian 13，webdesktop 的 X11 桌面会话 |
| 本次观察到的 Cindy 版本 | 0.1.109 | 已安装、运行的是 0.1.108；界面提示 0.1.109 更新待重启 |
| 应用入口 | Nix 声明的 `cindy` 包 | `/usr/bin/cindy`，实际程序 `/usr/lib/cindy/Cindy` |
| 应用资料目录 | `~/.config/CindyGlobal` | `~/.local/state/webdesktop/xdg/config/CindyGlobal` |
| 用户菜单目录 | 由本机桌面配置决定 | `~/.local/state/webdesktop/xdg/data/applications` |

不能因为两边用户名一样，就假定它们使用相同的数据目录、密钥环、显示协议或登录会话。

### 2.2 NixOS 的安装与缩放接线

本机包定义在 `modules/packages/cindy.nix`，由 `hosts/hx90/configuration.nix` 加入系统包。当前包固定版本与下载校验值，解包官方 `.deb`，使用 `buildFHSEnv` 提供 Electron 所需运行库，包括 `libsecret`。

启动器的关键部分是：

```sh
export ELECTRON_OZONE_PLATFORM_HINT=wayland
export OZONE_PLATFORM=wayland
exec /path/to/Cindy --ozone-platform=wayland "$@"
```

这些设置位于 Nix 包生成的持久启动链中，菜单、终端与 URI 入口都进入同一启动器。修改系统接线应编辑仓库源文件，经构建与 switch 应用，不能仅在某次手动启动命令中加参数。

原先的缩放需求是不同显示器分别使用其缩放比例，例如 2 倍屏幕使用 2 倍缩放。原生 Wayland 是当前仓库采用的接线方式。固定全局 `--force-device-scale-factor=2` 无法表达不同显示器不同缩放，不应当作这个需求的持久方案。本文记录当前包装方式，没有重新进行跨屏缩放验收。

### 2.3 Debian 的 XDG 路径

本次 Debian 桌面实际使用：

```text
DISPLAY=:20
XAUTHORITY=~/.local/state/webdesktop/Xauthority
XDG_CONFIG_HOME=~/.local/state/webdesktop/xdg/config
XDG_DATA_HOME=~/.local/state/webdesktop/xdg/data
XDG_CACHE_HOME=~/.local/state/webdesktop/xdg/cache
```

因此，往 `~/.config/CindyGlobal` 或 `~/.local/share/applications` 写文件，不一定会影响这个桌面中的 Cindy。应先检查正在运行的应用与桌面会话环境。

### 2.4 菜单入口与“装了几个 Cindy”

Debian 系统桌面文件为 `/usr/share/applications/cindy.desktop`；实际 XDG 用户菜单目录中有同名覆盖文件：

```text
~/.local/state/webdesktop/xdg/data/applications/cindy.desktop
```

本次使用的关键启动行为：

```ini
Exec=cindy --password-store=gnome-libsecret %U
```

同一 desktop ID 的用户覆盖文件用于覆盖系统项，本身不等于又安装了一份 Cindy。此前放错到默认用户目录的覆盖文件被移除。

检查安装包数量、菜单项、主进程应分别检查，不能把 Electron 的 renderer、GPU、zygote 子进程算作多份安装。不同入口即使运行同一个二进制，也可能因 XDG 路径或会话环境不同而打开不同资料。

## 3. Magpie 供应商应如何配置

### 3.1 管理页面与 API 地址

| 用途 | 地址 |
|---|---|
| Magpie 管理与路由页面 | `https://debian.tailb4776a.ts.net:8443/?view=routing` |
| Cindy 实际访问的 API Base URL | `https://debian.tailb4776a.ts.net:8444/v1` |
| 模型发现 | `https://debian.tailb4776a.ts.net:8444/v1/models` |
| Chat Completions | `https://debian.tailb4776a.ts.net:8444/v1/chat/completions` |

管理页面端口和推理端口不同，不能把 `:8443` 管理页面直接填成推理 API。

早期页面曾给出 `http://127.0.0.1:3425/v1` 的本机接入示例。`127.0.0.1` 指向运行客户端的那台机器；迁移到另一台主机时不能直接沿用。此次用户明确指定、实际验证有效的地址是上述 `:8444/v1`。

页面上的 `OPENAI_API_KEY=magpie` 示例描述了某种本机回环接入方式。本次远程 HTTPS 端点使用管理后台签发的调用方密钥，不能据此认定字符串 `magpie` 在远程端点也有效。本文不保存实际密钥。

### 3.2 模型 ID 来自哪里

模型应从实际推理端点的 `/v1/models` 获取，或直接使用后台明确给出的路由 ID。不能凭模型名称猜一个 ID 填进去。

本次实际查询返回：

| Cindy 显示名称 | 请求使用的模型 ID |
|---|---|
| default | `group/default` |
| GPT-6-Sol | `group/auto-gpt-6-sol` |
| free | `group/free` |

这些 ID 是 Magpie 路由组的入口，不保证对应某一个固定物理模型。具体转发、候选与故障切换由 Magpie 后台路由配置决定。旧截图里的名称或别名可能发生变化，应以当前端点返回结果为准。

用户指定默认使用 `default`，在 Cindy 中应选择 `Magpie (Debian)` 下的 `group/default`。

### 3.3 三个运行时分别保存

| Runtime | Base URL | 上游协议 | 密钥 |
|---|---|---|---|
| Claude Code | `https://debian.tailb4776a.ts.net:8444/v1` | OpenAI Chat Completions，使用 Cindy 的适配能力 | 在该运行时下保存 |
| Codex | 同上 | Chat Completions，Cindy 桥接 | 在该运行时下保存 |
| Pi | 同上 | OpenAI Chat Completions，原生连接 | 在该运行时下保存 |

“填充其他 runtime”不是完整凭据迁移。此次界面明确提示它是一次性字段填充，后续编辑不会自动同步，各运行时仍使用独立的 safeStorage 密钥记录。

因此，复制 Base URL、协议和模型后，必须切换到三个标签页分别确认密钥状态。某个标签页显示“已保存”，不能证明另外两个也保存了。

标准 Chat Completions 路径使用默认推导即可。精确请求路径是可选项，只有非标准端点才需要手动设置；应检查最终 URL，避免重复 `/v1` 或缺少路径。

### 3.4 在 Cindy 中配置或修复

1. 打开设置 → 模型供应商。
2. 已有供应商时选中 `Magpie (Debian)`，打开右上角更多操作 → 编辑连接设置。
3. 新建时选择添加供应商 → 自定义端点；迁移已有配置时优先导入已有配置内容。
4. 保留供应商 ID `magpie-debian`、名称、三个运行时的协议和地址。
5. 在各运行时分别保存有效调用方密钥。
6. 获取模型列表，确认实际出现三个路由；使用 `group/default` 作为默认对话模型。
7. 保存连接设置，让应用更新供应商目录和密钥状态。
8. 在同一已登录窗口中新建对话验证。

手动填写模型 ID 的界面还有“添加模型”按钮。只在输入框中键入 ID，不等于模型已经加入配置；此前出现过输入框有内容但仍显示“至少添加一个模型”的情况。

无需为普通对话启用 OpenAI Images 或视频 API。编辑时检查这些选项，避免鼠标坐标失准误改能力开关。

### 3.5 后台新增路由以后怎么办

本次使用的调用方密钥允许 `group/*`，目的是允许后续新增路由组，不把权限锁死为一个模型。

这里有三个独立条件：

1. Magpie 已发布新路由，`/v1/models` 中能看到它。
2. 调用方密钥权限允许访问它。
3. Cindy 刷新模型列表后发现并启用了它。

后台新增路由后，在 Cindy 的这个供应商中刷新或获取模型列表，不需要每次手工输入模型 ID。发现的新模型是否立即启用，应按当前版本的选择界面确认。本次验证了模型发现返回三个路由，没有实际新建第四个路由来验证自动发现，也没有证明“后台一改，Cindy 不刷新就自动启用”。

## 4. 供应商配置如何迁移

### 4.1 应迁移的内容

需要复制：供应商 ID、名称、三个运行时的 URL 与协议、模型定义和模型参数，以及目标账号中的密钥保存。

供应商定义、账号模型选择、加密凭据、登录状态和进程中的供应商目录是不同的状态。复制其中一项不会自动完成其余各项。

不应为了迁移这一个供应商覆盖整个应用资料目录：其中还包含聊天记录、登录令牌、缓存、其他供应商和运行时资料。

### 4.2 本次供应商记录的存储位置

本次源记录位于 HX90 的账号数据库：

```text
~/.config/CindyGlobal/cindy-cmv9i0xz401c8yg013q3zkqb0.db
```

目标位置为 Debian 实际 XDG 配置目录中的同名数据库。这个文件名是本次现场值，不能假定其他账号、版本或设备仍使用它。

供应商表为 `custom_providers`，本次观察到的列为：

```text
id, name, runtimes, sort_order, created_at, updated_at, auth
```

`runtimes` 保存各运行时的定义与模型元数据。本次源记录包含三个路由，以及模型名称、推理档位、上下文等元数据。迁移时直接复制现有记录，避免按截图重新手工重建而丢失这些参数。

### 4.3 复制之前先备份

先确定真实数据目录与当前账号。备份目录设为仅当前用户可访问；SQLite 使用其 backup API 或应用支持的导出功能，避免只复制正在使用的 `.db` 而遗漏 WAL 中的数据。

只备份真实业务数据库。不要遍历所有 `*.db` 后对每个文件调用 SQLite backup：本次这样做时遇到了长期占用的 ownership 锁数据库，备份进程阻塞。最后终止了该备份 Python 进程。

这次留下的主要备份位置是：

```text
~/.local/state/cindy-backups/20261016-011741/
~/.local/state/webdesktop/xdg/config/CindyGlobal/cindy-cmv9i0xz401c8yg013q3zkqb0.db.before-provider-copy-20261016-012406
```

第一个目录来自被中断的备份流程，不应未经检查就认为里面每个文件都是完整备份。第二个是复制供应商记录前，通过 SQLite backup API 创建的业务数据库备份。

`safe-storage` 的备份只能用于同机、相同密钥环和账号环境的恢复参考。不要把旧登录令牌的恢复当作通用恢复手段，原因见后文。

### 4.4 本次实际执行的记录复制

从源数据库选取 `id = 'magpie-debian'` 的唯一记录，通过 SSH 标准输入传给 Debian 的 Python 进程。在目标数据库创建备份后，按目标表实际拥有的列执行带参数的 upsert，并再次读取比较。

实际结果为：

```text
Copied provider: magpie-debian Magpie (Debian) ; exact database record match
```

这只证明数据库记录复制一致，**当时还没有证明当前窗口能成功对话**。后续故障恰好说明不能省略应用内保存和对话验收。

以后优先通过 Cindy 支持的导入或供应商写入接口接收源配置。若只能采用数据库记录迁移，应先备份，限定单条供应商记录，并在当前账号中完成应用内保存与验证。

下面是针对本次已确认表结构的单条记录导出示例。在 HX90 上执行；其他账号要先更换实际数据库路径。此表记录不包含本次存放在 safeStorage 中的调用方密钥，但导出文件仍按私人配置保管。

```python
import json
import os
from pathlib import Path
import sqlite3

source_db = Path.home() / ".config/CindyGlobal/cindy-cmv9i0xz401c8yg013q3zkqb0.db"
export_file = Path.home() / "cindy-provider-export.json"
db = sqlite3.connect(source_db.as_uri() + "?mode=ro", uri=True)
db.row_factory = sqlite3.Row
row = db.execute(
    "SELECT * FROM custom_providers WHERE id = ?", ("magpie-debian",)
).fetchone()
if row is None:
    raise SystemExit("Source provider not found")
fd = os.open(export_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.fchmod(fd, 0o600)
with os.fdopen(fd, "w") as stream:
    json.dump(dict(row), stream, ensure_ascii=False, indent=2)
db.close()
print("Exported provider configuration without safeStorage credentials")
```

通过 SSH 复制这个配置文件：

```sh
scp ~/cindy-provider-export.json debian:~/cindy-provider-export.json
```

以下是本次数据库复制方式的可复用示例。在 Debian 上执行，先确认目标账号数据库路径。它只 upsert 导出记录对应的供应商，先备份，再比较写入结果。**它不负责保存目标账号密钥，也不刷新正在运行的应用目录；执行完仍需完成下一节的应用内保存。**

```python
from datetime import datetime
import json
from pathlib import Path
import sqlite3

target_db = Path.home() / (
    ".local/state/webdesktop/xdg/config/CindyGlobal/"
    "cindy-cmv9i0xz401c8yg013q3zkqb0.db"
)
record = json.loads((Path.home() / "cindy-provider-export.json").read_text())
if record.get("id") != "magpie-debian":
    raise SystemExit("Unexpected provider ID; stop without modifying data")

db = sqlite3.connect(target_db)
backup_file = target_db.with_name(
    target_db.name + ".before-provider-copy-" + datetime.now().strftime("%Y%m%d-%H%M%S")
)
# 备份文件从创建时即限制权限。
backup_file.touch(mode=0o600, exist_ok=False)
backup = sqlite3.connect(backup_file)
db.backup(backup)
backup.close()

allowed = {row[1] for row in db.execute("PRAGMA table_info(custom_providers)")}
record = {key: value for key, value in record.items() if key in allowed}
columns = list(record)
names = ",".join('"' + name.replace('"', '""') + '"' for name in columns)
updates = ",".join(
    '"' + name.replace('"', '""') + '"=excluded."' + name.replace('"', '""') + '"'
    for name in columns if name != "id"
)
db.execute(
    f"INSERT INTO custom_providers ({names}) VALUES "
    f"({','.join('?' for _ in columns)}) ON CONFLICT(id) DO UPDATE SET {updates}",
    [record[name] for name in columns],
)
db.commit()
actual = dict(zip(columns, db.execute(
    f"SELECT {names} FROM custom_providers WHERE id = ?", (record["id"],)
).fetchone()))
assert actual == record, "Copied record differs from source"
db.close()
print("Provider record copied and compared; now save credentials in Cindy")
```

完成迁移与验收后删除两台机器上的临时导出文件。不要把它们混入系统配置仓库的版本管理。

### 4.5 密钥为什么不能直接随加密文件搬过去

Linux 上 Cindy 使用 Electron safeStorage 与系统密钥环保存凭据。加密文件依赖机器上的加密环境，也存在账号所有者命名空间。

此次看到的密钥文件名形如：

```text
safe-storage/owner_<namespace>_provider_key_magpie-debian_claude-code.enc
safe-storage/owner_<namespace>_provider_key_magpie-debian_codex.enc
safe-storage/owner_<namespace>_provider_key_magpie-debian_pi.enc
```

现场曾存在不同 `owner_...` 前缀的记录。某个目录里有同名供应商的加密文件，不证明当前登录账号能读取它，也不证明三个运行时都已配置。

正确做法是保留源供应商定义，在目标账号中通过 Cindy 保存同一个有效调用方密钥，由目标机器的密钥环重新加密。密钥不要写入本仓库、文档、命令行参数、调试输出或截图。

### 4.6 供应商目录也需要更新

本次直接复制记录后，模型列表能显示三个模型，但实际创建 Pi 会话失败。通过当前账号的编辑连接设置保存后，日志记录了供应商合并到活动目录，随后实际对话成功。

Cindy 0.1.108 的 renderer 中曾观察到这些内部接口：

```text
window.electronAPI.maker.listProviders
window.electronAPI.maker.createCustomProvider
window.electronAPI.maker.updateCustomProvider
window.electronAPI.maker.fetchProviderModels
```

它们是本次版本的内部接口，并非稳定公共 API。使用自动化迁移时应从当前版本确认签名，把源配置作为输入，避免绕过应用状态更新；密钥只通过安全输入传递。普通维护可以直接使用编辑连接设置完成这一保存动作。

## 5. 这次完整排查经过

| 阶段 | 做了什么 | 发现或结果 |
|---|---|---|
| 初始现场 | 查看 Debian 已登录窗口的模型供应商 | 只有原来的 Magpie，显示 688 个模型；预期的 Magpie (Debian) 没出现 |
| 早期误判 | 之前只确认过登录前本地资料中的供应商记录 | 没有确认登录后的当前账号和当前窗口；这不构成迁移成功 |
| 绕路操作 | 进入添加供应商向导，重新填写运行时与模型 | 偏离“直接复制现有供应商”的要求；表单滚动和标签切换还造成坐标误操作 |
| 找到源配置 | 查询 HX90 的 `custom_providers` | 找到完整 `magpie-debian` 记录，三个运行时和模型元数据都在 |
| 引入额外故障 | 为访问 renderer 调试接口重启应用，并尝试恢复凭据备份 | 出现登录存储不可用以及旧刷新令牌失效；这不是复制供应商所必需的步骤 |
| 实际复制 | 将源供应商记录 upsert 到目标账号数据库并逐字段比较 | 数据库记录一致，但当时尚未通过对话测试 |
| 登录后的报错 | 用户再次登录，供应商和三个模型可见 | 用户报告密钥无效；实际对话截图显示 `LAZY_CREATE_FAILED`，供应商未进入可用运行时目录 |
| 上游检查 | 用有效调用方密钥请求实际端点 | `/v1/models` 返回三个路由；`group/default` 的 Chat Completions 返回 200 和 `connection OK` |
| 当前账号检查 | 编辑现有供应商，逐个打开运行时标签 | Codex 和 Pi 的密钥框为空；Claude Code 显示已有保存记录 |
| 修复 | 三个运行时保存已验证的有效密钥，保存连接设置 | 日志显示一个自定义供应商合并到活动目录 |
| 最终验收 | 同一窗口新建 Pi + default 对话 | 成功返回 `Debian Magpie default works.` |

## 6. 错误现象、含义与处理

### 6.1 界面里看不到迁移过来的供应商

优先检查当前机器、XDG 目录、当前登录账号与资料所有者。不要只检查某个磁盘文件中有一条记录。

本次登录前资料与登录后界面不一致，是早期验证遗漏。最后必须以用户实际从菜单进入的那个窗口为准。

### 6.2 显示密钥无效或认证失败

用户曾报告“密钥无效”。本次没有单独取得 Cindy 对应请求的 401 响应作为证据；后续直接访问上游的有效密钥返回了 200，所以不能把所有报错都归为 Magpie 服务拒绝认证。

依次检查：

1. 实际 Base URL 是否为 `:8444/v1`。
2. 是否用了适用于远程端点的调用方密钥。
3. 密钥权限是否覆盖目标 `group/...`。
4. 当前所选运行时是否真的保存了密钥。
5. 当前账号命名空间和密钥环是否可读取它。
6. 实际原始错误是否其实是供应商缺失、模型缺失或协议不匹配。

### 6.3 `LAZY_CREATE_FAILED`：供应商不存在

本次实际截图中的错误为：

```text
LAZY_CREATE_FAILED: pi: BYOM provider 'magpie-debian' cannot serve model
'group/default' (provider absent, or it no longer offers this model);
refusing to fall back to the Cindy gateway
```

该错误发生在运行时定位供应商/模型阶段，不等于上游返回了“密钥无效”。应用拒绝自动回退到 Cindy 网关，避免把请求发给错误端点。

处理：确认供应商 ID 和模型 ID，补齐当前运行时的密钥，通过应用保存已迁移配置，让供应商进入活动目录，然后创建新的测试对话。

### 6.4 “至少添加一个模型”，但输入框已经有 ID

手动模型 ID 输入框仍是待添加文本，需要点击“添加模型”。也可以获取模型列表后选择导入。以界面的“已配置 N 个模型”和保存结果为准。

### 6.5 登录信息暂时无法存取

重启过程中实际出现过这个页面。排查发现 Debian 存在不同的会话总线：

- 桌面 `xfce4-panel` 继承的总线是 `unix:path=/tmp/dbus-...`。
- 用户级总线是 `unix:path=/run/user/1000/bus`。
- 检查时，用户级总线上存在 `org.freedesktop.secrets`，其 login collection 为未锁定状态。

XDG 路径相同不代表 DBus、密钥环和登录凭据环境相同。通过 SSH 临时拼一组环境变量重启，可能与桌面菜单实际环境不同。

避免为供应商复制反复重启。若必须修复启动环境，先记录当前可用主进程和桌面会话的环境，确认密钥服务所在总线，再统一持久入口。本次最终连接修复在已经登录的窗口完成，未进一步重新验证菜单冷启动登录，因此这部分不能宣称已完成持久性验收。

### 6.6 恢复旧备份后 `INVALID_REFRESH_TOKEN`

日志实际出现：

```text
cold-start refresh attempt 1 failed status=401 code=INVALID_REFRESH_TOKEN
cold-start refresh: definitive credential failure — cleared persisted auth session
```

恢复旧的 `cindy_auth_session_v1.enc` 不能保证恢复登录。刷新令牌可能已经轮换或失效；该日志证明恢复出的旧令牌被认证服务拒绝。不要反复覆盖登录文件来修供应商配置。

这次用户重新完成了登录；最终供应商修复使用的是这个已经登录的窗口。

### 6.7 调试接口没有 handler 或连接不到

启动早期曾出现：

```text
No handler registered for 'maker:provider:list'
```

应先确认应用是否完成初始化、是否处于登录存储错误页，以及当前 renderer 是否还是最初连接的那个。调试端口、renderer 生命周期和登录边界都可能变化，不能把调试接口暂不可用解释成供应商配置本身不存在。

本次曾临时使用 `--remote-debugging-port=9227` 访问 renderer。它是排错手段，不应加入正常菜单入口；调试接口不要暴露到网络。最终修复通过当前窗口的设置界面完成。

### 6.8 截图与鼠标自动化误操作

对话框会因滚动、标签切换和校验提示改变布局。沿用上一张截图的坐标，可能点到模型类型、图像 API 开关或非输入区域；在非输入区域按 Ctrl+A 会选中整页。

此次确实出现过这种绕路。可靠的操作顺序是每次切换标签或滚动后重新确认字段位置，保存后检查结果。不要把“已发出鼠标点击”当成“已保存成功”。

## 7. 可复用的上游验证脚本

以下脚本只在终端交互读取密钥，文档和 shell 历史不包含密钥。它验证模型发现和 default 的真实对话；运行时需要能够访问该 HTTPS 地址的机器和 Python 3。

```python
import getpass
import json
import urllib.error
import urllib.request

base_url = "https://debian.tailb4776a.ts.net:8444/v1"
api_key = getpass.getpass("Magpie caller key: ")
headers = {
    "Authorization": "Bearer " + api_key,
    "Content-Type": "application/json",
}

def request(path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base_url + path, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        # 不打印请求头、密钥或任意完整服务端响应。
        raise RuntimeError(f"{path}: HTTP {exc.code}") from None

status, data = request("/models")
print("Models HTTP", status)
print([model["id"] for model in data["data"]])

status, data = request("/chat/completions", {
    "model": "group/default",
    "messages": [{"role": "user", "content": "Reply only: connection OK"}],
    "max_tokens": 32,
    "stream": False,
})
print("Chat HTTP", status)
print(data["choices"][0]["message"].get("content"))
```

本次这两项的实际结果分别是三个路由的列表、HTTP 200 和 `connection OK`。上游验证成功之后，仍需要 Cindy 内对话验证，才能覆盖密钥保存、账号归属、供应商目录和运行时适配。

## 8. 下次迁移的最短可靠流程

1. 确认源机器已有供应商能用，导出这一个供应商的完整定义。
2. 确认目标当前窗口、账号、XDG 路径；备份对应业务数据。
3. 复制并导入现成定义，保留供应商 ID、协议、模型与元数据。
4. 在目标账号给三个运行时分别保存有效密钥；无需改登录状态。
5. 保存配置，确认供应商目录更新；刷新实际 `/models` 列表。
6. 选择 `Magpie (Debian)` → `default`，新建测试对话并检查实际回复。
7. 明确报告验证范围；只有另外实际测试过其他运行时、菜单重开与冷启动，才能声明这些也通过。

这次最应避免的错误是把“源记录存在”“目标记录一致”“界面能显示模型”和“实际运行时能对话”当成同一件事。最终成功的依据应是目标当前账号中的真实对话结果。
