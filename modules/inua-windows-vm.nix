{ config, lib, pkgs, ... }:

let
  cfg = config.services.inuaWindowsVm;
in
{
  options.services.inuaWindowsVm = {
    enable = lib.mkEnableOption "NixOS prerequisites for Inua Windows VM";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      defaultText = lib.literalExpression "null";
      example = lib.literalExpression "pkgs.inua";
      description = ''
        Inua package to install, when the host provides one (for example
        pkgs.inua). Null installs only the VM prerequisites; pass your own
        package from a flake input when nixpkgs does not carry inua.
      '';
    };

    enableDocker = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the Docker daemon and install Docker Compose v2 for the Windows VM backend.";
    };

    dockerUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Explicitly add these users to the docker group for Docker socket access.
        Membership grants root-equivalent host control. The module never adds
        users unless this option is set explicitly.
      '';
    };

    installFreeRdp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install FreeRDP for connecting to the Windows guest.";
    };

    installKvmTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install QEMU utilities used to inspect host KVM support; does not select host-specific CPU kernel modules.";
    };
  };

	config = lib.mkIf cfg.enable {
		environment.systemPackages = lib.optional (cfg.package != null) cfg.package
			++ lib.optionals cfg.enableDocker [ pkgs.docker-compose ]
			++ lib.optionals cfg.installFreeRdp [ pkgs.freerdp ]
			++ lib.optionals cfg.installKvmTools [ pkgs.qemu-utils ];
		virtualisation.docker.enable = cfg.enableDocker;
		users.groups.docker.members = cfg.dockerUsers;
	};
}
