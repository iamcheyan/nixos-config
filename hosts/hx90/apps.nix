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
  # nixpkgs' WinBoat 0.9.0 uses EOL Electron 40. Package the official 0.9.2
  # AppImage instead; that release includes security fixes and Electron 44.
  winboat = pkgs.appimageTools.wrapType2 {
    pname = "winboat";
    version = "0.9.2";
    src = pkgs.fetchurl {
      name = "winboat-0.9.2-x86_64.AppImage";
      url = "https://github.com/winboat-org/winboat/releases/download/v0.9.2/winboat-0.9.2-x86_64.AppImage";
      hash = "sha256-YzaEO5EeNEv2GC666i1C6JYO8RggoMyEI5qEi6ChQOQ=";
    };
  };
  winboatDesktop = pkgs.makeDesktopItem {
    name = "winboat";
    desktopName = "WinBoat";
    comment = "Run Windows apps on Linux";
    exec = "winboat";
    categories = [ "Utility" ];
  };
in
{
  environment.systemPackages = [ qqCurrent wechatCurrent winboat winboatDesktop ];
}
