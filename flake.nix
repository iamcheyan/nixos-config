{
  description = "Tetsuya's Multi-device NixOS Flake Configuration";

  inputs = {
    # Pin the migration baseline to the installed NixOS release. Upgrade this
    # deliberately after the new machine is stable.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    nixarchy = {
      url = "github:olafkfreund/nixarchy/v4.0.1-1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Minimal NixOS environment for WSL2 on Windows 11.
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      # ARM64 QEMU/NixOS host.
      aarch64 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/aarch64/configuration.nix
        ];
      };

      # x86_64 ext4 workstation using the same nixarchy desktop baseline.
      hx90 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/nixos-hx90/configuration.nix
        ];
      };

      # x86_64 WSL2 environment for Windows 11 (no desktop stack).
      wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.nixos-wsl.nixosModules.default
          ./hosts/wsl/configuration.nix
        ];
      };
    };
  };
}
