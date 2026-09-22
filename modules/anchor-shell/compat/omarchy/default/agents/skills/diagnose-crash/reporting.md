# Reporting a Crash to Nixarchy or Omarchy

Read this only after concluding that a crash is genuinely the distribution's to fix. Two projects can own it: Nixarchy (<https://github.com/olafkfreund/nixarchy>) for anything specific to NixOS — the store, a rebuild, `nixarchy-apply`, a hardcoded `/usr` path, a replaced `omarchy-*` command — and Omarchy (<https://github.com/basecamp/omarchy>) for anything that would happen identically on Arch. When unsure, file against Nixarchy; the `nixarchy` skill's `contributing.md` has the full rule.

## Is it even the distribution's bug?

Be strict here. Omarchy is a configuration layer and Nixarchy packages it for NixOS, so a crash
inside a third-party application — a file manager, a browser, a GNOME or Qt
library — is almost always an upstream bug in **that** project, not in Omarchy.

The distribution's sphere of control is roughly the list below. Nixarchy owns the NixOS half of each line -- how the thing is packaged, seeded and exposed on NixOS -- and Omarchy owns the behaviour itself:

- the `omarchy-*` commands
- the Quickshell shell and its plugins
- the Hyprland and terminal configuration it ships
- its themes
- its install and migration scripts
- how it packages and configures what it installs

A crash in a program the distribution merely installs is **not** its bug unless
Nixarchy's or Omarchy's own packaging or configuration is implicated.

If it belongs to neither, say so and stop. Suggesting the right upstream project is
useful; filing there yourself is not part of this.

## Three conditions, all required

1. **It is a verified bug in Nixarchy's or Omarchy's sphere**, established on evidence. Issues
   are for verified bugs only. An "is this even a bug?" belongs on the Discord at
   <https://omarchy.org/discord>; a feature idea belongs in GitHub Discussions
   under Suggestions.
2. **The user has explicitly agreed.** Show them the exact title and body you
   propose, and wait for a yes. Never file unprompted.
3. **The machine can file it** — `gh auth status` must succeed. If `gh` is missing
   or unauthenticated, do not install or authenticate it. Say so, and hand the
   user the finished text to submit themselves.

## Search before filing

A duplicate issue costs a maintainer more time than no report at all.

```bash
gh search issues --repo olafkfreund/nixarchy "<program> crash"
gh issue list --repo olafkfreund/nixarchy --state all --search "<signal> <program>"
```

Search on the crashing program, the signal, and distinctive symbols from the
backtrace — not on the wording of the title you were about to write.

`gh search issues` accepts only `open` or `closed` for `--state`, and errors on
anything else. Leaving it off searches both, which is what you want here.

### And the agent room, when this machine is on it

A crash somebody has already diagnosed is likelier to be a fresh message in
`#nixarchy-agents` than a filed issue: the room is where an agent goes while
still confused; the issue is what exists afterwards, if anyone got that far.
Only if the agent bus is already configured here -- the `mcp__agent-bus__*`
tools exist -- search it with the same signals: the program, the signal,
distinctive symbols from the backtrace, never the wording of the title you
were about to write:

    search(query="<program> <signal> <symbol>", room="#nixarchy-agents")

No bus means no step: do not stop to set it up mid-diagnosis, and do not send
the user to do so. The GitHub search above stands on its own.

Include **closed** issues. A matching issue closed as fixed, when the crash still
reproduces on a current system, is a regression — and reporting that is worth far
more than another duplicate.

## Adding to an existing report

If a plausible match comes back, read it properly first:

```bash
gh issue view <number> --repo olafkfreund/nixarchy --comments
```

Confirm it is genuinely the same failure. The same program crashing is not the
same bug if the trigger or the stack differs.

If it is the same, add to that issue rather than opening a new one — but only
when you have something the thread does not already contain: a different
reproduction, a symbolized stack where it has none, a narrower trigger, a version
where it regressed.

A comment that only says the bug happens to you too is noise. If that is all you
have, tell the user so and file nothing.

```bash
gh issue comment <number> --repo olafkfreund/nixarchy --body "..."
```

## Filing a new issue

Only when the search turns up nothing that matches:

```bash
gh issue create --repo olafkfreund/nixarchy --title "..." --body "..."
```

Include what happened, what was expected, steps to reproduce, `nixos-version` and the locked inputs from `nix flake metadata`, system details from
`omarchy version`, and diagnostics from `omarchy debug --no-sudo --print` (which
also writes `/tmp/omarchy-debug.log`; the interactive `omarchy debug` can upload
it and print a shareable URL worth including).

`gh` cannot attach media. If a screenshot would help, save one and give the user
the path to drag into the web form.

## Close the loop in the agent room

Only if the bus is configured, and whichever way the diagnosis went:

- Filed or commented: post the issue link and a one-line summary to
  `#nixarchy-agents`. That closes the loop for anyone who searched the room
  five minutes earlier and found nothing.
- Ruled out as upstream: post "ruled out: upstream in <project>" and the
  one-line reason. The dead end is exactly what the room exists to record;
  the next agent to meet the same backtrace gets the answer for free.

What goes in that post is the conclusion, never the material. A backtrace, a
coredumpctl dump or a journalctl excerpt is precisely the content most likely
to carry paths, hostnames, usernames, environment variables and occasionally
a token -- and the room is public, permanent and undeletable. Post the
program, the signal, at most a symbol name or two, the verdict and the link;
paste nothing you have not read in full, and when in doubt post the link and
nothing else. The full redaction table is share/agent-bus/SKILL.md in the
nixarchy repository, and its hooks/bus-redact.sh blocks the decidable part
mechanically where installed.

## Signing

End the issue or comment with a line naming the model and agent harness that
produced it, so a human reader knows it was machine-authored:

> Filed by \<model name\> via \<agent harness\>.

Use your actual model and harness names. If you are not certain of them, say so
plainly rather than inventing a version string.
