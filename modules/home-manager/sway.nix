{ config, lib, pkgs, ... }:

let
  # Keep the same physical layout as the current Hyprland/Labwc setup.
  # Sway expects output positions in logical pixels.
  swayWaybarConfig = ../labwc/waybar/sway/config.jsonc;

  swayWorkspace = number: "workspace number ${toString number}";
  swayMoveWorkspace = number: "move container to workspace number ${toString number}";
in
{
  # Sway is an additional session.  Hyprland and Labwc remain untouched.
  wayland.windowManager.sway = {
    enable = true;
    package = null;
    wrapperFeatures.gtk = true;

    config = {
      modifier = "Mod4";
      terminal = "kitty";
      menu = "fuzzel";

      # Do not let Home Manager start a second bar from its generated config;
      # the session startup below starts the Waybar profile explicitly.
      bars = [ ];

      input."*" = {
        xkb_layout = "jp";
        xkb_options = "compose:caps";
      };

      output = {
        "HDMI-A-1" = {
          mode = "1280x1024@60Hz";
          position = "0 0";
          scale = "1";
        };
        "HDMI-A-2" = {
          mode = "3840x2160@60Hz";
          position = "1280 0";
          scale = "2";
        };
      };

      gaps = {
        inner = 0;
        outer = 0;
        smartGaps = false;
      };

      # Match the current Hyprland appearance: no animation, no blur/shadow,
      # and a small visible border around tiled windows.
      window = {
        border = 2;
        titlebar = false;
      };

      floating = {
        border = 2;
        titlebar = false;
      };

      keybindings = lib.mkOptionDefault {
        "Mod4+Return" = "exec kitty";
        "Mod4+d" = "exec fuzzel";
        "Mod4+q" = "kill";

        "Mod4+h" = "focus left";
        "Mod4+j" = "focus down";
        "Mod4+k" = "focus up";
        "Mod4+l" = "focus right";
        "Mod4+Left" = "focus left";
        "Mod4+Down" = "focus down";
        "Mod4+Up" = "focus up";
        "Mod4+Right" = "focus right";

        "Mod4+Shift+h" = "move left";
        "Mod4+Shift+j" = "move down";
        "Mod4+Shift+k" = "move up";
        "Mod4+Shift+l" = "move right";
        "Mod4+Shift+Left" = "move left";
        "Mod4+Shift+Down" = "move down";
        "Mod4+Shift+Up" = "move up";
        "Mod4+Shift+Right" = "move right";

        "Mod4+f" = "fullscreen toggle";
        "Mod4+Shift+space" = "floating toggle";
        "Mod4+space" = "focus mode_toggle";

        # Sway workspaces belong to one output at a time.  These are the
        # standard focused-workspace bindings for the first test session;
        # output-specific numbering can be refined after observing the real
        # monitor names and desired workspace map.
        "Mod4+1" = swayWorkspace 1;
        "Mod4+2" = swayWorkspace 2;
        "Mod4+3" = swayWorkspace 3;
        "Mod4+4" = swayWorkspace 4;
        "Mod4+Shift+1" = swayMoveWorkspace 1;
        "Mod4+Shift+2" = swayMoveWorkspace 2;
        "Mod4+Shift+3" = swayMoveWorkspace 3;
        "Mod4+Shift+4" = swayMoveWorkspace 4;

        "Mod4+Shift+c" = "reload";
        "Mod4+Shift+e" = "exit";
        "Mod4+Tab" = "workspace back_and_forth";

        "Print" = "exec grim -g \"$(slurp)\" - | swappy -f -";
        "Shift+Print" = "exec grim - | swappy -f -";
        "F9" = "exec voxtype record toggle";
        "F24" = "exec voxtype record toggle";
      };

      startup = [
        {
          command = "~/.local/bin/nixarchy-import-session-environment";
          always = true;
        }
        {
          command = "systemctl --user start --no-block voxtype.service";
          always = true;
        }
        {
          command = "~/.config/labwc/scripts/set-wallpaper wayland";
          always = true;
        }
        {
          command = "waybar -c ${swayWaybarConfig}";
          always = true;
        }
      ];
    };
  };

}
