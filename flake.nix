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

    # Minimal NixOS environment for WSL2 on Windows 11.
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
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
  };
}
