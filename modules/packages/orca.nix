{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "orca";
  version = "1.4.266";
  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-C/xSvDykAe6P0sMswwlK/iaWrr3EhuEN5/UXIiwmYUU=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs = pkgs: with pkgs; [
    alsa-lib
    gtk3
    libsecret
    libXScrnSaver
    libXtst
    mesa
    nss
  ];

  extraInstallCommands = ''
    install -Dm444 ${contents}/orca-ide.desktop $out/share/applications/orca.desktop
    install -Dm444 ${contents}/orca-ide.png $out/share/icons/hicolor/512x512/apps/orca.png
    substituteInPlace $out/share/applications/orca.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=orca'
  '';

  meta = {
    description = "Desktop workspace for coding agents";
    homepage = "https://github.com/stablyai/orca";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "orca";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
