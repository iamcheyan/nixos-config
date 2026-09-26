{ lib, stdenvNoCC, bash, python3, coreutils, nixos-icons, satty, localsend, fetchFromGitHub }:
let
  themeSource = fetchFromGitHub {
    owner = "basecamp"; repo = "omarchy";
    rev = "346e69e1cec6c4e8924531874af6ba010a1bc99e";
    hash = "sha256-DtaDI3gyvK7YVnul2vRmNHHGK86Hn64WfbAVeG4888Y=";
  };
in stdenvNoCC.mkDerivation {
  pname = "desktop-compat";
  version = "4.0.2-local";
  src = ../anchor-shell/compat/omarchy;
  nativeBuildInputs = [ bash python3 ];
  postPatch = ''
    python3 ${./normalize-desktop-compat.py} . ${nixos-icons} ${coreutils}
    patchShebangs bin default
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/omarchy" "$out/bin" "$out/share/fonts/truetype" "$out/share/plymouth/themes/omarchy"
    cp -r . "$out/share/omarchy/"
    cp -r ${themeSource}/themes "$out/share/omarchy/themes"
    for script in "$out/share/omarchy/bin/"*; do
      [ -f "$script" ] && ln -s "$script" "$out/bin/$(basename "$script")"
    done
    cp default/fonts/omarchy/omarchy.ttf "$out/share/fonts/truetype/"
    cp -r default/plymouth/. "$out/share/plymouth/themes/omarchy/"
    substituteInPlace "$out/share/plymouth/themes/omarchy/omarchy.plymouth" \
      --replace '/usr/share/plymouth/themes/omarchy' '/etc/plymouth/themes/omarchy'
    printf '#!${bash}/bin/bash\nexec ${satty}/bin/satty --filename "$@"\n' > "$out/bin/satty-edit"
    printf '#!${bash}/bin/bash\nexec ${localsend}/bin/localsend_app "$@"\n' > "$out/bin/localsend"
    printf '#!${bash}/bin/bash\necho "Use ~/nixos-config and nixos-rebuild to manage system packages." >&2\nexit 1\n' > "$out/bin/pacman"
    chmod +x "$out/bin/"{satty-edit,localsend,pacman}
    runHook postInstall
  '';
  meta.license = lib.licenses.mit;
}
