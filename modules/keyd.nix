{ pkgs, ... }:

let
  voice = import ./keyd-voice.nix;
in

{
  # One shared MINILA-R profile for every host. The USB ID identifies the
  # keyboard, not a machine-specific configuration variant.
  environment.systemPackages = [ pkgs.keyd ];

  services.keyd = {
    enable = true;
    keyboards.minila-r = {
      ids = [
        "k:0c45:22b8" # USB wired mode
        "k:0a5c:8502" # Bluetooth mode
      ];
      settings.main = {
        leftalt = "leftmeta";
        leftmeta = "leftalt";
        # Dedicated MINILA-R modifier layer.  Screenshot actions emit real
        # Print-based key events; the desktop binding remains in chezmoi.
        fn = "layer(muhenkan)";
        muhenkan = "layer(muhenkan)";
        katakanahiragana = "left";
        delete = "right";
        rightcontrol = "up";
        rightalt = "down";
        grave = "escape";
        escape = "grave";
      # The physical right Ctrl key is the MINILA-R arrow-up key.  Keep this
      # mapping authoritative; the voice layer must not turn it back into a
      # Ctrl/F24 overload.
      } // voice.leftControl // voice.capsLock;
      settings.muhenkan = {
        # Emit C-M-v directly; F13 is not reliably received by Labwc.
        v = "C-M-v";
        l = "C-M-l";
        "3" = "C-S-f3";
        s = "print";
      };
      settings."muhenkan+shift" = {
        # Keep physical Shift+Print's delayed screenshot untouched while
        # providing a distinct chord for MINILA-R's direct full-screen shot.
        s = "C-S-print";
      };
    };
  };
}
