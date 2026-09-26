{ config, hostName ? "unknown", lib, pkgs, ... }:

let
  # Hyprland uses XKB names.  Keep the choice with the host configuration so
  # the same Home Manager module can be reused by other NixOS workstations.
  kbLayout = {
    hx90 = "jp";
  }.${hostName} or "us";

  inputSource = builtins.readFile ./hypr/input.lua;
  inputWithLayout = lib.replaceStrings
    [ "input = {\n    kb_options = \"compose:caps\",\n  }" ]
    [ "input = {\n    kb_layout = \"${kbLayout}\",\n    kb_options = \"compose:caps\",\n  }" ]
    inputSource;

  active-monitor-screenshot = pkgs.writeShellApplication {
    name = "nixarchy-screenshot-active-monitor";
    runtimeInputs = [ pkgs.coreutils pkgs.grim pkgs.hyprland pkgs.jq pkgs.libnotify pkgs.wl-clipboard pkgs.wlr-randr pkgs.xdotool ];
    text = ''
      if [ "$#" -gt 0 ]; then
        monitor="$1"
        if ! wlr-randr | awk -v target="$monitor" '/^[^[:space:]]/ && $1 == target { found = 1 } END { exit !found }'; then
          printf 'Unknown monitor: %s\n' "$monitor" >&2
          exit 1
        fi
      else
        if monitor="$(hyprctl -j activeworkspace 2>/dev/null | jq -er '.monitor' 2>/dev/null)"; then
          :
        else
          # Labwc bindings pass the focused window's output explicitly. For
          # other callers, fall back to mapping the pointer to wlr-randr data.
          pointer="$(xdotool getmouselocation --shell | awk -F= '$1 == "X" { x = $2 } $1 == "Y" { y = $2 } END { if (x != "" && y != "") print x, y }')"
          if [ -z "$pointer" ]; then
            printf '%s\n' "Could not determine the active monitor." >&2
            exit 1
          fi
          monitor="$(wlr-randr | awk -v pointer="$pointer" '
            BEGIN { split(pointer, p, " "); px = p[1]; py = p[2] }
            function finish_output() {
              if (enabled == "yes" && width > 0 && height > 0 && scale > 0 &&
                  px >= x && px < x + width / scale &&
                  py >= y && py < y + height / scale) {
                print name
                found = 1
              }
            }
            /^[^[:space:]]/ {
              if (name != "") finish_output()
              name = $1; enabled = "no"; width = 0; height = 0
              x = 0; y = 0; scale = 1
            }
            /^[[:space:]]+Enabled: yes/ { enabled = "yes" }
            /^[[:space:]]+[0-9]+x[0-9]+ px,/ && /current/ {
              split($1, dimensions, "x"); width = dimensions[1]; height = dimensions[2]
            }
            /^[[:space:]]+Position:/ {
              position = $2; split(position, coordinates, ",")
              x = coordinates[1]; y = coordinates[2]
            }
            /^[[:space:]]+Scale:/ { scale = $2 }
            END { if (!found && name != "") finish_output() }
          ')"
          if [ -z "$monitor" ]; then
            printf '%s\n' "Could not map the pointer to an active monitor." >&2
            exit 1
          fi
        fi
      fi
      pictures_dir="''${XDG_PICTURES_DIR:-$HOME/Pictures}"
      mkdir -p "$pictures_dir"
      filepath="$pictures_dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"

      grim -o "$monitor" "$filepath"
      wl-copy --type image/png < "$filepath"
      printf '%s\n' "$filepath"
      notify-send "Screenshot" "Saved to Pictures and copied to clipboard" -t 2500 2>/dev/null || true
    '';
  };
in
{
  home.packages = [ active-monitor-screenshot ];

  # The complete Hyprland user directory is now owned by Home Manager.  Keep
  # the source files in this repository; only input.lua is rendered per host.
  home.file = {
    ".config/hypr/README.md" = { source = ./hypr/README.md; force = true; };
    ".config/hypr/autostart.lua" = { source = ./hypr/autostart.lua; force = true; };
    ".config/hypr/bindings.lua" = { source = ./hypr/bindings.lua; force = true; };
    ".config/hypr/bindings.lua.bak.overview-interrupt-cleanup-1788595221" = {
      source = ./hypr/bindings.lua.bak.overview-interrupt-cleanup-1788595221;
      force = true;
    };
    ".config/hypr/hyprland.lua" = { source = ./hypr/hyprland.lua; force = true; };
    ".config/hypr/hyprsunset.conf" = { source = ./hypr/hyprsunset.conf; force = true; };
    ".config/hypr/input.lua" = { text = inputWithLayout; force = true; };
    ".config/hypr/looknfeel.lua" = { source = ./hypr/looknfeel.lua; force = true; };
    ".config/hypr/xdph.conf" = { source = ./hypr/xdph.conf; force = true; };
  };
}
