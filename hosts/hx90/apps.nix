{ pkgs, ... }:
let
  # The locked nixpkgs QQ source URL was removed upstream (404). Pin the
  # currently published official x86_64 Debian package until nixpkgs updates.
  qqCurrent = pkgs.qq.overrideAttrs (old: {
    version = "3.2.32-2026-08-12";
    src = pkgs.fetchurl {
      name = "QQ_3.2.32_260812_amd64_01.deb";
      url = "https://qqdl.gtimg.cn/qqfile/QQNT/9.9.33/release/3f89efc5/QQ_3.2.32_260812_amd64_01.deb";
      hash = "sha256-0IXdiTlyJQYeufGUMI9ogSmBjtRFd36XpKChbhPXsOg=";
    };
  });
  # Tencent retired the fixed Linux AppImage URL archived by nixpkgs. Use the
  # unmodified official AppImage mirrored with a published SHA-256 checksum.
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
in
{
  environment.systemPackages = [ qqCurrent wechatCurrent ];
}
