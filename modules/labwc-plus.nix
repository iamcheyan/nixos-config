{ config, lib, pkgs, ... }:

let
  # This machine is intentionally built from the local development checkout.
  # The path is outside this flake, so nixos-rebuild must be run with
  # --impure. There is no fallback to the upstream GitHub package anymore.
  localSource = "/home/tetsuya/labwc-plus";

  # The pinned nixpkgs branch currently carries wlroots 0.20.0, while this
  # fork follows the upstream 0.20.1 API baseline.
  wlroots0201 = pkgs.wlroots_0_20.overrideAttrs (_: {
    version = "0.20.1";
    src = pkgs.fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "wlroots";
      repo = "wlroots";
      rev = "0.20.1";
      hash = "sha256-uuc1dn13FXvFSBvE3+QOi35rLJZmWIUst64oaXGdPFk=";
    };
  });

  labwcPlusSource = lib.cleanSourceWith {
    src = builtins.path {
      path = localSource;
      name = "labwc-plus-local";
    };
    filter = path: _type:
      let
        pathString = toString path;
      in
        !lib.hasInfix "/.git/" pathString
        && !lib.hasInfix "/build/" pathString
        && builtins.match ".*/subprojects/[^/]+\\.wrap" pathString == null;
  };

  labwcPlus = pkgs.labwc.overrideAttrs (old: {
    pname = "labwc-plus";
    version = "0.20.2";

    src = labwcPlusSource;

    # Nixpkgs' 0.9.7 package follows wlroots 0.19.  labwc-plus 0.20.x
    # requires wlroots 0.20, so replace that one dependency in the inherited
    # package instead of silently compiling against the old ABI.
    buildInputs =
      (lib.filter (input: input != pkgs.wlroots_0_19) old.buildInputs)
      ++ [ wlroots0201 ];

    # NixOS/Home Manager already provides the session lifecycle wiring.  Do
    # not let Meson install a user unit into the systemd package output.
    mesonFlags = (old.mesonFlags or [ ]) ++ [
      (lib.mesonOption "systemd-session" "disabled")
    ];

    # Keep the executable and session identity unchanged, but make the
    # compositor easy to distinguish from the stock labwc in SDDM.
    postInstall = (old.postInstall or "") + ''
      substituteInPlace "$out/share/wayland-sessions/labwc.desktop" \
        --replace-fail 'Name=labwc' 'Name=labwc-plus'
    '';
  });
in
{
  # labwc.nix owns the session configuration and assets; this module owns
  # only the compositor package used by that session.
  config = lib.mkIf config.programs.labwcPreview.enable {
    programs.labwc.package = labwcPlus;
  };
}
