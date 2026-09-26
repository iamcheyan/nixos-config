{ config, lib, pkgs, inputs, ... }:

let
  # Keep the Home Manager package identical to the system package. Nixarchy
  # v4.0.2-4's embedded Python check needs the same indentation compatibility
  # fix on both module paths.
  nixarchyPackage = import ../packages/nixarchy-omarchy.nix {
    inherit lib pkgs inputs;
  };
in

# User configuration that is specific to the NixOS + Nixarchy environment.
# Cross-platform application preferences remain managed by chezmoi.
{
  imports = [
    inputs.nixarchy.homeManagerModules.nixarchy
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
  home.file.".config/omarchy/plugins.list" = {
    source = ./omarchy-plugins.list;
    force = true;
  };

  programs.nixarchy = {
    enable = true;
    package = nixarchyPackage;
  };

  # Install the official Linux ChatGPT/Codex desktop package declaratively.
  # The package includes its own Codex CLI runtime; no separate CLI install is
  # needed just to launch the desktop application.
  programs.codexDesktopLinux = {
    enable = true;
  };

  # Nixarchy owns the Omarchy/NixOS integration. Keep its generated user
  # service declarative and prevent the upstream cursor hook from overriding
  # the Home Manager cursor selection.
  xdg.configFile."omarchy/hooks/theme-set.d/cursor".enable = lib.mkForce false;
  systemd.user.services.omarchy-theme-gnome.Service.ExecStart = lib.mkForce [
    "${config.programs.nixarchy.package}/bin/omarchy-theme-set-gnome"
  ];

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
