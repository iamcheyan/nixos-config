{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.devenv (pkgs.callPackage ./packages/devenv-init.nix { }) ];
  programs.bash.interactiveShellInit = ''
    if command -v devenv >/dev/null 2>&1; then eval "$(devenv hook bash)"; fi
  '';
  programs.zsh.interactiveShellInit = ''
    if command -v devenv >/dev/null 2>&1; then eval "$(devenv hook zsh)"; fi
  '';
  programs.fish.interactiveShellInit = ''
    if command -q devenv; devenv hook fish | source; end
  '';
  nix.settings = {
    substituters = [ "https://devenv.cachix.org" ];
    trusted-public-keys = [ "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=" ];
  };
}
