---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this machine, from a systemd-coredump core dump.
  Use when a process has segfaulted, aborted, or otherwise dumped core, when asked
  why an application crashed or disappeared, or when a "Process crashed:" desktop
  notification is acted on. Triggers: crash, segfault, SIGSEGV, SIGABRT, core dump,
  coredumpctl, "why did X crash", "X keeps crashing", backtrace symbolization.
  Covers reporting a confirmed Nixarchy or Omarchy bug — see reporting.md.
---

## 本机约束

本机是 NixOS，配置源在 `~/nixos-config`，HX90 日常桌面是 Labwc + Anchor Shell。
Nixarchy 外部依赖已移除；不要调用 `nixarchy apply`、app/pkg 管理器或编辑旧的
`~/.config/nixarchy/*.nix`。系统变更直接编辑本仓库的 Nix 模块。先查看实际 cwd、
仓库 AGENTS.md 和已有更改。跨平台私人配置归 chezmoi，公开通用配置归 dotfiles。
构建本机使用 `nixos-rebuild build --impure --flake ~/nixos-config#hx90`；
用户授权应用后使用 `sudo nixos-rebuild switch --impure --flake ~/nixos-config#hx90`。
保留未提交改动，不编辑 `/nix/store`；不要为修复单个问题更新整个 flake。



# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible-sounding story.

## Establish the facts

`coredumpctl info <pid>` is the starting point. Beyond the backtrace, note the
**command line** the process was started with — it usually reveals what the
program was working on when it died, which is often the whole answer.

`coredumpctl list` shows whether this crash is a one-off or a pattern. Repeated
crashes of the same program, or several programs dying together, point somewhere
different than a single failure does.

## Rule out the boring causes first

Check resource exhaustion before blaming the program: `free -h`, and the journal
for OOM kills. A process killed by the OOM killer is not a bug in that process.

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same second
  as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent system generations.** A crash that starts right after a rebuild points at
  the rebuild. `nix profile diff-closures --profile /nix/var/nix/profiles/system` names exactly what changed between generations — stronger evidence than any package log — and `sudo nixos-rebuild --rollback switch` tests the theory in one command.

## Read the whole core, not just frame 0

Thread stacks other than the crashing one show what work was **in flight** —
thumbnailers, image loaders, IPC readers, GPU queues. That context often explains
the trigger even when the crashing frame itself cannot be symbolized.

Note any third-party code in the address space: file-manager or browser
extensions, plugins, out-of-tree drivers. In-process third-party code is a common
crash source and worth flagging — but do not pin blame on it without evidence
that it is actually implicated.

## Symbolize when you can

No public debuginfod serves nixpkgs builds. Symbols resolve only if this machine runs `nixseparatedebuginfod` (which serves the whole store on 127.0.0.1:1949 and exports `DEBUGINFOD_URLS` itself) or the package was built with `separateDebugInfo`. Run it anyway — gdb degrades to an unsymbolized stack rather than failing:

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="${DEBUGINFOD_URLS:-}" \
  gdb -q <executable> "$core" \
  -batch -ex 'set debuginfod enabled on' -ex 'bt'
```

A core is a verbatim copy of the process's memory and can hold passwords, tokens,
and private documents. Write it to a fresh `mktemp` path rather than a predictable
shared one, and delete it when you are done — never leave it lying in `/tmp`.

Many packages publish no debug symbols. When frames stay unresolved, say so —
never invent function names to fill the gap. An unsymbolized stack still has
shape: which library each frame belongs to, and whether the crash came from a
signal handler, a main loop, or a worker thread.

## Report

1. What crashed, and what it was doing at the time.
2. The most likely mechanism — separating clearly what the evidence **proves**
   from what you are **inferring**.
3. Whether any user data was lost, and where it can be recovered from. Check the
   trash before concluding anything is gone.
4. Whether it is likely to recur, and what would avoid or fix it.

Be straight about the limits of the evidence. If the cause is genuinely
ambiguous, say so rather than assembling confidence out of guesswork.

**Leave the system as you found it.** Diagnosis reads; it does not fix, tidy, or
reconfigure. The one thing to clean up is your own: delete the core you extracted
above, which is a copy of the crashed process's memory.

## If it is a Nixarchy or Omarchy bug

Most application crashes are upstream bugs in those applications, not the distribution's
doing. In the minority of cases where the cause really does sit within Nixarchy's or Omarchy's
sphere of control, read [`reporting.md`](reporting.md) before offering to file
anything.
