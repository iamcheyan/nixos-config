# Labwc XWayland HiDPI patches

These pinned patches provide a compositor-wide integer XWayland scale for the
Labwc session. They are paired with XWayland 24.1.13 and wlroots 0.20.2 and are
kept out of Hyprland's package closure.

The patch set follows the Labwc HiDPI guide and its referenced AUR package
recipes:

- [Labwc HiDPI guide](https://labwc.github.io/hidpi-scaling.html)
- [Labwc patch/build guide](https://labwc.github.io/hidpi-scaling-patches.html)
- [XWayland 24.1.13 HiDPI patch recipe](https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=xorg-xwayland-hidpi-xprop)
- [wlroots 0.20.2 HiDPI patch recipe](https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=wlroots0.20-hidpi-xprop)

Labwc autostart sets `_XWAYLAND_GLOBAL_OUTPUT_SCALE` to `2`. This is one
global XWayland scale, so it makes legacy apps sharp on the 2x 4K output but
cannot give XWayland separate crisp scales on the 1x and 2x outputs at once.
Wayland-native clients remain unaffected.

The patch files are vendored so builds do not depend on a mutable AUR endpoint.
Their SHA-256 hashes are:

| Patch | SHA-256 |
|---|---|
| `xwayland-24.1.13-hidpi.patch` | `c00b014b2a74079da30b9f3a94358157a4d390bb90a84af78ee384bacf37193a` |
| `0001-revert-wl-surface-error-size.patch` | `0caf7a8d9170a0481a2c483a3440316347df544a98893a15f310a06895887822` |
| `0002-wlroots-xwayland-hidpi.patch` | `f281a894457157a2f863ccf99abbc4727286d611c665a62ea2eccba7e329048d` |
| `0003-wlroots-configure-notify.patch` | `498ea56153b7752d2ed275eda2d1906607355cd7db53a9ab0873129da743e809` |
| `0004-wlroots-size-hints.patch` | `7128352c28d0ee287a9388efca36a44dce1f4d3a5b5ca5b8557c117c6c829c8c` |
