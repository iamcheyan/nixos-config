{
  description = "Tetsuya's Multi-device NixOS Flake Configuration";

  inputs = {
    # Pin the migration baseline to the installed NixOS release. Upgrade this
    # deliberately after the new machine is stable.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    nixarchy = {
      url = "github:olafkfreund/nixarchy/v4.0.2-4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # macOS system management for the Apple Silicon host. Keep this on the
    # matching 26.05 branch while the NixOS side uses nixpkgs 26.05.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Minimal NixOS environment for WSL2 on Windows 11.
    nixos-wsl.url = "github:nix-community/NixOS-WSL";

    # Fresh moves faster than the pinned Nixpkgs release. Keep its official
    # flake independent so the CLI/editor can follow Fresh releases without
    # upgrading the system-wide nixpkgs baseline.
    fresh.url = "github:sinelaw/fresh";

    # Shizuka SDDM theme. Keep the theme as a locked flake input instead of
    # copying its files into this configuration repository.
    shizuka = {
      url = "git+https://github.com/iamcheyan/shizuka.git?ref=main";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    # Git-ignored per-machine modules live outside the pure flake snapshot.
    # Pass NIXOS_CONFIG_LOCAL and --impure when you want to load them.
    localRoot = builtins.getEnv "NIXOS_CONFIG_LOCAL";
  in {
    nixosConfigurations = {
      # ARM64 QEMU/NixOS host.
      aarch64 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs localRoot; };
        modules = [
          ./hosts/aarch64/configuration.nix
        ];
      };

      # x86_64 btrfs workstation using the same nixarchy desktop baseline.
      hx90 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs localRoot; };
        modules = [
          ./hosts/hx90/configuration.nix
        ];
      };

      # x86_64 WSL2 environment for Windows 11 (no desktop stack).
      wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs localRoot; };
        modules = [
          inputs.nixos-wsl.nixosModules.default
          ./hosts/wsl/configuration.nix
        ];
      };
    };

    # Apple Silicon macOS host. This is intentionally a separate output:
    # nix-darwin modules are not NixOS modules, and macOS has no hardware
    # configuration file comparable to a NixOS installation.
    darwinConfigurations.macbook-m1-max = inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { inherit inputs localRoot; };
      modules = [
        ./hosts/macbook-m1-max/configuration.nix
      ];
    };
  };
}
