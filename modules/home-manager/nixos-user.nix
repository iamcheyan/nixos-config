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

  # Use the Pop!_OS-style application icons across GTK applications.
  gtk = {
    enable = true;
    iconTheme = {
      package = pkgs.pop-icon-theme;
      name = "Pop";
    };
  };
}
