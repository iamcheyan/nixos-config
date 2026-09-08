{ pkgs, ... }:

{
  # Unified system fonts across NixOS (Linux) and nix-darwin (macOS).
  # Terminal emulators (Kitty, Ghostty, Alacritty, Foot) and Neovim rely on
  # these fonts for consistent code rendering, powerline symbols, and icons.
  fonts.packages = with pkgs; [
    # Core Developer & Terminal Monospace Fonts (Nerd Fonts v3+)
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    meslo-lgs-nf

    # UI / Desktop & Multilingual Typography
    adwaita-fonts
    cantarell-fonts
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji

    # Icon and Symbol Glyphs for Statusbars, TUI & Editor UI
    material-symbols
    font-awesome
  ];
}
