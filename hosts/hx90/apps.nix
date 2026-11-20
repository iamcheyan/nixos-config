{ inputs, pkgs, ... }:
let
  # Tencent retired nixpkgs' fixed Linux AppImage URL. Keep WeChat on its
  # existing Nix package until the Flathub package's external-data checksum
  # works reliably again.
  wechatAppImage = pkgs.callPackage (pkgs.path + "/pkgs/by-name/we/wechat/linux.nix") {
    pname = "wechat";
    version = "4.1.1.8";
    meta = pkgs.wechat.meta;
    src = pkgs.fetchurl {
      name = "WeChatLinux_4.1.1.8_x86_64.AppImage";
      url = "https://github.com/trouter-ai/wechat-linux-versions/releases/download/v4.1.1.8/WeChatLinux_4.1.1.8_x86_64.AppImage";
      hash = "sha256-RX26ArkbAxzdRBLu4HT7v/udnQax5Q/Bgi00hw4RSZA=";
    };
  };
  # WeChat's bundled Qt runs through XWayland. Ask Qt 5 to use RandR's
  # per-monitor physical DPI so its UI follows each output's density.
  wechatLauncher = pkgs.writeShellScript "wechat" ''
    export QT_USE_PHYSICAL_DPI=1
    exec ${wechatAppImage}/bin/wechat "$@"
  '';
  wechatCurrent = pkgs.symlinkJoin {
    name = "wechat-${wechatAppImage.version}-hidpi";
    paths = [ wechatAppImage ];
    postBuild = ''
      rm $out/bin/wechat
      ln -s ${wechatLauncher} $out/bin/wechat
    '';
  };
  # Use the upstream Nix package built with Electron 43, outside the AppImage
  # user namespace that hides supplementary groups from WinBoat's own check.
  winboat = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.winboat;
in
{
  # QQ is installed from Flathub; WeChat and WinBoat remain Nix packages.
  environment.systemPackages = [ wechatCurrent winboat ];
}
