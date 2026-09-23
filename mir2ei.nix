{ pkgs, ... }:

{
  # System toolchain for the Mir3-EI / Zircon research tools. The tools share
  # the system Python for their lightweight services; dbeditor/uieditor still
  # install their pinned application requirements into local uv environments.
  environment.systemPackages = with pkgs; [
    uv
    dotnet-sdk
    godot-mono

    python3
    python3Packages.fastapi
    python3Packages.uvicorn
    python3Packages.websockets
    python3Packages.httptools
    python3Packages.watchfiles
    python3Packages.pyyaml
    python3Packages.pillow
    python3Packages.numpy
  ];

  # Keep uv on the NixOS-provided Python instead of downloading a private
  # interpreter. Tool-specific venvs remain local to their tool directories.
  environment.sessionVariables = {
    UV_PYTHON_PREFERENCE = "only-system";

    MIR3_ZIRCON_ROOT = "/home/tetsuya/development/Zircon";
    MIR3_ZIRCON_CLIENT = "/home/tetsuya/development/Zircon/Debug/Client";
    ZIRCON_ROOT = "/home/tetsuya/development/Zircon";
    MIR3_EI_ROOT = "/home/tetsuya/mir3ei";
    MIR3EI_ROOT = "/home/tetsuya/mir3ei";

    # NAS-backed source data is mounted on demand at this location.
    MIR3_NAS_TMP = "/home/tetsuya/NAS/TMP";
    MIR3_MUD3_ROOT = "/home/tetsuya/NAS/TMP/Mud3";
  };
}
