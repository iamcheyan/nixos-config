# Reusable keyd mappings for Voxtype dictation.
#
# keyd owns only the keyboard-side behavior:
#   * A Control chord is always Control, even if Control was held past holdMs.
#   * Holding Control alone for holdMs milliseconds emits F24 (and keeps
#     Control) for the rest of the press; releasing F24 ends the hold.
# The desktop-side F24 binding and the voxtype-ptt watcher live next to this
# file in keyd.nix / Labwc / Hyprland.
#
# timeout(layer(control), holdMs, f24) is the wrong action2: once F24 replaces
# Control, a later letter is typed unmodified. oneshotk(control, f24) keeps
# the control layer while F24 is held, so Ctrl+A still works after the timeout.
# oneshot_timeout in extraConfig clears the leftover oneshot Control after a
# solo hold-to-talk release, so the next letter is not Ctrl+letter.
let
  holdMs = 300;
  holdToTalk = "timeout(layer(control), ${toString holdMs}, oneshotk(control, f24))";
in
{
  inherit holdMs;

  extraConfig = ''
    [global]
    oneshot_timeout = 50
  '';

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
