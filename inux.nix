{ config, lib, pkgs, ... }:

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
      in name != ".git" && name != "bin";
  };
  gtkDeps = lib.closePropagation [ pkgs.gtk4 pkgs.gtk4-layer-shell ];

  inua = pkgs.buildGoModule {
    pname = "inua";
    inherit version;
    passthru.providedSessions = [ "inua" ];

    src = inuaSource;

    # No vendor/ directory upstream; buildGoModule derives it from go.mod.
    vendorHash = "sha256-iM/qEJ/PJM9PLILeC7jpw+Hz7Qd1Xy7E5YvBz5hkoSE=";

    # Pure Go (CGO_ENABLED=0): GTK4 through puregotk, layer surfaces through
    # gtk4-layer-shell. The .ui files are committed, so no blueprint-compiler.
    nativeBuildInputs = [ pkgs.makeWrapper ];

    # Upstream injects the version through goreleaser; do the same so the
    # binaries do not report "dev".
    ldflags = [ "-s" "-w" "-X main.version=${version}" ];

    subPackages = [
      "cmd/inua"
      "cmd/inua-shell"
      "cmd/inua-apps"
      "cmd/inua-games"
      "cmd/inua-pinentry"
      "cmd/inua-assistant"
      "cmd/inua-keyring"
    ];

    # The GTK bindings load libraries at runtime, so the wrapped binaries need
    # the GTK stack on LD_LIBRARY_PATH.
    postFixup = ''
      for program in inua inua-shell inua-apps inua-games inua-assistant inua-keyring inua-pinentry; do
        wrapProgram "$out/bin/$program" \
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
          'export PATH="@INUA_PACKAGE@/bin:${pkgs.hyprland}/bin:$PATH"; export INUA_SESSION=1'
      substituteInPlace "$out/bin/inua-session" \
        --replace-fail '@INUA_PACKAGE@' "$out"
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
  environment.systemPackages = [ inua pkgs.gtk4 pkgs.gtk4-layer-shell ];
  services.displayManager.sessionPackages = [ inua ];

  # Inua runs on the existing Hyprland configuration. Upstream's session
  # script does not export a session marker of its own, so the Nix wrapper
  # below adds INUA_SESSION=1; Hyprland's autostart starts inua-shell only for
  # that session and the Omarchy/Quickshell shell only without it. This keeps
  # the regular Hyprland and Labwc sessions unchanged.
}
