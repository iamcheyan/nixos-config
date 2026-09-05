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
        muhenkan = "f13";
        katakanahiragana = "left";
        delete = "right";
        rightcontrol = "up";
        rightalt = "down";
        grave = "escape";
        escape = "grave";
        leftcontrol = "overload(control, f24)";
      };
    };
  };
}
