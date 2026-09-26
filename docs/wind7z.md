# Win7-Zip on NixOS

This document records how the Windows 7-Zip File Manager from
[iamcheyan/7z-for-Linux](https://github.com/iamcheyan/7z-for-Linux) is packaged,
integrated with the desktop, and adapted for Wine on this machine.

## Design

The upstream project is a Linux launcher around the Windows 7-Zip GUI. Its
published AppImage is about 331 MB. The AppImage's `AppRun` expects to download
a Wine AppImage on first launch and writes desktop entries and associations to
the user's home directory. Those runtime downloads and mutable desktop files do
not fit this repository's declarative NixOS setup.

Instead, this configuration fetches a pinned source snapshot, installs the
upstream Windows program files and resources, and runs `7zFM.exe` with the
system's `wineWow64Packages.stable`. Nix generates the launcher and desktop
entry. The package does not run the upstream `AppRun` script and does not need
FUSE or a mutable AppImage.

The package currently targets `x86_64-linux`. It includes the upstream `exe/`
tree, which contains `7zFM.exe`, the 7-Zip DLLs, language resources, and related
files. The release/source version recorded by the package is 7-Zip 24.08.

## Files and responsibilities

- [`packages/wind7z.nix`](../packages/wind7z.nix) pins the upstream Git revision
  and hash, installs its Windows files, generates the Wine wrapper and desktop
  entry, and imports the per-prefix registry configuration on launch.
- [`modules/home-manager/nixos-user.nix`](../modules/home-manager/nixos-user.nix)
  installs the package for the x86_64 Home Manager user.
- [`modules/workstation.nix`](../modules/workstation.nix) selects
  `wind7z.desktop` as the default handler for common archive MIME types.
- [`modules/fonts.nix`](../modules/fonts.nix) installs WenQuanYi Micro Hei as a
  system font. Wine's fontconfig integration can then find it from the prefix.

The package launcher is named `wind7z`; the registered desktop application ID
is `wind7z.desktop`.

## Launch and Wine prefix

The desktop entry launches the wrapper with the selected archive path. The
wrapper:

1. Uses `$HOME/.local/share/wineprefixes/wind7z` as its default `WINEPREFIX`,
   while honoring an explicitly supplied `WINEPREFIX`.
2. Imports `cjk-fonts.reg` into that prefix before starting the GUI.
3. Starts the pinned `exe/7zFM.exe` using NixOS's Wine package.

The prefix stores Wine's generated registry and user state outside the Nix
store. The executable, language files, registry template, and desktop entry
remain immutable in `/nix/store`.

The wrapper can also be launched from a terminal:

```bash
wind7z /path/to/archive.rar
```

## Archive associations

The Home Manager MIME defaults point these types to `wind7z.desktop`:

- 7z, ZIP, and RAR
- XZ, BZip/BZip2, and gzip
- tar and compressed tar

The default is declared in `modules/workstation.nix`; it is not written by the
upstream AppImage on first run. To inspect an association:

```bash
xdg-mime query default application/zip
xdg-mime query default application/x-7z-compressed
```

Both should return `wind7z.desktop` after Home Manager activation. RAR is
supported for opening and extraction; 7-Zip does not create RAR archives.

## Chinese language and fonts

The system already had Noto CJK fonts, but the first Wine prefix had Japanese
font/codepage defaults and the 7-Zip interface opened in Japanese. The package
now sets the 7-Zip language value to `zh-cn` and maps common Windows CJK font
names, including `MS Shell Dlg`, `MS UI Gothic`, `SimSun`, and `Microsoft YaHei`,
to WenQuanYi Micro Hei. The mapping is added both through Windows font
substitutions and Wine's font replacement registry so legacy controls can use
the installed Linux font.

WenQuanYi Micro Hei was added because it is a TrueType CJK screen font with
hinting that suits the small text sizes used by this older Win32 interface.
Noto CJK remains installed for the rest of the desktop.

### Font smoothing and size

Wine stores separate system font records for menus and dialog/message controls.
The options dialog and the main File Manager menu therefore need not look the
same even inside one process. In particular, changing the CJK fallback alone
does not change the menu's selected font, point size, or rendering quality.

The generated registry file applies these prefix-local settings:

- 120 DPI (`LogPixels` 120) for a modest increase over Wine's 96 DPI default.
- Wine/Windows font smoothing enabled with grayscale smoothing, gamma `0x578`,
  and RGB orientation.
- `WindowMetrics\MenuFont` set to WenQuanYi Micro Hei at a larger height with
  GDI antialias quality. The dialog's message font is left as a separate
  setting.

`MenuFont` is stored as a Windows `LOGFONTW` binary registry value. Its current
font height is `-14`, weight is 400, quality is 4 (antialiased), and face name
is `WenQuanYi Micro Hei`. Keeping this binary in the package template makes
the setting reproducible whenever the launcher starts.

These changes target the missing glyphs and the visibly small/rough menu text
without changing the dialog font configuration. They do not guarantee that the
main menu and dialog will look identical: Wine and 7-Zip can render individual
controls differently. Recheck the result after changing Wine, the font package,
or the display scale. The relevant Wine settings are read during process
startup, so close and reopen 7-Zip after changing them.

## Inspecting the current setup

```bash
# Confirm the CJK font resolves through fontconfig
fc-match 'WenQuanYi Micro Hei'

# Confirm the selected language and menu font in this prefix
WINEPREFIX="$HOME/.local/share/wineprefixes/wind7z" \
  wine reg query 'HKCU\Software\7-Zip' /v Lang
WINEPREFIX="$HOME/.local/share/wineprefixes/wind7z" \
  wine reg query 'HKCU\Control Panel\Desktop\WindowMetrics' /v MenuFont

# Confirm the launcher and MIME default
command -v wind7z
xdg-mime query default application/zip
```

Expected language is `zh-cn`, and the MIME handler is `wind7z.desktop`.

## Updating the upstream snapshot

The source revision and fixed-output hash in `packages/wind7z.nix` must be
updated together. For a new source commit:

1. Set `rev` to the exact upstream commit and update `version` to the bundled
   7-Zip version.
2. Recompute the unpacked source hash with `nix-prefetch-url --unpack` and set
   the returned hash in `fetchFromGitHub`.
3. Build the package and check that `exe/7zFM.exe`, the CJK language file, and
   any required DLLs are still present.
4. Open representative ZIP, 7z, and RAR archives and recheck the Chinese menu
   and dialog rendering after the Wine prefix has been updated.

Apply this machine's system configuration with:

```bash
nix flake check --no-build --impure
nixos-rebuild build --flake .#hx90 --impure
sudo nixos-rebuild switch --flake .#hx90 --impure
```
