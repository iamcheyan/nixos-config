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

  # 3. Secure and robust systemd configuration for keyd
  systemd.services.keyd = {
    # Auto-initialize the configuration directory and files if they are missing
    # This prevents keyd from crashing with status 255 and locking system rebuilds
    preStart = ''
      mkdir -p /etc/keyd
      if [ ! -f /etc/keyd/omd.conf ]; then
        echo "# Generated placeholder config" > /etc/keyd/omd.conf
      fi
    '';

    serviceConfig = {
      # NixOS sandbox overrides (allows keyd to demote its user/group status on startup)
      CapabilityBoundingSet = [ "CAP_SYS_NICE" "CAP_IPC_LOCK" "CAP_SETGID" "CAP_SETUID" ];
    };
  };
}
