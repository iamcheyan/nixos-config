{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/keyd.nix
    ../../modules/desktop.nix
    ../../modules/zsh.nix
    ../../modules/cli.nix
    ../../modules/dev.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "hx90";
  time.timeZone = "Asia/Tokyo";

  # Disk hibernation: this host has a 68.4 GiB NVMe swap partition (UUID from
  # hardware-configuration.nix) and ~62 GiB RAM. NixOS does not wire resume=
  # from swapDevices alone.
  boot.resumeDevice = "/dev/disk/by-uuid/8123e3f3-db0c-4d51-b48e-b1239eaad003";

  # Keep lid/power-button suspend. Do not auto-sleep on idle.
  services.logind.settings.Login = {
    IdleAction = "ignore";
    HandleLidSwitch = "suspend";
    HandlePowerKey = "suspend";
    HandleSuspendKey = "suspend";
  };

  # ACPI S4 poweroff fails on this firmware: xhci 0000:04:00.4 returns EBUSY
  # (-16), USB resets count as a wakeup, and the kernel rolls the image back.
  # After the snapshot is on disk, do a normal poweroff instead of S4.
  systemd.sleep.settings.Sleep = {
    HibernateMode = "shutdown";
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

  home-manager.users.tetsuya = { config, pkgs, lib, ... }: {
    imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];
    home.stateVersion = "26.05";
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
    programs.nixarchy.enable = true;

    # Disable nixarchy automatic cursor override
    xdg.configFile."omarchy/hooks/theme-set.d/cursor".enable = lib.mkForce false;
    systemd.user.services.omarchy-theme-gnome.Service.ExecStart = lib.mkForce [
      "${config.programs.nixarchy.package}/bin/omarchy-theme-set-gnome"
    ];

    # Set default cursor (Adwaita)
    home.pointerCursor = {
      gtk.enable = true;
      x11.enable = true;
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
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
