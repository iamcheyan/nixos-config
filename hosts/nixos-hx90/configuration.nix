{ config, lib, pkgs, inputs, localRoot ? "", ... }:

let
  localHost = if localRoot != "" then "${localRoot}/hosts/nixos-hx90.nix" else null;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/keyd.nix
    ../../modules/desktop.nix
    ../../modules/zsh.nix
    ../../modules/cli.nix
    ../../modules/dev.nix
    ../../modules/update-snapshots.nix
    inputs.home-manager.nixosModules.home-manager
  ] ++ lib.optional (localHost != null && builtins.pathExists localHost) localHost;

  home-manager.extraSpecialArgs = { inherit inputs; };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "hx90";
  time.timeZone = "Asia/Tokyo";

  # Disk hibernation: this host has a 68.4 GiB NVMe swap partition (UUID from
  # hardware-configuration.nix) and ~62 GiB RAM. NixOS does not wire resume=
  # from swapDevices alone.
  boot.resumeDevice = "/dev/disk/by-uuid/cfceef33-5044-4a72-8c01-c8d1f4444f00";

  # Keep lid/power-button suspend. Do not auto-sleep on idle.
  services.logind.settings.Login = {
    IdleAction = "ignore";
    HandleLidSwitch = "suspend";
    HandlePowerKey = "suspend";
    HandleSuspendKey = "suspend";
  };

  # Keep manual suspend/hibernation available, but do not trigger either one
  # automatically. The lid and power-button policy above controls that latter
  # behavior.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "yes";
    AllowHibernation = "yes";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
    # ACPI S4 poweroff fails on this firmware: xhci 0000:04:00.4 returns EBUSY
    # (-16), USB resets count as a wakeup, and the kernel rolls the image back.
    # After the snapshot is on disk, do a normal poweroff instead of S4.
    HibernateMode = "shutdown";
  };

  # Nixarchy's upstream menu uses an Arch/mkinitcpio-only hibernation marker.
  # Override that existing row declaratively so the option is visible on NixOS
  # when this host has a resume-capable swap device and boot configuration.
  programs.nixarchy.menu.extraEntries = {
    "system.hibernate" = {
      when = ''test -r /sys/power/image_size && awk 'NR > 1 && $1 !~ /zram/ && $3 > 0 { found = 1 } END { exit !found }' /proc/swaps && grep -q 'resume=' /run/current-system/kernel-params'';
      action = "systemctl hibernate";
    };
    "system.nixos-update" = {
      icon = "󰒓";
      label = "NixOS Update (Snapshot)";
      description = "Snapshot / and /home, update plugins and NixOS";
      action = "nixos-update";
    };
  };

  # zram pages live in RAM. Flush them to the NVMe resume swap before the
  # hibernation snapshot. systemd-sleep's PATH has no awk, so parse meminfo
  # in pure shell and use store paths for swapoff/systemctl.
  environment.etc."systemd/system-sleep/10-hibernate-zram.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # systemd-sleep calls hooks as: <script> pre|post suspend|hibernate
      [ "$2" = "hibernate" ] || exit 0
      case "$1" in
        pre)
          echo 0 > /sys/power/image_size 2>/dev/null || true
          for f in /sys/bus/usb/devices/*/power/wakeup /sys/bus/pci/devices/*/power/wakeup; do
            echo disabled > "$f" 2>/dev/null || true
          done
          ${pkgs.util-linux}/bin/swapoff /dev/zram0 || true
          ;;
        post)
          mem_kb=0
          while read -r key val _; do
            if [ "$key" = "MemTotal:" ]; then
              mem_kb=$val
              break
            fi
          done < /proc/meminfo
          if [ -n "$mem_kb" ] && [ "$mem_kb" -gt 0 ]; then
            echo $(( mem_kb * 1024 * 2 / 5 )) > /sys/power/image_size 2>/dev/null || true
          fi
          echo 1 > /sys/block/zram0/reset 2>/dev/null || true
          ${pkgs.systemd}/bin/systemctl restart systemd-zram-setup@zram0.service || true
          ;;
      esac
    '';
  };

  home-manager.users.tetsuya = { ... }: {
    imports = [ ../../modules/home-manager/nixos-user.nix ];
    home.sessionVariables.BROWSER = "firefox";
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = [ "firefox.desktop" ];
        "x-scheme-handler/http" = [ "firefox.desktop" ];
        "x-scheme-handler/https" = [ "firefox.desktop" ];
        "x-scheme-handler/about" = [ "firefox.desktop" ];
        "x-scheme-handler/unknown" = [ "firefox.desktop" ];
      };
    };
  };

  users.users.tetsuya = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "tetsuya";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" ];
  };

  environment.systemPackages = with pkgs; [
    spice-vdagent
  ];

  system.stateVersion = "26.05";
}
