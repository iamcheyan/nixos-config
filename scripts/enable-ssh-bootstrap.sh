#!/usr/bin/env bash
set -euo pipefail

# One-time bootstrap for a freshly installed NixOS system. It overlays SSH
# password-login settings on /etc/nixos/configuration.nix without modifying
# that file or the repository, then applies the overlay with nixos-rebuild.

if [[ "${EUID}" -eq 0 ]]; then
  echo "Please run this as the installed user, not directly as root." >&2
  exit 1
fi

if [[ ! -f /etc/nixos/configuration.nix ]]; then
  echo "Missing /etc/nixos/configuration.nix. Run this on the installed NixOS system." >&2
  exit 1
fi

user_name="${SUDO_USER:-$(id -un)}"

bootstrap_dir="$(mktemp -d)"
trap 'rm -rf "${bootstrap_dir}"' EXIT

cat > "${bootstrap_dir}/configuration.nix" <<EOF
{ lib, ... }:
{
  imports = [ /etc/nixos/configuration.nix ];
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = true;
    KbdInteractiveAuthentication = true;
    PermitRootLogin = "no";
  };
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 22 ];
}
EOF

echo "Applying temporary SSH bootstrap configuration..."
sudo nixos-rebuild switch -I "nixos-config=${bootstrap_dir}/configuration.nix"

echo
echo "SSH is active. Connect using user: ${user_name}"
echo "IPv4 addresses:"
ip -4 -o addr show scope global | awk '{print "  " $4}'
echo
echo "Password authentication is enabled temporarily by this bootstrap."
