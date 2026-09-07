{ ... }:

{
  homebrew = {
    enable = true;

    # These are the current top-level GUI applications that are useful to
    # preserve during the first declarative migration. Dependencies installed
    # by Homebrew are not copied here; Homebrew resolves them itself.
    casks = [
      "aerospace"
      "android-commandlinetools"
      "android-platform-tools"
      "android-studio"
      "beekeeper-studio"
      "bitwarden"
      "db-browser-for-sqlite"
      "genymotion"
      "ghostty"
      "godot-mono"
      "hammerspoon"
      "kitty"
      "klogg"
      "macfuse"
      "meld"
      "miniconda"
      "monitorcontrol"
      "orbstack"
      "vlc"
      "xquartz"
    ];

    # Keep specialised formulae in Homebrew for now. Ordinary CLI tools are
    # intentionally provided by Nix instead of being duplicated here.
    brews = [
      "mas"
      "ntfs-3g-mac"
    ];

    onActivation = {
      # The first switch must not uninstall anything that is currently
      # installed but has not yet been classified. Tighten this only after
      # reviewing `brew list --formula` and `brew list --cask`.
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };
  };
}
