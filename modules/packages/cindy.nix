{ lib, stdenvNoCC, fetchurl, dpkg, buildFHSEnv, writeShellScript, ... }:

let
  version = "0.1.109";
  deb = fetchurl {
    url = "https://hotfix.cindy.app/cindy/app/linux-x64/cindy-${version}-amd64.deb";
    sha256 = "55a2cffc2217cbcd60683aa678e06605d7950feb26232d0ee6ddd54e63af8fad";
  };
  app = stdenvNoCC.mkDerivation {
    pname = "cindy-unpacked";
    inherit version;
    src = deb;
    nativeBuildInputs = [ dpkg ];
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out"
      dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-permissions -C "$out"
    '';
  };
  fhs = buildFHSEnv {
    name = "cindy";
    targetPkgs = pkgs: with pkgs; [
      alsa-lib
      atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gtk3
      libGL
      libX11
      libXcomposite
      libXcursor
      libXext
      libXfixes
      libXi
      libXdamage
      libXrandr
      libXScrnSaver
      libXrender
      libXt
      libXtst
      libxcb
      libdrm
      libgbm
      libnotify
      libsecret
      libxkbcommon
      libxshmfence
      mesa
      nspr
      nss
      pango
      stdenv.cc.cc.lib
      udev
      xdg-utils
      zlib
    ];
    runScript = writeShellScript "cindy-fhs-launcher" ''
      # Keep the Electron backend selection inside the FHS container so every
      # entry point (desktop, command line, and URI handler) uses Wayland.
      export ELECTRON_OZONE_PLATFORM_HINT=wayland
      export OZONE_PLATFORM=wayland
      exec ${app}/usr/lib/cindy/Cindy --ozone-platform=wayland "$@"
    '';
  };
  launcher = writeShellScript "cindy-wayland-launcher" ''
    exec ${fhs}/bin/cindy "$@"
  '';
in
stdenvNoCC.mkDerivation {
  pname = "cindy";
  inherit version;
  dontUnpack = true;
  nativeBuildInputs = [ dpkg ];
  installPhase = ''
    mkdir -p "$out/bin" "$out/share/applications" "$out/share/pixmaps"
    ln -s ${launcher} "$out/bin/cindy"
    cp ${app}/usr/share/pixmaps/cindy.png "$out/share/pixmaps/cindy.png"
    substitute ${app}/usr/share/applications/cindy.desktop "$out/share/applications/cindy.desktop" \
      --replace-fail "Exec=cindy" "Exec=$out/bin/cindy" \
      --replace-fail "Icon=cindy" "Icon=$out/share/pixmaps/cindy.png"
  '';
  meta = {
    description = "Open-source AI agent desktop application";
    homepage = "https://github.com/makecindy/cindy";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "cindy";
  };
}
