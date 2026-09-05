{ config, lib, pkgs, inputs, ... }:

# User configuration that is specific to the NixOS + Nixarchy environment.
# Cross-platform application preferences remain managed by chezmoi.
{
  imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];

  home.stateVersion = "26.05";

  programs.nixarchy.enable = true;

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
