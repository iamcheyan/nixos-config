{ lib, stdenvNoCC, fetchFromGitHub, makeWrapper, wineWow64Packages }:

stdenvNoCC.mkDerivation rec {
  pname = "wind7z";
  version = "7z24.08";

  src = fetchFromGitHub {
    owner = "iamcheyan";
    repo = "7z-for-Linux";
    rev = "5190480c2fc00ee63c78e2cade00ce1b63fab098";
    hash = "sha256-OLInY8d60wxKlFo9iXU9OwHNIy/wH9gSyoL+xXCcaXs=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    appDir="$out/share/wind7z"
    mkdir -p "$appDir" "$out/bin" "$out/share/applications" "$out/share/icons/hicolor/256x256/apps"
    cp -r exe "$appDir/"
    cp 7-Zip.png "$out/share/icons/hicolor/256x256/apps/wind7z.png"

    cat > "$appDir/cjk-fonts.reg" <<'EOF'
    REGEDIT4

    [HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
    "MS Shell Dlg"="WenQuanYi Micro Hei"
    "MS Shell Dlg 2"="WenQuanYi Micro Hei"
    "MS UI Gothic"="WenQuanYi Micro Hei"
    "SimSun"="WenQuanYi Micro Hei"
    "NSimSun"="WenQuanYi Micro Hei"
    "Microsoft YaHei"="WenQuanYi Micro Hei"
    "Microsoft YaHei UI"="WenQuanYi Micro Hei"

    [HKEY_CURRENT_USER\Software\Wine\Fonts]
    "LogPixels"=dword:00000078

    [HKEY_CURRENT_USER\Control Panel\Desktop]
    "LogPixels"=dword:00000078
    "FontSmoothing"="2"
    "FontSmoothingGamma"=dword:00000578
    "FontSmoothingOrientation"=dword:00000001
    "FontSmoothingType"=dword:00000001

    [HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics]
    "MenuFont"=hex:f2,ff,ff,ff,00,00,00,00,00,00,00,00,00,00,00,00,90,01,00,00,00,00,00,01,00,00,04,00,57,00,65,00,6e,00,51,00,75,00,61,00,6e,00,59,00,69,00,20,00,4d,00,69,00,63,00,72,00,6f,00,20,00,48,00,65,00,69,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00

    [HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]
    "MS Shell Dlg"="WenQuanYi Micro Hei"
    "MS Shell Dlg 2"="WenQuanYi Micro Hei"
    "MS UI Gothic"="WenQuanYi Micro Hei"
    "SimSun"="WenQuanYi Micro Hei"
    "NSimSun"="WenQuanYi Micro Hei"
    "Microsoft YaHei"="WenQuanYi Micro Hei"
    "Microsoft YaHei UI"="WenQuanYi Micro Hei"

    [HKEY_CURRENT_USER\Software\7-Zip]
    "Lang"="zh-cn"
    EOF

    makeWrapper ${wineWow64Packages.stable}/bin/wine "$out/bin/wind7z" \
      --add-flags "$appDir/exe/7zFM.exe" \
      --run 'export WINEPREFIX="''${WINEPREFIX:-$HOME/.local/share/wineprefixes/wind7z}"' \
      --run 'mkdir -p "$(dirname "$WINEPREFIX")"' \
      --run "${wineWow64Packages.stable}/bin/wine regedit /S $appDir/cjk-fonts.reg" \
      --run 'export WINEDLLOVERRIDES="mscoree,mshtml=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"'

    cat > "$out/share/applications/wind7z.desktop" <<EOF
    [Desktop Entry]
    Name=7-Zip (Win7-Zip)
    Comment=Open and manage archives with Win7-Zip
    Exec=$out/bin/wind7z %f
    Icon=wind7z
    Terminal=false
    Type=Application
    Categories=Utility;Archiving;
    StartupNotify=true
    StartupWMClass=7zfm.exe
    MimeType=application/x-7z-compressed;application/zip;application/x-rar-compressed;application/vnd.rar;application/x-xz;application/x-xz-compressed;application/x-bzip;application/x-bzip2;application/gzip;application/x-gzip;application/x-tar;application/x-compressed-tar;
    EOF

    runHook postInstall
  '';

  meta = {
    description = "Win7-Zip GUI packaged for NixOS with system Wine";
    homepage = "https://github.com/iamcheyan/7z-for-Linux";
    # The bundled 7-Zip binaries are distributed under the upstream LGPL terms.
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "wind7z";
  };
}
