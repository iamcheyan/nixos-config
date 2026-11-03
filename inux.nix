{ config, lib, pkgs, inputs, ... }:

let
  ghosttyCommit = "765ea37ad64f7e3a48f6ac27a70ad7fb6f31b9bb";
  ghosttySrc = pkgs.fetchFromGitHub {
    owner = "ghostty-org";
    repo = "ghostty";
    rev = ghosttyCommit;
    hash = "sha256-YT0EJ1TAD1NepkP8y1W6GVhpcegl6SVvmSlnJq4CmPs=";
  };
  inuaTermEngine = let
    ghosttyDeps = pkgs.callPackage "${ghosttySrc}/build.zig.zon.nix" {
      name = "inua-term-engine-zig-packages-${ghosttyCommit}";
    };
  in pkgs.stdenv.mkDerivation {
    pname = "inua-term-engine";
    version = ghosttyCommit;
    src = ghosttySrc;
    nativeBuildInputs = [ pkgs.zig_0_16 pkgs.gawk pkgs.binutils pkgs.git pkgs.pkg-config ];
    dontConfigure = true;
    dontSetZigDefaultFlags = true;
    ZIG_GLOBAL_CACHE_DIR = "$TMPDIR/zig-global-cache";
    ZIG_LOCAL_CACHE_DIR = "$TMPDIR/zig-local-cache";
    buildPhase = ''
      runHook preBuild
      zig build --system "${ghosttyDeps}" -Demit-lib-vt=true -Doptimize=ReleaseFast
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      keymap="$PWD/zig-out/keymap"
      mkdir -p "$keymap" "$out/lib/inua"
      printf '%s\n' '{ global: inua_vt_*; local: *; };' > "$keymap/exports.map"
      ${pkgs.gawk}/bin/awk '
        FILENAME == ARGV[1] {
          if (match($0, /GHOSTTY_KEY_[A-Z0-9_]+/)) names[substr($0, RSTART, RLENGTH)] = 1
          next
        }
        /\.\{ "[A-Za-z0-9]+", \.[a-z0-9_]+ \}/ {
          match($0, /"[A-Za-z0-9]+"/); code = substr($0, RSTART + 1, RLENGTH - 2)
          match($0, /\.[a-z0-9_]+ \}/); tags[code] = substr($0, RSTART + 1, RLENGTH - 3)
          next
        }
        /^ *\.\{ 0x[0-9a-f]+, 0x[0-9a-f]+, 0x[0-9a-f]+,/ {
          split($0, f, ","); xkb = f[3]; gsub(/ /, "", xkb)
          if (xkb != "0x0000" && match($0, /"[A-Za-z0-9]+"/)) pairs[++n] = xkb SUBSEP substr($0, RSTART + 1, RLENGTH - 2)
        }
        END {
          for (i = 1; i <= n; i++) {
            split(pairs[i], p, SUBSEP)
            if (!(p[2] in tags)) continue
            name = toupper(tags[p[2]])
            if (name ~ /^KEY_[A-Z]$/) name = substr(name, 5)
            name = "GHOSTTY_KEY_" name
            if (name in names) print "  {" p[1] ", " name "},"
          }
        }
      ' "$src/include/ghostty/vt/key/event.h" "$src/src/input/keycodes.zig" > "$keymap/inua_keymap.inc"
      test -s "$keymap/inua_keymap.inc"
      zig cc -shared -fPIC -O2 -std=c11 -Wall -Werror -I zig-out/include -I "${inuaSource}/internal/term/vt/shim" -I "$keymap" -o "$out/lib/inua/libinua-vt.so" "${inuaSource}/internal/term/vt/shim/inua_vt.c" zig-out/lib/libghostty-vt.a -Wl,--version-script="$keymap/exports.map" -Wl,-s -Wl,-soname,libinua-vt.so
      runHook postInstall
    '';
  };
  # Build the machine's Inua package from the development checkout so system
  # upgrades pick up its current source, including uncommitted development work.
  # Set INUA_DEV_DIR="$HOME/development/inua" when evaluating the flake with
  # --impure; this keeps the checkout path independent of the login name.
  version = "dev";
  inuaDevDir = builtins.getEnv "INUA_DEV_DIR";
  inuaSource = lib.cleanSourceWith {
    src = if inuaDevDir == "" then
      throw "INUA_DEV_DIR must point to the Inua development checkout (use --impure)"
    else
      builtins.toPath inuaDevDir;
    filter = path: type:
      let name = builtins.baseNameOf (toString path);
      in name != ".git" && name != "bin" && name != "vendor";
  };
  gtkDeps = lib.closePropagation [ pkgs.gtk4 pkgs.gtk4-layer-shell ];
  # puregotk expects one directory and may load several sonames per namespace
  # (GLib needs both glib and gobject). Keep all of those files available.
  puregotkLibraries = pkgs.linkFarm "inua-puregotk-libraries" (map
    (entry: { name = entry.name; path = "${lib.getLib entry.package}/lib/${entry.name}"; })
    [
      { name = "libgtk-4.so.1"; package = pkgs.gtk4; }
      { name = "libglib-2.0.so.0"; package = pkgs.glib; }
      { name = "libgobject-2.0.so.0"; package = pkgs.glib; }
      { name = "libgio-2.0.so.0"; package = pkgs.glib; }
      { name = "libgmodule-2.0.so.0"; package = pkgs.glib; }
      { name = "libcairo-gobject.so.2"; package = pkgs.cairo; }
      { name = "libpango-1.0.so.0"; package = pkgs.pango; }
      { name = "libgraphene-1.0.so.0"; package = pkgs.graphene; }
      { name = "libgdk_pixbuf-2.0.so.0"; package = pkgs.gdk-pixbuf; }
    ]);
  shellStartup = pkgs.writeShellScriptBin "inua-shell-startup" ''
    umask 077
    logDir="$HOME/nixos-config/logs"
    mkdir -p "$logDir"
    logFile="''${INUA_STARTUP_LOG:-$(${pkgs.coreutils}/bin/mktemp "$logDir/inua-shell-$(date +%Y%m%d-%H%M%S)-XXXXXX.log")}"
    exec >>"$logFile" 2>&1
    printf '\n[%s] shell-launch pid=%s uptime=%s\n' "$(date --iso-8601=ns)" "$$" "$(cut -d ' ' -f 1 /proc/uptime)"
    exec ${inua}/bin/inua-shell "$@"
  '';
  # Use the separately locked Hyprland input. The Nixpkgs package remains on
  # 0.55.4 and lacks the upstream wl_output lifetime fix for monitor reconnects.
  hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default;

  inua = pkgs.buildGoModule {
    pname = "inua";
    inherit version;
    passthru.providedSessions = [ "inua" ];

    src = inuaSource;

    # Ignore the checkout's generated vendor tree: it may lag behind go.mod.
    # buildGoModule derives a consistent, hash-checked tree from go.mod/go.sum.
    vendorHash = "sha256-t3nzRUwpMcyneuqx4SDT1cFbFsPw2y2Xh+118MUNIV4=";

    # Pure Go (CGO_ENABLED=0): GTK4 through puregotk, layer surfaces through
    # gtk4-layer-shell. The .ui files are committed, so no blueprint-compiler.
    nativeBuildInputs = [ pkgs.makeWrapper ];

    # Instrument only the build snapshot; leave the development checkout alone.
    postPatch = ''
      ${pkgs.python3}/bin/python ${./modules/inua-startup-instrument.py}
    '';

    # Upstream injects the version through goreleaser; do the same so the
    # binaries do not report "dev".
    ldflags = [ "-s" "-w" "-X main.version=${version}" ];

    subPackages = [
      "cmd/inua"
      "cmd/inua-shell"
      "cmd/inua-apps"
      "cmd/inua-files"
      "cmd/inua-viewer"
      "cmd/inua-vm"
      "cmd/inua-remote"
      "cmd/inua-connect"
      "cmd/inua-disk-usage"
      "cmd/inua-mail"
      "cmd/inua-games"
      "cmd/inua-pinentry"
      "cmd/inua-assistant"
      "cmd/inua-keyring"
      "cmd/inua-term"
    ];

    # The GTK bindings load libraries at runtime, so the wrapped binaries need
    # the GTK stack on LD_LIBRARY_PATH.
    postFixup = ''
      for program in inua inua-shell inua-apps inua-files inua-viewer inua-vm inua-remote inua-connect inua-disk-usage inua-mail inua-games inua-assistant inua-keyring inua-pinentry inua-term; do
        wrapProgram "$out/bin/$program" \
          --set PUREGOTK_LIB_FOLDER "${puregotkLibraries}" \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath gtkDeps}" \
          --prefix PKG_CONFIG_PATH : "${lib.makeSearchPathOutput "dev" "lib/pkgconfig" gtkDeps}"
      done
    '';

    # buildGoModule installs the subPackages binaries into $out/bin itself.
    # Add the session script, desktop entries and the INUA_SESSION marker.
    postInstall = ''
      install -Dm755 scripts/inua-session "$out/bin/inua-session"
      install -Dm644 config/apps/*.desktop -t "$out/share/applications"
      install -Dm644 config/apps/*.svg -t "$out/share/icons/hicolor/scalable/apps"
      install -Dm644 config/session/inua.desktop "$out/share/wayland-sessions/inua.desktop"

      substituteInPlace "$out/share/wayland-sessions/inua.desktop" \
        --replace-fail '/usr/local/bin/inua-session' '/run/current-system/sw/bin/inua-session'
      substituteInPlace "$out/bin/inua-session" \
        --replace-fail 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"' \
          'export PATH="@INUA_PACKAGE@/bin:${hyprland}/bin:$PATH"; export INUA_SESSION=1'
      substituteInPlace "$out/bin/inua-session" \
        --replace-fail '@INUA_PACKAGE@' "$out"
      # Capture the session before Hyprland starts. The shell launcher reopens
      # this file because compositor-spawned children may have /dev/null stdio.
      substituteInPlace "$out/bin/inua-session" --replace-fail 'set -eu' 'set -eu
      umask 077
      mkdir -p "$HOME/nixos-config/logs"
      INUA_STARTUP_LOG=$(${pkgs.coreutils}/bin/mktemp "$HOME/nixos-config/logs/inua-login-$(date +%Y%m%d-%H%M%S)-XXXXXX.log")
      export INUA_STARTUP_LOG
      exec >>"$INUA_STARTUP_LOG" 2>&1
      printf "[%s] session-start pid=%s uptime=%s\\n" "$(date --iso-8601=ns)" "$$" "$(cut -d " " -f 1 /proc/uptime)"'
      install -Dm755 "${inuaTermEngine}/lib/inua/libinua-vt.so" "$out/lib/inua/libinua-vt.so"
    '';

    doCheck = false;

    meta = {
      description = "A quiet desktop shell for Hyprland, written in Go and GTK4";
      homepage = "https://github.com/lyricat/inua";
      license = lib.licenses.mit;
      mainProgram = "inua";
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  };
in
{
  environment.systemPackages = [ inua shellStartup pkgs.gtk4 pkgs.gtk4-layer-shell ];
  services.displayManager.sessionPackages = [ inua ];

  # Inua runs on the existing Hyprland configuration. Upstream's session
  # script does not export a session marker of its own, so the Nix wrapper
  # below adds INUA_SESSION=1; Hyprland's autostart starts inua-shell only for
  # that session and the Omarchy/Quickshell shell only without it. This keeps
  # the regular Hyprland and Labwc sessions unchanged.
}
