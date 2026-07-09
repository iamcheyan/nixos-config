{
  description = "Tetsuya's Multi-device NixOS Flake Configuration";

  inputs = {
    # NixOS official unstable channel branch
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      # 1. Laptop Configuration (previously named nixos)
      # Command to rebuild: sudo nixos-rebuild switch --flake ~/nixos-config#laptop
      laptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/laptop/configuration.nix
        ];
      };

      # 2. Desktop Configuration
      # Command to rebuild: sudo nixos-rebuild switch --flake ~/nixos-config#desktop
      desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/desktop/configuration.nix
        ];
      };
    };
  };
}
