{
  description = "Tetsuya's Multi-device NixOS Flake Configuration";

  inputs = {
    # Pin the migration baseline to the installed NixOS release. Upgrade this
    # deliberately after the new machine is stable.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
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

      # New x86_64 NixOS host created from the machine's own hardware scan.
      nixos-new = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nixos-new/configuration.nix
        ];
      };

      # ARM64 QEMU/NixOS host. This host intentionally uses the GNOME
      # configuration instead of the legacy OMD/Sumika desktop module.
      nixos-aarch64 = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./hosts/nixos-aarch64/configuration.nix
        ];
      };
    };
  };
}
