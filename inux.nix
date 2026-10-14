{ config, lib, pkgs, ... }:

let
  version = "0.0.2";
  gtkDeps = lib.closePropagation [ pkgs.gtk4 pkgs.gtk4-layer-shell ];
  inuaArchive = pkgs.fetchurl {
    url = "https://github.com/lyricat/inua/releases/download/v${version}/inua_linux_amd64.tar.gz";
    hash = "sha256-UA4vWf7DDRqlYDO22StmFsaoVfEMoZVu+Kx2vV/G6N8=";
  };

  inua = pkgs.stdenvNoCC.mkDerivation {
    pname = "inua";
    inherit version;
    passthru.providedSessions = [ "inua" ];
    src = inuaArchive;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;

    unpackPhase = ''
      tar -xzf "$src"
      sourceRoot=inua_linux_amd64
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 inua -t "$out/bin"
      install -Dm755 inua-shell -t "$out/bin"
      install -Dm755 inua-apps -t "$out/bin"
      install -Dm755 inua-pinentry -t "$out/bin"
      install -Dm755 scripts/inua-session "$out/bin/inua-session"
      install -Dm644 config/apps/*.desktop -t "$out/share/applications"
      install -Dm644 config/apps/*.svg -t "$out/share/icons/hicolor/scalable/apps"
      install -Dm644 config/session/inua.desktop "$out/share/wayland-sessions/inua.desktop"

      for program in inua inua-shell inua-apps inua-pinentry; do
        wrapProgram "$out/bin/$program" \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath gtkDeps}" \
          --prefix PKG_CONFIG_PATH : "${lib.makeSearchPathOutput "dev" "lib/pkgconfig" gtkDeps}"
      done

      substituteInPlace "$out/share/wayland-sessions/inua.desktop" \
        --replace-fail '/usr/local/bin/inua-session' '/run/current-system/sw/bin/inua-session'
      substituteInPlace "$out/bin/inua-session" \
        --replace-fail 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"' \
          'export PATH="@INUA_PACKAGE@/bin:${pkgs.hyprland}/bin:$PATH"; export INUA_SESSION=1'
      substituteInPlace "$out/bin/inua-session" \
        --replace-fail '@INUA_PACKAGE@' "$out"
      runHook postInstall
    '';
  };
in
{
  environment.systemPackages = [ inua pkgs.gtk4 pkgs.gtk4-layer-shell ];
  services.displayManager.sessionPackages = [ inua ];

  # Inua runs on the existing Hyprland configuration. Its shell autostart is
  # gated by the Inua session launcher, keeping the regular Hyprland session
  # unchanged.
}
