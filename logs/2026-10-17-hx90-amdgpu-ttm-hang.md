# hx90: amdgpu/ttm deadlock, desktop frozen (2026-10-17)

A hang of the whole machine, caught and recorded while it was still up. The
raw kernel log of the incident is beside this file:
[`2026-10-17-hx90-amdgpu-ttm-hang.log`](2026-10-17-hx90-amdgpu-ttm-hang.log)
(`dmesg --ctime`, 3165 lines; it holds no addresses, MACs, UUIDs or user names
beyond the hostname).

## What was seen

- The desktop stopped responding entirely; the machine stayed reachable over
  SSH now and then, one command at a time.
- 16 CPUs; load average rose 29 → 54 over the incident; 23 GiB of swap in use;
  dozens of processes in `D` state.
- Two `kworker` threads (`u65:8+ttm`, `u64:69+events_unbound`) sat at ~95 % CPU.

## Root cause

A kernel-side deadlock in the AMD display path, not a hung application. The
first traces name a GPU client closing its DRM file descriptor, and the block
that never returns is the atomic-commit workqueue:

```
amdgpu_driver_postclose_kms      [amdgpu]
amdgpu_drm_release               [amdgpu]
…
commit_tail
amdgpu_dm_atomic_commit_tail     [amdgpu]
drm_atomic_helper_cleanup_planes
amdgpu_dm_plane_helper_cleanup_fb [amdgpu]
amdgpu_bo_unpin                  [amdgpu]
ttm_bo_unpin                     [ttm]
_raw_spin_lock
native_queued_spin_lock_slowpath   ← spinning here
process_one_work → worker_thread → kthread
```

The worker spins on a queued spinlock inside `ttm_bo_unpin` with interrupts
affected, so it never finishes the commit; every other task that needs the
same DRM object or the console then waits on it: `Hyprland`, `kitty`,
`CanvasRenderer`, `Renderer`, `Cindy`, `codex app-server`, `NetworkManager`,
`snapperd`, `khugepaged`, even `systemd` (pid 1 in `D`).

Consequences in the log:

- 35 × `watchdog: BUG: soft lockup` — single tasks stuck for 44 s up to 130 s.
- 6 × `rcu: INFO: rcu_preempt self-detected stall` (and one expedited stall on
  five CPUs at once).
- Kernel taint `DIE` + `SOFTLOCKUP`, kernel `7.2.3 #1-NixOS PREEMPT(lazy)`.
- **No** `amdgpu: GPU reset`, ring timeout or page fault was ever logged: the
  driver did not detect the hang, so it never tried to recover.

Hardware, from the same log: Minisforum HX90, AMD Cezanne iGPU
(`1002:1638`, Radeon Vega), BIOS 5.19 (2021-10-11). Uptime at the hang:
11 h 41 m; heavy desktop session (Hyprland, Firefox, Electron apps) with 23 GiB
swapped out.

## Why a normal restart did not work

- `systemctl reboot` → `Failed to start reboot.target: Transport endpoint is not
  connected`: systemd itself was in `D` state, D-Bus gone.
- `/sbin/reboot -f` and a SysRq `b` write did not take effect: with PID 1 and
  the machine's shells wedged, the command could not be scheduled reliably.
- Only a hard power cycle (hold the power button) recovered the machine.

## What to change

1. **Pin the kernel off `linuxPackages_latest`.** `modules/workstation.nix`
   sets `boot.kernelPackages = pkgs.linuxPackages_latest` (and
   `modules/desktop-runtime.nix` defaults to it), which is 7.2.3 here —
   a very new kernel on a Cezanne iGPU. `ttm_bo_unpin` deadlocking in
   `amdgpu_dm_atomic_commit_tail` is a driver bug, not a configuration
   mistake; the practical fix is a kernel series known to be stable on this
   GPU (6.12 LTS), and to follow up on the upstream report instead of tracking
   `latest` on the one machine that must stay usable.
2. **Do not expect GPU recovery to help.** No reset was attempted; adding
   `amdgpu.gpu_recovery=1` would not unwedge a spinlock held with interrupts
   affected.
3. **If it recurs on LTS**, try `amdgpu.dcdebugmask=0x10` (disable PSR) as the
   next experiment, and capture the same `dmesg` evidence before touching the
   machine further.
4. **Watch the swap.** 23 GiB of swap in use on a 62 GiB machine is not the
   cause of this deadlock, but it makes every stall far worse and hides which
   process is at fault.

## Timeline (JST)

| Time | Event |
|---|---|
| 09:34 | boot (uptime 11 h 41 m at the hang) |
| 21:17:35 | first `amdgpu_driver_postclose_kms` / `amdgpu_drm_release` traces |
| 21:18:02 | first soft lockups (`kworker/u65:8`, `kworker/u64:69`) |
| 21:18:10 | RCU self-detected stall; further soft lockups follow |
| 21:19–21:20 | soft lockups reach 130 s; the log ends around 21:20:31 |
| 21:30–21:35 | `systemctl reboot`, `reboot -f` and SysRq all fail; machine still up, load 54 |
