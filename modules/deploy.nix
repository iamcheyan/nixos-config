{ config, lib, pkgs, ... }:

# NixOS deploy pipeline safety net.
#
# Primary path:  CI builds the flake on push/auto-update, then a Hermes webhook
#                (controller) SSHes to this host and runs
#                `scripts/nixos-apply.sh --controller --ref <ref>`.
# Fallback path: this timer runs only when the controller has not applied an
#                update within FALLBACK_GRACE_HOURS (see the script). It runs the
#                full local `nixos-update` so the machine still self-updates when
#                the controller is unreachable.
#
# Both paths go through scripts/nixos-apply.sh, which stashes any uncommitted
# work (e.g. an in-progress feature branch) and restores it afterwards — it
# never `git reset --hard`.
{
  systemd.services.nixos-deploy-fallback = {
    description = "NixOS deploy fallback (controller unreachable)";
    serviceConfig = {
      Type = "oneshot";
      User = "tetsuya";
      TimeoutSec = "1800";
    };
    script = ''
      exec ${pkgs.bash}/bin/bash /home/tetsuya/nixos-config/scripts/nixos-apply.sh --fallback
    '';
  };

  systemd.timers.nixos-deploy-fallback = {
    description = "Daily NixOS deploy fallback timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "2h";
      Persistent = true;
    };
  };
}
