{ config, lib, pkgs, ... }:

let
  nixosUpdate = pkgs.writeShellApplication {
    name = "nixos-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.git
      pkgs.jq
      pkgs.nix
      pkgs.nixos-rebuild
      pkgs.snapper
      pkgs.systemd
      config.programs.nixarchy.package
    ];
    text = builtins.readFile ../scripts/nixos-update.sh;
  };
in
{
  services.snapper = {
    snapshotRootOnBoot = false;
    persistentTimer = false;
    configs = {
      root = {
        SUBVOLUME = "/";
        FSTYPE = "btrfs";
        ALLOW_USERS = [ "tetsuya" ];
        TIMELINE_CREATE = false;
        TIMELINE_CLEANUP = false;
        NUMBER_CLEANUP = true;
        NUMBER_LIMIT = 10;
        NUMBER_LIMIT_IMPORTANT = 5;
      };
      home = {
        SUBVOLUME = "/home";
        FSTYPE = "btrfs";
        ALLOW_USERS = [ "tetsuya" ];
        TIMELINE_CREATE = false;
        TIMELINE_CLEANUP = false;
        NUMBER_CLEANUP = true;
        NUMBER_LIMIT = 10;
        NUMBER_LIMIT_IMPORTANT = 5;
      };
    };
  };

  environment.systemPackages = [ nixosUpdate ];

  # Snapper requires a .snapshots subvolume below every configured subvolume.
  # Create it once during activation; refuse to hide an ordinary directory.
  system.activationScripts.snapper-subvolumes = {
    text = ''
      ensure_snapshots_subvolume() {
        subvolume="$1"
        snapshots="$subvolume/.snapshots"
        if ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$snapshots" >/dev/null 2>&1; then
          return 0
        fi
        if [ -e "$snapshots" ]; then
          echo "Refusing to use existing non-subvolume path: $snapshots" >&2
          exit 1
        fi
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create "$snapshots"
        chmod 0750 "$snapshots"
      }
      ensure_snapshots_subvolume /
      ensure_snapshots_subvolume /home
    '';
  };
}
