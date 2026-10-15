{ config, lib, pkgs, ... }:

let
  # inua is built from source at a pinned commit rather than from an upstream
  # release tarball. v0.0.12 (the latest release, 2026-10-14) ships the
  # workspace overview crash from upstream issue #13 — its window cards
  # unreference their icon and title twice, so pressing Win segfaults the
  # shell. Commit 54f7f2aa2f4d carries the fix but is not in any release yet.
  # Move back to a release tarball once upstream tags one that includes it.
  rev = "54f7f2aa2f4deddc1153dcfc327facdee2cd32f3";
  version = "0.0.12-unstable-2026-10-14";
  gtkDeps = lib.closePropagation [ pkgs.gtk4 pkgs.gtk4-layer-shell ];

  inua = pkgs.buildGoModule {
    pname = "inua";
    inherit version;
    passthru.providedSessions = [ "inua" ];

    src = pkgs.fetchFromGitHub {
      owner = "lyricat";
      repo = "inua";
      inherit rev;
      hash = "sha256-VxXajOsAEBEuioSnji7UOLkDhegGTXPx81tB/e2EyKQ=";
    };

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
