{ inputs, ... }:

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

  users.users.tetsuya = {
    name = "tetsuya";
    home = "/Users/tetsuya";
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.tetsuya = import ../../modules/home-manager/darwin-user.nix;

  # This is the nix-darwin schema version, not the macOS version and not the
  # NixOS system.stateVersion. Do not change it during routine upgrades.
  system.stateVersion = 6;
}
