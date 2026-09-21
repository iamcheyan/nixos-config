# Runtime troubleshooting

## Missing clipboard theme state

The clipboard panel reads the optional generated theme state from:

```text
~/.local/state/omarchy/clipboard-theme.json
```

On a fresh installation, after a theme change, or before the theme hook has
created the file, Quickshell may log a `FileView` warning that the file does
not exist. This is expected and cosmetic. The panel uses its built-in colors
until the state file becomes available.

Do not create a fake file just to silence the warning. To refresh the real
theme state, switch the Omarchy theme normally and let the theme hook generate
the file. The clipboard history itself does not depend on this optional file.

Useful checks:

```sh
test -f ~/.local/state/omarchy/clipboard-theme.json
omarchy theme current
journalctl --user -b --no-pager | rg 'clipboard-theme|iamcheyan.clipboard'
```
