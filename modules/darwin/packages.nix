{ pkgs, ... }:

{
  # macOS-specific nixpkgs packages (if any).
  # Common CLI tools and development environments are managed by cli.nix and dev.nix.
  environment.systemPackages = with pkgs; [
  ];
}
