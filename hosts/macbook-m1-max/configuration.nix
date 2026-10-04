{ inputs, lib, ... }:

{
  imports = [
    ../../modules/cli.nix
    ../../modules/dev.nix
    ../../modules/fonts.nix
    ../../modules/darwin/base.nix
    ../../modules/darwin/packages.nix
    ../../modules/darwin/homebrew.nix
    ../../modules/darwin/defaults.nix
    inputs.home-manager.darwinModules.home-manager
  ];

  # Apple Silicon. Keep this explicit so evaluation cannot silently select a
  # package set for the wrong architecture.
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "macbook-m1-max";
  system.primaryUser = "tetsuya";

  # Run the OpenSSH server so this Mac accepts key-authenticated connections.
  services.openssh.enable = true;

  users.users.tetsuya = {
    name = "tetsuya";
    home =
      let home = builtins.getEnv "DARWIN_HOME";
      in assert lib.assertMsg (home != "")
        "DARWIN_HOME must point to the primary user's home directory";
        home;
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.tetsuya = import ../../modules/home-manager/darwin-user.nix;

  # Run the open-source Tailscale daemon as a system service so this Mac can
  # serve Tailscale SSH. Its state is kept by tailscaled under /var/db/tailscale.
  launchd.daemons.tailscaled.serviceConfig = {
    ProgramArguments = [ "/opt/homebrew/opt/tailscale/bin/tailscaled" ];
    RunAtLoad = true;
    KeepAlive = true;
    StandardOutPath = "/opt/homebrew/var/log/tailscaled.log";
    StandardErrorPath = "/opt/homebrew/var/log/tailscaled.log";
  };

  # This is the nix-darwin schema version, not the macOS version and not the
  # NixOS system.stateVersion. Do not change it during routine upgrades.
  system.stateVersion = 6;
}
