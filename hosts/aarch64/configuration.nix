{ lib, localRoot ? "", ... }:

let
  localHost = if localRoot != "" then "${localRoot}/hosts/aarch64.nix" else null;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/workstation.nix
  ] ++ lib.optional (localHost != null && builtins.pathExists localHost) localHost;

  networking.hostName = "aarch64";

  services.spice-vdagentd.enable = true;
  services.qemuGuest.enable = true;

  system.stateVersion = "26.05";
}
