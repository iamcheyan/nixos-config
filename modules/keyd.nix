{ pkgs, ... }:

let
  voice = import ./keyd-voice.nix;
  voxtypePtt = pkgs.writeScriptBin "voxtype-ptt" ''
    #!${pkgs.python3.interpreter}
    ${builtins.readFile ./voxtype-ptt.py}
  '';
in

{
  # One shared MINILA-R profile for every host. The USB ID identifies the
  # keyboard, not a machine-specific configuration variant.
  environment.systemPackages = [ pkgs.keyd voxtypePtt ];

  # TAG+="uaccess" must be applied before systemd's 73-seat-late.rules.
  # services.udev.extraRules lands in 99-local.rules, which is too late.
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "keyd-voxtype-ptt-udev";
      destination = "/lib/udev/rules.d/70-keyd-voxtype-ptt.rules";
      text = ''
        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="keyd virtual keyboard", TAG+="uaccess"
      '';
    })
  ];

  systemd.user.services.voxtype-ptt = {
    description = "Voxtype hold-to-talk from keyd F24";
    wantedBy = [ "default.target" ];
    path = [ pkgs.voxtype-onnx ];
    serviceConfig = {
      ExecStart = "${voxtypePtt}/bin/voxtype-ptt";
      Restart = "always";
      RestartSec = 1;
    };
  };

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
      # Ctrl/F24 hold-to-talk mapping.
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
