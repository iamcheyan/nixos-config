{ config, lib, pkgs, inputs, ... }:

let
  # Keep the Home Manager package identical to the system package. Nixarchy
  # v4.0.2-4's embedded Python check needs the same indentation compatibility
  # fix on both module paths.
  nixarchyPackage = (pkgs.extend inputs.nixarchy.overlays.default).omarchy.overrideAttrs (old: {
    installPhase = lib.replaceStrings [ "\n            " ] [ "\n" ] old.installPhase;
  });
in

# User configuration that is specific to the NixOS + Nixarchy environment.
# Cross-platform application preferences remain managed by chezmoi.
{
  imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];

  home.stateVersion = "26.05";

  programs.nixarchy = {
    enable = true;
    package = nixarchyPackage;
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
}
