{ pkgs, ... }:

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
  ];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # nix-darwin manages the Nix daemon unconditionally when Nix is enabled;
  # there is no separate services.nix-daemon.enable switch on this release.

  # A declarative SSH daemon is deliberately not enabled here. This Mac is a
  # client first; enable remote login separately only if that is needed.
}
