# Runtime troubleshooting

## Missing AccountsService avatar

If `/var/lib/AccountsService/icons/<username>` does not exist, Quickshell can
log a warning when it tries to load that first avatar candidate. This is
cosmetic: the lock screen continues through its fallback chain and eventually
shows `~/.face`, `~/.face.icon`, or the built-in Nerd Font avatar.

To provide a user avatar without AccountsService privileges:

```sh
cp your-avatar.png ~/.face
```

The fallback order is:

1. `/var/lib/AccountsService/icons/<username>`
2. `~/.face`
3. `~/.face.icon`
4. the built-in fallback icon

The lock screen must remain usable when all image candidates are missing. The
fallback icon is intentional and should not be replaced by a fatal image-load
error.

## Output and placeholder-screen safety

The custom lock screen deliberately keeps the active output alive while
`WlSessionLock` owns the surface. Turning off the only active output can create
a placeholder screen and destabilize the shell. The service records a
`blank-skipped: keep-output-alive` event instead of running a display-off
command.

Useful checks after changing the lock screen:

```sh
omarchy system lock
journalctl --user -b --no-pager | rg 'omarchy lock|placeholder screen|fatal|EGL'
```
