{ lib, pkgs, inputs }:

# NixOS does not provide the FHS layout assumed by the upstream Omarchy
# Windows VM helper. Keep the upstream source intact and adapt the package at
# the NixOS boundary instead.
(pkgs.extend inputs.nixarchy.overlays.default).omarchy.overrideAttrs (old: {
  installPhase = lib.replaceStrings [ "\n            " ] [ "\n" ] old.installPhase;

  postInstall = (old.postInstall or "") + ''
    vm_helper="$out/share/omarchy/bin/omarchy-windows-vm"

    # NixOS uses /nix/store and /run/current-system/sw instead of the FHS
    # /usr/bin layout expected by the upstream Arch helper.
    substituteInPlace "$vm_helper" \
      --replace-fail \
        'export PATH=/usr/bin:/usr/sbin:/bin:/sbin' \
        'export PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/bin:/usr/sbin:/bin:/sbin'

    # Keep the upstream ownership/mode checks, but use the canonical
    # immutable script that is currently executing as the pkexec target.
    substituteInPlace "$vm_helper" \
      --replace-fail \
        'local candidate=/usr/bin/omarchy-windows-vm canonical probe owner mode' \
        'local candidate canonical probe owner mode
  candidate=$(realpath -e -- "''${BASH_SOURCE[0]}" 2>/dev/null) || return 1'

    # /nix/store is intentionally root-owned and sticky but group-writable
    # (1775) for Nix build users. Treat only that exact boundary as the
    # immutable-store exception; all other parents keep the upstream check.
    substituteInPlace "$vm_helper" \
      --replace-fail \
        '[[ $owner == 0 ]] && ! ((8#$mode & 022)) || return 1' \
        'if [[ $probe == /nix/store ]]; then
      [[ $owner == 0 && $mode == 1775 ]] || return 1
    else
      [[ $owner == 0 ]] && ! ((8#$mode & 022)) || return 1
    fi'

    # NixOS exposes Compose v2 as `docker compose`, not docker-compose.
    substituteInPlace "$vm_helper" \
      --replace-fail \
        'dc() { docker-compose -f "$COMPOSE_FILE" "$@"; }' \
        'dc() { docker compose -f "$COMPOSE_FILE" "$@"; }'

    # These helpers run after the root-side PATH is pinned.
    substituteInPlace "$vm_helper" \
      --replace-fail \
        'TREE_SCAN_TIMEOUT=/usr/bin/timeout' \
        'TREE_SCAN_TIMEOUT=/run/current-system/sw/bin/timeout' \
      --replace-fail \
        'TREE_SCAN_FIND=/usr/bin/find' \
        'TREE_SCAN_FIND=/run/current-system/sw/bin/find'
  '';
})
