# Reusable keyd mappings for Voxtype dictation.
#
# keyd owns only the keyboard-side behavior: a standalone press emits F24,
# while a chord keeps the normal modifier behavior. The desktop-side F24
# binding lives in chezmoi/dot_config/hypr/bindings.lua.
{
  leftControl = {
    leftcontrol = "overload(control, f24)";
  };

  rightControl = {
    rightcontrol = "overload(control, f24)";
  };

  capsLock = {
    capslock = "overload(control, f24)";
  };
}
