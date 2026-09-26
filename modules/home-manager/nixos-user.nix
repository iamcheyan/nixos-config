{ config, lib, pkgs, inputs, ... }:

let
  desktopPackage = pkgs.callPackage ../packages/desktop-compat.nix { };
  skillRoot = ../anchor-shell/compat/omarchy/default/agents/skills;
  skillNames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillRoot));
  skillFiles = lib.listToAttrs (lib.concatMap (name: map (prefix: {
    name = "${prefix}/${name}";
    value = { source = skillRoot + "/${name}"; force = true; };
  }) [ ".agents/skills" ".codex/skills" ".claude/skills" ".pi/agent/skills" ]) skillNames);

in

# User configuration that is specific to the locally managed NixOS desktop.
# Cross-platform application preferences remain managed by chezmoi.
{
  imports = [
    inputs.chatgpt-desktop-linux.homeManagerModules.default
    ./hyprland.nix
  ];

  home.stateVersion = "26.05";

  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    (pkgs.callPackage ../../packages/wind7z.nix { })
    # Wine (64-bit + WoW64, staging branch) and winetricks to run Windows-only
    # creative tools, currently the Photoshop CC v19 installer from
    # ~/development/photoshopCClinux-lightroom. winetricks takes wine from PATH.
    pkgs.wineWow64Packages.staging
    pkgs.winetricks
  ];

  # Keep the complete Omarchy plugin inventory with the NixOS/Home Manager
  # configuration.  The plugin checkouts themselves remain a separate Git
  # workspace because Omarchy updates them outside the Nix store.
  # Share one machine-specific environment brief across local coding agents.
  # These global instruction files are loaded regardless of the current
  # working directory; each client uses its own conventional filename.
  home.file = skillFiles // {
    ".config/omarchy/plugins.list" = {
      source = ./omarchy-plugins.list;
      force = true;
    };
  } // lib.genAttrs [
    ".config/agent/AGENTS.md"
    ".codex/AGENTS.md"
    ".claude/CLAUDE.md"
    ".gemini/GEMINI.md"
    ".config/opencode/AGENTS.md"
  ] (_: {
    source = ./agent-environment.md;
    # Replace the former chezmoi-managed links at these exact destinations.
    force = true;
  });


  # Install the official Linux ChatGPT/Codex desktop package declaratively.
  # The package includes its own Codex CLI runtime; no separate CLI install is
  # needed just to launch the desktop application.
  programs.codexDesktopLinux = {
    enable = true;
  };

  systemd.user.services.omarchy-theme-gnome = {
    Unit = { Description = "Apply desktop theme to GTK"; After = [ "graphical-session.target" ]; PartOf = [ "graphical-session.target" ]; };
    Service = {
      Type = "oneshot";
      Environment = [ "PATH=${desktopPackage}/bin:${pkgs.glib}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin" "OMARCHY_PATH=${desktopPackage}/share/omarchy" ];
      ExecStart = "${desktopPackage}/bin/omarchy-theme-set-gnome";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Seed only missing defaults; private chezmoi-owned preferences always win.
  home.activation.localDesktopSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/cp -rn --no-preserve=mode,ownership \
      "${desktopPackage}/share/omarchy/config/". "${config.xdg.configHome}/" || true
    run mkdir -p "${config.xdg.configHome}/btop/themes" "${config.xdg.configHome}/omarchy/branding" \
      "${config.home.homeDirectory}/.local/state/omarchy/current"
    if [ ! -e "${config.xdg.configHome}/btop/themes/current.theme" ]; then
      run ln -s "${config.home.homeDirectory}/.local/state/omarchy/current/theme/btop.theme" "${config.xdg.configHome}/btop/themes/current.theme"
    fi
    if [ ! -e "${config.home.homeDirectory}/.XCompose" ]; then
      echo 'include "/etc/omarchy/xcompose"' > "${config.home.homeDirectory}/.XCompose"
    fi
    if [ ! -e "${config.home.homeDirectory}/.local/state/omarchy/current/theme.name" ]; then
      run env OMARCHY_PATH="${desktopPackage}/share/omarchy" OMARCHY_THEME_HEADLESS=1 \
        PATH="${desktopPackage}/bin:/run/current-system/sw/bin:$PATH" \
        ${desktopPackage}/bin/omarchy-theme-set "tokyo-night" || true
    fi
  '';

  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
  };

  # KDE applications are used inside the Labwc session rather than inside
  # Plasma.  Keep the KDE platform plugin enabled and provide the settings
  # KDE normally writes from System Settings so Qt apps do not fall back to a
  # light palette or a missing icon theme.
  home.sessionVariables.QT_QPA_PLATFORMTHEME = "kde";
  xdg.configFile."kdeglobals".text = ''
    [ColorEffects:Disabled]
    ChangeSelectionColor=
    Color=56,56,56
    ColorAmount=0
    ColorEffect=0
    ContrastAmount=0.65
    ContrastEffect=1
    Enable=
    IntensityAmount=0.1
    IntensityEffect=2

    [ColorEffects:Inactive]
    ChangeSelectionColor=true
    Color=112,111,110
    ColorAmount=0.025
    ColorEffect=2
    ContrastAmount=0.1
    ContrastEffect=2
    Enable=false
    IntensityAmount=0
    IntensityEffect=0

    [Colors:Button]
    BackgroundAlternate=30,87,116
    BackgroundNormal=41,44,48
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=61,174,233
    ForegroundInactive=161,169,177
    ForegroundLink=29,153,243
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=252,252,252
    ForegroundPositive=39,174,96
    ForegroundVisited=155,89,182

    [Colors:Complementary]
    BackgroundAlternate=30,87,116
    BackgroundNormal=32,35,38
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=61,174,233
    ForegroundInactive=161,169,177
    ForegroundLink=29,153,243
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=252,252,252
    ForegroundPositive=39,174,96
    ForegroundVisited=155,89,182

    [Colors:Header]
    BackgroundAlternate=32,35,38
    BackgroundNormal=41,44,48
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=61,174,233
    ForegroundInactive=161,169,177
    ForegroundLink=29,153,243
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=252,252,252
    ForegroundPositive=39,174,96
    ForegroundVisited=155,89,182

    [Colors:Header][Inactive]
    BackgroundAlternate=41,44,48
    BackgroundNormal=32,35,38
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=61,174,233
    ForegroundInactive=161,169,177
    ForegroundLink=29,153,243
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=252,252,252
    ForegroundPositive=39,174,96
    ForegroundVisited=155,89,182

    [Colors:Selection]
    BackgroundAlternate=30,87,116
    BackgroundNormal=61,174,233
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=252,252,252
    ForegroundInactive=161,169,177
    ForegroundLink=253,188,75
    ForegroundNegative=176,55,69
    ForegroundNeutral=198,92,0
    ForegroundNormal=252,252,252
    ForegroundPositive=23,104,57
    ForegroundVisited=155,89,182

    [Colors:Tooltip]
    BackgroundAlternate=32,35,38
    BackgroundNormal=41,44,48
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=61,174,233
    ForegroundInactive=161,169,177
    ForegroundLink=29,153,243
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=252,252,252
    ForegroundPositive=39,174,96
    ForegroundVisited=155,89,182

    [Colors:View]
    BackgroundAlternate=29,31,34
    BackgroundNormal=20,22,24
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=61,174,233
    ForegroundInactive=161,169,177
    ForegroundLink=29,153,243
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=252,252,252
    ForegroundPositive=39,174,96
    ForegroundVisited=155,89,182

    [Colors:Window]
    BackgroundAlternate=41,44,48
    BackgroundNormal=32,35,38
    DecorationFocus=61,174,233
    DecorationHover=61,174,233
    ForegroundActive=61,174,233
    ForegroundInactive=161,169,177
    ForegroundLink=29,153,243
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=252,252,252
    ForegroundPositive=39,174,96
    ForegroundVisited=155,89,182

    [General]
    ColorScheme=BreezeDark
    ColorSchemeHash=2c3f86428c11011a7c64ee1e7f47c274d498ff10

    [Icons]
    Theme=breeze-dark

    [KDE]
    LookAndFeelPackage=org.kde.breezedark.desktop
    AnimationDurationFactor=0
    contrast=4
    frameContrast=0.2
    widgetStyle=Breeze

    [WM]
    activeBackground=39,44,49
    activeBlend=252,252,252
    activeForeground=252,252,252
    inactiveBackground=32,36,40
    inactiveBlend=161,169,177
    inactiveForeground=161,169,177
  '';

  # Use the Pop!_OS-style application icons across GTK applications.
  gtk = {
    enable = true;
    iconTheme = {
      package = pkgs.pop-icon-theme;
      name = "Pop";
    };
  };
}
