{ lib
, buildGoModule
, fetchFromGitHub
, cmake
, ninja
, pkg-config
, makeWrapper
, qt6
}:

buildGoModule rec {
  pname = "flux";
  version = "0.10.1";

  src = fetchFromGitHub {
    owner = "bjarneo";
    repo = "flux";
    rev = "1605304ac1bf6b132472fa248238be3d05ff1899";
    hash = "sha256-EbZZfGyrKjAyfDNCX6uuKJGmwT0kUy14lqjk3xDiqx4=";
  };

  patches = [ ./flux-labwc.patch ];

  # The daemon and CLI are Go; the desktop window is Qt Quick/C++.
  nativeBuildInputs = [ cmake ninja pkg-config makeWrapper ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative qt6.qtsvg qt6.qtwayland ];

  vendorHash = "sha256-ziP/NS+YCcakzYOcszxqCV5dWKD4upCUVB8Rf6YFf+Y=";
  doCheck = false;
  dontWrapQtApps = true;

  # The pinned nixos-26.05 channel provides Go 1.26.6. Flux's dependencies
  # support Go 1.26; lower the module floor to the channel's compiler and let
  # the build catch any source that actually needs a newer standard library.
  postPatch = ''
    substituteInPlace go.mod --replace-fail 'go 1.27.1' 'go 1.26'
    # The pinned upstream desktop welcome page predates its iOS client copy.
    # Both Android and iPhone are supported peers, so keep the shared guide neutral.
    substituteInPlace gui/qml/pages/Empty.qml \
      --replace-fail 'Flux pairs with Flux for Android on your phone.' \
        'Flux pairs with Flux on your phone.' \
      --replace-fail 'Install Flux for Android on the phone.' \
        'Install Flux on your phone (Android or iPhone).'
    substituteInPlace cmd/flux/update.go \
      --replace-fail 'r, err := release.Latest(context.Background(), release.URL(), version)' \
      'if !checkOnly { return errors.New("Flux is managed by NixOS. Update it by rebuilding the system configuration") }; r, err := release.Latest(context.Background(), release.URL(), version)'
  '';

  buildPhase = ''
    runHook preBuild
    make build VERSION=${version}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/fluxd "$out/bin/fluxd"
    install -Dm755 bin/flux-cli "$out/bin/flux-cli"
    install -Dm755 bin/flux-approve "$out/lib/flux/flux-approve"
    install -Dm755 gui/app/build/flux-gui "$out/bin/flux-gui"
    wrapProgram "$out/bin/flux-gui" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtbase}/lib/qt-6/plugins:${qt6.qtsvg}/lib/qt-6/plugins:${qt6.qtwayland}/lib/qt-6/plugins"

    install -Dm644 dist/flux.desktop "$out/share/applications/flux.desktop"
    install -Dm644 dist/flux.svg "$out/share/icons/hicolor/scalable/apps/flux.svg"
    install -Dm644 dist/flux-symbolic.svg "$out/share/icons/hicolor/symbolic/apps/flux-symbolic.svg"

    mkdir -p "$out/lib/flux/qml/Flux"
    find gui/qml -type f \( -name '*.qml' -o -name '*.js' -o -name qmldir \) \
      ! -path 'gui/qml/tools/*' -print | while IFS= read -r file; do
        target="$out/lib/flux/qml/Flux/''${file#gui/qml/}"
        install -Dm644 "$file" "$target"
      done
    # The upstream Omarchy widget imports the mark from Flux/components.
    # Export that same packaged component from the shared Flux module so the
    # Anchor plugin can use it through the stable `import Flux 1.0` path.
    install -Dm644 gui/qml/components/FluxMark.qml "$out/lib/flux/qml/Flux/FluxMark.qml"
    printf '\nFluxMark 1.0 FluxMark.qml\n' >> "$out/lib/flux/qml/Flux/qmldir"

    mkdir -p "$out/lib/systemd/user"
    sed "s|@BINDIR@|$out/bin|g" dist/fluxd.service \
      > "$out/lib/systemd/user/fluxd.service"

    runHook postInstall
  '';

  meta = {
    description = "Connect a Linux desktop to phones and Macs with Flux";
    homepage = "https://github.com/bjarneo/flux";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    # Upstream has not selected a license yet.
    license = lib.licenses.unfree;
    mainProgram = "flux-cli";
  };
}
