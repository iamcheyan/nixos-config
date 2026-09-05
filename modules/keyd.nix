{ pkgs, ... }:

{
  # One shared MINILA-R profile for every host. The USB ID identifies the
  # keyboard, not a machine-specific configuration variant.
  environment.systemPackages = [ pkgs.keyd ];

  services.keyd = {
    enable = true;
    keyboards.minila-r = {
      ids = [ "k:0c45:22b8" ];
      settings.main = {
        leftalt = "leftmeta";
        leftmeta = "leftalt";
        # Dedicated MINILA-R modifier layer.  Screenshot actions emit real
        # Print-based key events; the desktop binding remains in chezmoi.
        muhenkan = "layer(muhenkan)";
        katakanahiragana = "left";
        delete = "right";
        rightcontrol = "up";
        rightalt = "down";
        grave = "escape";
        escape = "grave";
        leftcontrol = "overload(control, f24)";
      };
    settings.muhenkan = {
      # Emit Ctrl+Super+V for the clipboard action.
      v = "C-M-v";
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
