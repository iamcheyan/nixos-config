{ ... }:

{
  home.stateVersion = "26.05";

  home.sessionVariables = {
    BROWSER = "open";
  };

  # macOS-only user configuration lives in this repository rather than in
  # chezmoi. Manage individual files instead of whole application directories:
  # Karabiner and Hammerspoon create writable runtime data next to these files
  # (backups, assets, and Spoons).
  home.file = {
    ".config/aerospace/aerospace.toml".source = ./darwin-files/aerospace/aerospace.toml;
    ".config/karabiner/karabiner.json" = {
      source = ./darwin-files/karabiner/karabiner.json;
      # Karabiner regenerates a minimal default file when its old directory is
      # absent. Replace that first-run file with the versioned configuration.
      # Future edits must be made in the repository source file.
      force = true;
    };
    ".hammerspoon/init.lua".source = ./darwin-files/hammerspoon/init.lua;
    ".skhdrc".source = ./darwin-files/skhdrc;
    ".local/bin/macos-zero-animation".source = ./darwin-files/scripts/macos-zero-animation.sh;
  };
}
