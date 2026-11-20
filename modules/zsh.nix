{ config, pkgs, ... }:

{
  # Enable global Zsh settings and completions
  programs.zsh.enable = true;
  programs.zsh.interactiveShellInit = ''
    # Reconnect shells to the persistent XFCE web desktop when no display
    # has already been selected by the caller.
    if [[ -z ''${DISPLAY:-} && -z ''${WAYLAND_DISPLAY:-} \
      && -r "$HOME/.local/state/webdesktop/display" \
      && -r "$HOME/.local/state/webdesktop/Xauthority" ]]; then
      read -r _webdesktop_display < "$HOME/.local/state/webdesktop/display"
      if [[ $_webdesktop_display == <-> && -S /tmp/.X11-unix/X$_webdesktop_display ]]; then
        export DISPLAY=":$_webdesktop_display"
        export XAUTHORITY="$HOME/.local/state/webdesktop/Xauthority"
      fi
      unset _webdesktop_display
    fi
  '';
}
