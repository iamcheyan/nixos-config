{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/desktop.nix
    ../../modules/keyd.nix
    ../../modules/zsh.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.users.tetsuya = {
    imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];
    home.stateVersion = "26.05";
    programs.nixarchy.enable = true;
  };

  networking.hostName = "nixos-new";
  time.timeZone = "Asia/Tokyo";

  # The machine has a 16.5 GiB swap partition and supports disk hibernation.
  boot.resumeDevice = "/dev/disk/by-uuid/6b64ecf8-2317-4e9b-af61-6eda9451ab01";

  # Keep lid/power-button suspend behavior. Disable only unattended idle
  # suspend until this firmware's s2idle resume behavior is proven reliable.
  services.logind.settings.Login = {
    IdleAction = "ignore";
    HandleLidSwitch = "suspend";
    HandlePowerKey = "suspend";
    HandleSuspendKey = "suspend";
  };

  # Hibernation vs zram: pages swapped into zram live in RAM, so the
  # hibernation snapshot must include them AND still find enough free pages
  # for the atomic copy — on a 14G machine with zram loaded this fails with
  # ENOMEM ("Failed to put system to sleep ... Cannot allocate memory") and
  # the system thaws back. Flush zram to the NVMe resume swap and request the
  # smallest possible image before hibernating; restore both after resume.
  # Suspend-to-RAM is unaffected.
  environment.etc."systemd/system-sleep/10-hibernate-zram.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # systemd-sleep calls hooks as: <script> pre|post suspend|hibernate
      [ "$2" = "hibernate" ] || exit 0
      case "$1" in
        pre)
          # Smallest possible image: kernel drops reclaimable caches first.
          echo 0 > /sys/power/image_size 2>/dev/null
          # Move zram contents to the disk swap (the resume device) so they
          # leave RAM entirely instead of ballooning the snapshot.
          swapoff /dev/zram0 || true
          ;;
        post)
          # Restore the kernel default image_size (2/5 of RAM).
          echo $(( $(awk '/MemTotal/{print $2}' /proc/meminfo) * 1024 * 2 / 5 )) > /sys/power/image_size 2>/dev/null
          # Re-run zram-generator's setup so the swap comes back exactly as
          # configured (a bare `swapon` would lose the priority=100 setting
          # and end up level with the disk swap). The device must be reset
          # first — after swapoff it stays initialized and reconfiguration
          # fails with EBUSY.
          echo 1 > /sys/block/zram0/reset 2>/dev/null
          systemctl restart systemd-zram-setup@zram0.service
          ;;
      esac
    '';
  };

  # Local rollback points for the system and user data subvolumes. These are
  # not a replacement for an encrypted NAS backup.
  services.snapper.configs = {
    root = {
      SUBVOLUME = "/";
      ALLOW_USERS = [ "tetsuya" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      NUMBER_CLEANUP = true;
      NUMBER_MIN_AGE = 1800;
      NUMBER_LIMIT = 10;
      TIMELINE_LIMIT_HOURLY = 6;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 6;
      TIMELINE_LIMIT_YEARLY = 0;
    };
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "tetsuya" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      NUMBER_CLEANUP = true;
      NUMBER_MIN_AGE = 1800;
      NUMBER_LIMIT = 10;
      TIMELINE_LIMIT_HOURLY = 6;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 6;
      TIMELINE_LIMIT_YEARLY = 0;
    };
  };

  users.users.tetsuya = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "tetsuya";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" "docker" ];
  };

  # Windows VM tooling (sumika windows-vm extension): docker backend for the
  # VM provisioning helper, freerdp for the RDP client, cifs-utils for SMB
  # mounts used by the file-backup (musubi) polkit path.
  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    btrfs-progs
    restic
    snapper
    freerdp
    cifs-utils
    docker-compose
  ];

  system.stateVersion = "26.05";
}
