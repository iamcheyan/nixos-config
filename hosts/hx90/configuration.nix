{ config, lib, pkgs, localRoot ? "", ... }:

let
  localHost = if localRoot != "" then "${localRoot}/hosts/hx90.nix" else null;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../mir2ei.nix
    ../../modules/workstation.nix
    ../../modules/update-snapshots.nix
    ../../inux.nix
    ./apps.nix
    ../../modules/devenv.nix
    ../../modules/inua-windows-vm.nix
  ] ++ lib.optional (localHost != null && builtins.pathExists localHost) localHost;

  # Windows VM support for the Inua session (HX90 test host): Docker for the
  # Dockur container, FreeRDP to connect, and the QEMU utilities the doctor
  # uses. tetsuya gets Docker socket access, which is root-equivalent; remove
  # this before distributing the machine's configuration.
  services.inuaWindowsVm = {
    enable = true;
    dockerUsers = [ "tetsuya" ];
  };

  networking.hostName = "hx90";

  # Tailscale mesh VPN; authentication is performed after activation.
  services.tailscale = {
    enable = true;
    # Keep the daemon's Tailscale SSH server preference enabled on activation.
    extraSetFlags = [ "--ssh" ];
  };
  services.flatpak.enable = true;
  services.syncthing = {
    enable = true;
    user = "tetsuya";
    group = "users";
    dataDir = "/home/tetsuya";
    configDir = "/home/tetsuya/.local/state/syncthing";
    openDefaultPorts = false;
    settings = {
      devices.debian = {
        id = "A43UXGE-Q2NW3JR-AWKZZNG-LAKZGYW-VGBLPA2-TYB6MIA-S5WHR75-VSKTKAK";
        addresses = [ "tcp://192.168.3.82:22000" ];
      };
      folders = {
        "mir2ei-client" = {
          id = "mir2ei-client";
          label = "Mir2EI client — Debian source";
          path = "/home/tetsuya/mir2ei";
          type = "receiveonly";
          devices = [ "debian" ];
        };
        "mir2ei-webdata" = {
          id = "mir2ei-webdata";
          label = "Mir2EI WebData — Debian source";
          path = "/home/tetsuya/mir2ei-webdata";
          type = "receiveonly";
          devices = [ "debian" ];
        };
      };
      options.listenAddresses = [ "tcp://0.0.0.0:22000" ];
    };
  };
  environment.sessionVariables.XDG_DATA_DIRS = [
    "/home/tetsuya/.local/share/flatpak/exports/share"
    "/var/lib/flatpak/exports/share"
  ];

  # Labwc is HX90's normal desktop session. This also selects Labwc for SDDM
  # autologin, so restarting the display manager does not launch Omarchy first.
  services.displayManager.defaultSession = lib.mkForce "labwc";
  programs.labwcPreview.enable = true;

  # Keep the Hermes remote API peer available when the user is logged out.
  users.users.tetsuya.linger = true;

  environment.systemPackages = with pkgs; [
    curl
    ffmpeg
    git
    google-chrome
    microsoft-edge
    vscode
    nodejs_24
    (pkgs.callPackage ../../modules/packages/ai-usagebar.nix { })
    (pkgs.callPackage ../../modules/packages/cindy.nix { })
    ripgrep
    tigervnc
    xz
  ];


  # Install Furigana Maker from the Chrome Web Store for every Chrome profile.
  environment.etc."opt/chrome/policies/managed/furigana-maker.json".text = builtins.toJSON {
    ExtensionSettings.heodojceeinbkfjfilnfminlkgbacpfp = {
      installation_mode = "force_installed";
      update_url = "https://clients2.google.com/service/update2/crx";
    };
  };

  # The peer is bound to this host's LAN address; only the local subnet may
  # connect to TCP/8377 and the Syncthing data port.
  networking.firewall.extraCommands = ''
    iptables -w -A nixos-fw -s 192.168.3.0/24 -p tcp --dport 8377 -j nixos-fw-accept
    iptables -w -A nixos-fw -s 192.168.3.0/24 -p tcp --dport 22000 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -w -D nixos-fw -s 192.168.3.0/24 -p tcp --dport 8377 -j nixos-fw-accept 2>/dev/null || true
    iptables -w -D nixos-fw -s 192.168.3.0/24 -p tcp --dport 22000 -j nixos-fw-accept 2>/dev/null || true
  '';

  # Flux negotiates its TCP listener on one port in this range and uses UDP
  # 1716 for discovery. Permit those connections from the home LAN and the
  # Tailscale interface only; do not expose the phone-link service on every
  # network interface.
  networking.firewall.interfaces."wlp3s0" = {
    allowedTCPPortRanges = [ { from = 1716; to = 1764; } ];
    allowedUDPPorts = [ 1716 ];
  };
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPortRanges = [ { from = 1716; to = 1764; } ];
    allowedUDPPorts = [ 1716 ];
  };
  systemd.tmpfiles.rules = [ "d /home/tetsuya/mir2ei-webdata 0750 tetsuya users -" ];

  home-manager.users.tetsuya = { ... }: {
    xdg.desktopEntries.code = {
      name = "Visual Studio Code";
      genericName = "Text Editor";
      comment = "Code Editing. Redefined.";
      exec = "${pkgs.vscode}/bin/code --ozone-platform=wayland %F";
      icon = "vscode";
      terminal = false;
      categories = [ "Utility" "TextEditor" "Development" "IDE" ];
      mimeType = [ "text/plain" ];
      settings = {
        StartupWMClass = "Code";
        StartupNotify = "true";
      };
    };
  };

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

  # Low-latency remote desktop/game streaming for macOS Moonlight clients.
  # Auto-login is intentional: this is a privately owned workstation and the
  # remote desktop must have a graphical session available after boot.
  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true;
    capSysAdmin = true;
  };
  services.displayManager.autoLogin = {
    enable = false;
    user = "tetsuya";
  };

  # Keep suspend modes disabled while this workstation is being used remotely,
  # but allow an explicit disk hibernation from the local power menu.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "yes";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
    # ACPI S4 poweroff fails on this firmware: xhci 0000:04:00.4 returns EBUSY
    # (-16), USB resets count as a wakeup, and the kernel rolls the image back.
    # After the snapshot is on disk, do a normal poweroff instead of S4.
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

  system.stateVersion = "26.05";
}
