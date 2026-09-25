# Applications available through the Omarchy menu, as NixOS configuration.
#
# Every app is listed and every line is commented out. Uncomment what you
# want -- or pick it from the menu, which uncomments it for you -- then run
#
#     nixarchy-apply
#
# to copy this into your flake and `nixos-rebuild switch`. Enable as many as
# you like before applying; nothing is built until you do.
#
# This file is yours. Nothing regenerates or overwrites it once created;
# the current full list is always at /etc/nixarchy/apps-template.nix.
#
# The `#@ name` markers are how the menu finds a line to uncomment. Keep
# them and you can reformat, reorder and annotate this file freely.
{ pkgs, ... }:
let
  # The locked nixpkgs QQ source URL was removed upstream (404). Pin the
  # currently published official x86_64 Debian package until nixpkgs updates.
  qqCurrent = pkgs.qq.overrideAttrs (old: {
    version = "3.2.32-2026-08-12";
    src = pkgs.fetchurl {
      name = "QQ_3.2.32_260812_amd64_01.deb";
      url = "https://qqdl.gtimg.cn/qqfile/QQNT/9.9.33/release/3f89efc5/QQ_3.2.32_260812_amd64_01.deb";
      hash = "sha256-0IXdiTlyJQYeufGUMI9ogSmBjtRFd36XpKChbhPXsOg=";
    };
  });
  # Tencent retired the fixed Linux AppImage URL archived by nixpkgs. Use the
  # unmodified official AppImage mirrored with a published SHA-256 checksum.
  wechatCurrent = pkgs.callPackage (pkgs.path + "/pkgs/by-name/we/wechat/linux.nix") {
    pname = "wechat";
    version = "4.1.1.8";
    meta = pkgs.wechat.meta;
    src = pkgs.fetchurl {
      name = "WeChatLinux_4.1.1.8_x86_64.AppImage";
      url = "https://github.com/trouter-ai/wechat-linux-versions/releases/download/v4.1.1.8/WeChatLinux_4.1.1.8_x86_64.AppImage";
      hash = "sha256-RX26ArkbAxzdRBLu4HT7v/udnQax5Q/Bgi00hw4RSZA=";
    };
  };
in
{
  programs.nixarchy.apps = {

  # ── Service ─────────────────────────────────────────────────────
    # _1password.enable = true;  #@ _1password  # unfree — Needs the module, not the package: unlocking requires a setuid helper that only programs._1password-gui installs. Set `settings.polkitPolicyOwners = [ "yourname" ]`.
    #   _1password.settings = { };  #@ _1password.settings
    # bitwarden.enable = true;  #@ bitwarden
    # dropbox.enable = true;  #@ dropbox  # unfree
    # nordvpn.enable = true;  #@ nordvpn  # unfree
    # once.enable = true;  #@ once
    # signal.enable = true;  #@ signal
    # spotify.enable = true;  #@ spotify  # unfree
    # tailscale.enable = true;  #@ tailscale  # A daemon. `settings.useRoutingFeatures = "client"` for exit nodes.
    #   tailscale.settings = { };  #@ tailscale.settings

  # ── Terminal ────────────────────────────────────────────────────
    # alacritty.enable = true;  #@ alacritty
    # foot.enable = true;  #@ foot
    # ghostty.enable = true;  #@ ghostty
    # kitty.enable = true;  #@ kitty

  # ── Browser ─────────────────────────────────────────────────────
    # brave.enable = true;  #@ brave
    # chrome.enable = true;  #@ chrome  # unfree
    # edge.enable = true;  #@ edge  # unfree
    # firefox.enable = true;  #@ firefox  # A NixOS module, so policies and extensions are declarative too.
    #   firefox.settings = { };  #@ firefox.settings
    # zen.enable = true;  #@ zen

  # ── Development ─────────────────────────────────────────────────
    # bun.enable = true;  #@ bun
    # clojure.enable = true;  #@ clojure
    # deno.enable = true;  #@ deno
    # dotnet.enable = true;  #@ dotnet
    # elixir.enable = true;  #@ elixir
    # go.enable = true;  #@ go  # mise use --global go@latest downloads a toolchain outside Nix. This is nixpkgs' go, rebuilt with the system.
    # java.enable = true;  #@ java
    # nodejs.enable = true;  #@ nodejs  # mise' prebuilt Node is dynamically linked against paths NixOS does not have, so it often will not execute at all. This one does.
    # ocaml.enable = true;  #@ ocaml
    # php.enable = true;  #@ php
    # python.enable = true;  #@ python  # Already on the system as a runtime dependency of Omarchy's own scripts, so this row shows dim on a stock install. Select it to say so in your configuration rather than relying on that.
    # rust.enable = true;  #@ rust  # rustup manages its own toolchains under ~/.rustup, the same as upstream. Use pkgs.cargo and pkgs.rustc instead if you would rather Nix pinned the compiler.
    # scala.enable = true;  #@ scala
    # symfony.enable = true;  #@ symfony  # unfree
    # zig.enable = true;  #@ zig

  # ── AI ──────────────────────────────────────────────────────────
    # chatgpt.enable = true;  #@ chatgpt  # unfree
    # dictation.enable = true;  #@ dictation
    # grok-bot.enable = true;  #@ grok-bot  # unfree
    # lm-studio.enable = true;  #@ lm-studio  # unfree
    # t3-code.enable = true;  #@ t3-code

  # ── Editor ──────────────────────────────────────────────────────
    # cursor.enable = true;  #@ cursor  # unfree
    # emacs.enable = true;  #@ emacs
    # helix.enable = true;  #@ helix
    # vim.enable = true;  #@ vim
    # vscode.enable = true;  #@ vscode  # unfree
    # zed.enable = true;  #@ zed

  # ── Gaming ──────────────────────────────────────────────────────
    # heroic.enable = true;  #@ heroic
    # lutris.enable = true;  #@ lutris
    # minecraft.enable = true;  #@ minecraft
    # retroarch.enable = true;  #@ retroarch  # Ships 13 free cores. For more -- including snes9x, genesis-plus-gx, mame and dolphin, which nixpkgs marks unfree -- set allowUnfree and override the package:   apps.retroarch.package =     pkgs.retroarch.withCores (c: [ c.snes9x c.mame c.dolphin ]);
    # steam.enable = true;  #@ steam  # unfree — A module, not a package: Steam needs an FHS wrapper to run at all.
    #   steam.settings = { };  #@ steam.settings
    # xbox-controllers.enable = true;  #@ xbox-controllers  # A kernel driver, so it is a hardware option rather than a package.
    #   xbox-controllers.settings = { };  #@ xbox-controllers.settings

  # ── Preinstalls ─────────────────────────────────────────────────
    # obsidian.enable = true;  #@ obsidian  # unfree — Preinstalled upstream, opt-in here because it is unfree. Theme syncing needs the Omarchy theme selected under Appearance > Themes in the app; omarchy-theme-set-obsidian writes it on every theme change.
  };

  # ── Extra packages ──────────────────────────────────────────────
  # Plain nixpkgs attributes, added by nixarchy-pkg-add. These are
  # not part of the curated app list above: the Omarchy menu does
  # not offer them and will not remove them. The file stays yours --
  # reformat and annotate freely, the tool only ever inserts one
  # line before the end marker.
  environment.systemPackages = with pkgs; [  #@pkgs-begin
    qqCurrent
    wechatCurrent
  ];  #@pkgs-end
}

# Offered by the Omarchy menu but with no nixpkgs equivalent:
#   Brave Origin — Brave's managed build is AUR-only with no published source; enable apps.brave and put policies in /etc/brave/policies/managed, which stock Brave honours identically.
#   Sublime Text — nixpkgs marks sublimetext4 broken over an insecure OpenSSL dependency; enabling it fails the rebuild.
