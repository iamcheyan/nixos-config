{ pkgs, ... }:

let
  darwinRebuildMacbook = pkgs.writeShellScriptBin "darwin-rebuild-macbook" ''
    set -euo pipefail

    if [ "$#" -ne 0 ]; then
      echo "usage: sudo darwin-rebuild-macbook" >&2
      echo "This wrapper intentionally accepts no extra arguments." >&2
      exit 2
    fi

    exec /run/current-system/sw/bin/darwin-rebuild \
      switch --flake /Users/tetsuya/nixos-config#macbook-m1-max
  '';
in

{
  # Nix-darwin manages the Nix installation and the system activation entry
  # point. The macOS kernel, APFS layout, Recovery partition, and Apple boot
  # chain remain Apple's responsibility.
  nix.package = pkgs.nix;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "tetsuya" ];
    auto-optimise-store = true;
  };

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # Apple Silicon Homebrew is installed outside the Nix store. Keep its
  # executables visible to both interactive shells and Bash child scripts
  # (for example the fnm/npm-backed Codex wrapper).
  environment.systemPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];

  # Keep this list intentionally small. Cross-platform shell configuration
  # remains in ~/dotfiles and private ~/chezmoi; these are the binaries that
  # should exist before either repository's setup scripts run.
  environment.systemPackages = with pkgs; [
    age
    chezmoi
    curl
    fd
    fzf
    git
    jq
    neovim
    ripgrep
    tmux
    tree
    unzip
    wget
    zip
    zellij
    darwinRebuildMacbook
  ];

  # The wrapper is deliberately narrower than NOPASSWD: ALL or NOPASSWD: nix:
  # it can only switch this Mac to this repository's fixed flake target. The
  # first activation still needs the normal sudo password so this rule can be
  # installed; later switches can use `sudo darwin-rebuild-macbook`.
  environment.etc."sudoers.d/10-darwin-rebuild-macbook".text = ''
    tetsuya ALL=(root) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild-macbook
  '';

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # nix-darwin manages the Nix daemon unconditionally when Nix is enabled;
  # there is no separate services.nix-daemon.enable switch on this release.

  # A declarative SSH daemon is deliberately not enabled here. This Mac is a
  # client first; enable remote login separately only if that is needed.
}
