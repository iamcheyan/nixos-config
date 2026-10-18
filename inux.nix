{ config, lib, pkgs, inputs, ... }:

let
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
    # Go's init trace covers the work before main, including the preload re-exec.
    export GODEBUG="''${GODEBUG:+$GODEBUG,}inittrace=1"
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
    vendorHash = "sha256-lG1TxwYgNX1p1XfLxzgxcDRKnKfsbOU7aBhUtzVdIBQ=";

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
      "cmd/inua-games"
      "cmd/inua-pinentry"
      "cmd/inua-assistant"
      "cmd/inua-keyring"
    ];

    # The GTK bindings load libraries at runtime, so the wrapped binaries need
    # the GTK stack on LD_LIBRARY_PATH.
    postFixup = ''
      for program in inua inua-shell inua-apps inua-files inua-viewer inua-games inua-assistant inua-keyring inua-pinentry; do
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
