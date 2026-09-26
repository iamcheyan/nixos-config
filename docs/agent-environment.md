# 全局 Agent 环境与 Skills

## 实现原理

Nixarchy 的做法是把 `SKILL.md` 安装到只读系统资源中，再将每个 skill 目录
链接到 Agent 的用户级发现目录。Agent 先看到名称/触发描述，任务匹配时读取全文；
这不等于每条聊天都强制执行一次 skill。

本机现在由 `~/nixos-config` 接管，分为两部分：全局背景每个会话加载，
专项 skill 由任务触发。工作目录不影响这些用户级入口；普通网页聊天不会读取本机文件。

## 唯一来源和部署

全局背景正文：`modules/home-manager/agent-environment.md`。
部署模块：`modules/home-manager/nixos-user.nix`。

| Agent | 全局背景入口 |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| Claude Code | `~/.claude/CLAUDE.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| OpenCode | `~/.config/opencode/AGENTS.md` |
| 通用本机入口 | `~/.config/agent/AGENTS.md` |

上述文件共享一份正文。Home Manager 管理链接，不由 chezmoi 复制维护。
自定义 `CODEX_HOME` 或其他独立 profile 仍需将背景接入该 profile。

系统 skills 源在 `modules/anchor-shell/compat/omarchy/default/agents/skills/`，
Home Manager 为 `.agents/skills`、`.codex/skills`、`.claude/skills`、
`.pi/agent/skills` 声明每个 skill 的目录链接。更新源文件再 rebuild 即可更新，
不依赖一次性 provision。`nixarchy` 是保留的桌面 skill 名，内容已改为本地
Labwc / Anchor Shell 与备用 Hyprland 的维护规则。

## 内容边界

- `~/nixos-config`：系统声明、桌面系统接线、全局本机背景及系统 skills。
- `~/chezmoi`：私人用户偏好、跨平台 Agent 启动器/provider 配置、凭据入口。
- `~/dotfiles`：公开通用 shell/editor 配置。

背景记录稳定事实；当前目录、Git 状态、远程主机、容器和当前运行状态必须在现场读取。
不要将本机规则套到远端，也不要把动态健康报告写成长期固定事实。

客户端入口参考：[Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)、
[Claude Code](https://support.claude.com/en/articles/14553240-give-claude-context-claude-md-and-better-prompts)、
[Gemini CLI](https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html)、
[OpenCode](https://dev.opencode.ai/v2/docs/instructions/)。各工具版本的加载行为仍以实际实现为准。

Nixarchy 移除的完整接管清单见 [nixarchy-removal.md](nixarchy-removal.md)。
