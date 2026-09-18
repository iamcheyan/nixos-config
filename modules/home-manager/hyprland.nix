{ config, hostName ? "unknown", lib, ... }:

let
  # Hyprland uses XKB names.  Keep the choice with the host configuration so
  # the same Home Manager module can be reused by other NixOS workstations.
  kbLayout = {
    hx90 = "jp";
  }.${hostName} or "us";

  inputSource = builtins.readFile ./hypr/input.lua;
  inputWithLayout = lib.replaceStrings
    [ "input = {\n    kb_options = \"compose:caps\",\n  }" ]
    [ "input = {\n    kb_layout = \"${kbLayout}\",\n    kb_options = \"compose:caps\",\n  }" ]
    inputSource;
in
{
  # The complete Hyprland user directory is now owned by Home Manager.  Keep
  # the source files in this repository; only input.lua is rendered per host.
  home.file = {
    ".config/hypr/README.md" = { source = ./hypr/README.md; force = true; };
    ".config/hypr/autostart.lua" = { source = ./hypr/autostart.lua; force = true; };
    ".config/hypr/bindings.lua" = { source = ./hypr/bindings.lua; force = true; };
    ".config/hypr/bindings.lua.bak.overview-interrupt-cleanup-1788595221" = {
      source = ./hypr/bindings.lua.bak.overview-interrupt-cleanup-1788595221;
      force = true;
    };
    ".config/hypr/hyprland.lua" = { source = ./hypr/hyprland.lua; force = true; };
    ".config/hypr/hyprsunset.conf" = { source = ./hypr/hyprsunset.conf; force = true; };
    ".config/hypr/input.lua" = { text = inputWithLayout; force = true; };
    ".config/hypr/looknfeel.lua" = { source = ./hypr/looknfeel.lua; force = true; };
    ".config/hypr/xdph.conf" = { source = ./hypr/xdph.conf; force = true; };
  };
}
