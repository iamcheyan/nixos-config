{ ... }:

{
  homebrew = {
    enable = true;

    # These are the current top-level GUI applications that are useful to
    # preserve during the first declarative migration. Dependencies installed
    # by Homebrew are not copied here; Homebrew resolves them itself.
    casks = [
      "aerospace"
      "alacritty"
      "android-commandlinetools"
      "android-platform-tools"
      "android-studio"
      "appcleaner"
      "balenaetcher"
      "beekeeper-studio"
      "bitwarden"
      "cap"
      "claude"
      "coconutbattery"
      "crystalfetch"
      "db-browser-for-sqlite"
      "genymotion"
      "ghostty"
      "google-chrome"
      "google-drive"
      "grandperspective"
      "godot-mono"
      "hammerspoon"
      "hhkb-studio"
      "iterm2"
      "keka"
      "kitty"
      "klogg"
      "maccy"
      "macfuse"
      "meld"
      "microsoft-office"
      "miniconda"
      "monitorcontrol"
      "nextcloud"
      "onedrive"
      "openmtp"
      "orbstack"
      "snipaste"
      "tailscale"
      "tigervnc-viewer"
      "utm"
      "vlc"
      "upscayl"
      "visual-studio-code"
      "xquartz"
      "zed"
      "zoom"
    ];

    # Keep specialised formulae in Homebrew for now. Ordinary CLI tools are
    # intentionally provided by Nix instead of being duplicated here.
    brews = [
      "mas"
      "ntfs-3g-mac"
    ];

    # Mac App Store applications. IDs come from `mas list` on this Mac.
    # Installing these requires the Mac App Store account to be signed in;
    # removing an entry later does not automatically uninstall the app.
    masApps = {
      "Adblock Plus" = 1432731683;
      "KeePassium" = 1435127111;
      "LINE" = 539883307;
      "Microsoft Excel" = 462058435;
      "Parallels Client" = 600925318;
      "QQ" = 451108668;
      "QuickFox" = 1514073011;
      "SingleFile" = 6444322545;
      "Telegram" = 747648890;
      "The Unarchiver" = 425424353;
      "WeChat" = 836500024;
      "WhatsApp" = 310633997;
      "Windows App" = 1295203466;
      "格式工厂" = 6443540458;
      "迅雷" = 1503466530;
      "没入型翻訳" = 6447957425;
    };

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
