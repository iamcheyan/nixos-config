{ config, pkgs, ... }:

{
  # 1. Ensure keyd is installed as a system package so command-line scripts can call it
  environment.systemPackages = with pkgs; [
    keyd
  ];

  # 2. Enable the keyd keyboard remapping daemon
  services.keyd = {
    enable = true;
  };

  # 2b. keyd demotes itself to the "keyd" user/group at startup (upstream
  # behavior; Arch's package creates these, the NixOS module does not).
  # Without them keyd logs a warning on every start and stays root.
  users.users.keyd = {
    isSystemUser = true;
    group = "keyd";
    description = "keyd keyboard remapping daemon";
  };
  users.groups.keyd = { };

  # 3. /etc/keyd must exist as a REAL writable directory: the keyboard-remap
  # extension installs /etc/keyd/sumika.conf imperatively via pkexec. Create
  # it with tmpfiles (runs as root outside the unit sandbox) — the keyd unit
  # has ProtectSystem=strict, so a preStart mkdir inside it fails with EROFS.
  # The placeholder keeps keyd from exiting when no real config exists yet.
  systemd.tmpfiles.rules = [
    "d /etc/keyd 0755 root root -"
    "f /etc/keyd/omd.conf 0644 root root - # Generated placeholder config"
  ];

  # 4. Sandbox overrides: keyd demotes itself to the keyd runtime user at
  # startup, which needs SETGID/SETUID beyond the module default bounding set.
  systemd.services.keyd.serviceConfig.CapabilityBoundingSet =
    [ "CAP_SYS_NICE" "CAP_IPC_LOCK" "CAP_SETGID" "CAP_SETUID" ];
}
