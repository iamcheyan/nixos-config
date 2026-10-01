# Reusable keyd mappings for Voxtype dictation.
#
# keyd owns only the keyboard-side behavior. A Control chord stays Control.
# Holding Control alone for holdMs milliseconds emits F24 for the rest of the
# press; releasing F24 ends the hold. The desktop-side F24 binding and the
# voxtype-ptt watcher live next to this file in keyd.nix / Labwc / Hyprland.
let
  holdMs = 200;
  holdToTalk = "timeout(layer(control), ${toString holdMs}, f24)";
in
{
  inherit holdMs;

  leftControl = {
    leftcontrol = holdToTalk;
  };

  rightControl = {
    rightcontrol = holdToTalk;
  };

  capsLock = {
    capslock = holdToTalk;
  };
}
