{ lib
, makeWrapper
, nasm
, procps
, rustPlatform
, stdenv
, xdg-utils
}:

let
  source = ./ai-usagebar/upstream;
  cargoToml = builtins.fromTOML (builtins.readFile "${source}/Cargo.toml");
  linuxRuntimePath = lib.makeBinPath [ procps xdg-utils ];
in
rustPlatform.buildRustPackage {
  pname = "ai-usagebar";
  version = cargoToml.package.version;
  src = source;
  cargoLock.lockFile = "${source}/Cargo.lock";
  # The upstream Cargo suite is not part of a system package build.
  doCheck = false;
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isx86_64 [ nasm ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ makeWrapper ];
  postInstall = ''
    rm -f "$out/bin/ai-usagebar-tray"
    install -Dm644 config.example.toml "$out/share/ai-usagebar/config.example.toml"
    install -Dm644 README.md "$out/share/doc/ai-usagebar/README.md"
    install -Dm644 LICENSE "$out/share/licenses/ai-usagebar/LICENSE"
  '' + lib.optionalString stdenv.hostPlatform.isLinux ''
    for program in ai-usagebar ai-usagebar-tui; do
      wrapProgram "$out/bin/$program" --prefix PATH : "${linuxRuntimePath}"
    done
  '';
  meta = {
    description = "Multi-provider AI plan usage monitor and TUI";
    homepage = "https://github.com/akitaonrails/ai-usagebar";
    license = lib.licenses.mit;
    mainProgram = "ai-usagebar";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
