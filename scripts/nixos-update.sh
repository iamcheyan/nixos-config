#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  nixos-update [--yes] [--allow-dirty]
  nixos-update check
  nixos-update list
  nixos-update show <transaction-id>

The default action snapshots / and /home, updates Omarchy plugins and the Nix
flake, builds and switches the current NixOS host, then records the result.
EOF
}

flake_dir="${NIXOS_CONFIG:-$HOME/nixos-config}"
host="$(hostname -s)"
history_dir="/var/lib/nixos-update/history"
sudo_cmd="/run/wrappers/bin/sudo"
[[ -x "$sudo_cmd" ]] || sudo_cmd="$(command -v sudo || true)"
release_api="https://api.github.com/repos/olafkfreund/nixarchy/releases/latest"
yes=false
allow_dirty=false
original_args=("$@")

current_generation() {
  nixos-rebuild list-generations 2>/dev/null \
    | awk '$NF == "True" { print $1; exit }' \
    || true
}

record_path=""
record_tmp=""
write_record() {
  [[ -n "$record_path" && -f "$record_tmp" ]] || return 0
  "$sudo_cmd" install -d -m 0755 "$history_dir"
  "$sudo_cmd" install -o root -g root -m 0644 "$record_tmp" "$record_path"
}

append_record() {
  printf '%s\n' "$1" >> "$record_tmp"
}

finish() {
  local exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    append_record 'status=success'
  else
    append_record 'status=failed'
    append_record "exit_code=$exit_code"
  fi
  write_record || true
  rm -f "$record_tmp"
  exit "$exit_code"
}

show_history() {
  "$sudo_cmd" find "$history_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null \
    | sort -r \
    || true
}

show_record() {
  local id=${1:-}
  [[ "$id" =~ ^[A-Za-z0-9._:-]+$ ]] || {
    echo "Invalid transaction id: $id" >&2
    exit 2
  }
  "$sudo_cmd" cat "$history_dir/$id" \
    || { echo "Transaction not found: $id" >&2; exit 1; }
}

nixarchy_release() {
  sed -nE 's#^[[:space:]]*url[[:space:]]*=[[:space:]]*"github:olafkfreund/nixarchy/([^"]+)";.*#\1#p' \
    "$flake_dir/flake.nix" | head -n1
}

latest_nixarchy_release() {
  curl --fail --silent --show-error --location --retry 2 \
    --header 'Accept: application/vnd.github+json' \
    "$release_api" | jq --raw-output '.tag_name // empty'
}

check_nixarchy_release() {
  local current latest newest
  current="$(nixarchy_release)"
  [[ "$current" =~ ^v[0-9]+(\.[0-9]+)*(-[0-9]+)?$ ]] || {
    echo "Could not determine the pinned Nixarchy release from flake.nix." >&2
    return 1
  }
  latest="$(latest_nixarchy_release)"
  [[ "$latest" =~ ^v[0-9]+(\.[0-9]+)*(-[0-9]+)?$ ]] || {
    echo "Could not determine the latest Nixarchy release from GitHub." >&2
    return 1
  }
  newest="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)"
  printf 'Nixarchy release: current=%s latest=%s\n' "$current" "$latest"
  if [[ "$current" == "$latest" ]]; then
    printf 'Nixarchy is up to date.\n'
    return 0
  fi
  if [[ "$newest" != "$latest" ]]; then
    printf 'Pinned Nixarchy release is newer than the latest GitHub release; no upgrade suggested.\n'
    return 0
  fi
  printf 'Nixarchy update available: %s -> %s\n' "$current" "$latest"
  return 0
}

upgrade_nixarchy_ref() {
  local latest=$1
  sed -i -E \
    "s#^([[:space:]]*url[[:space:]]*=[[:space:]]*\"github:olafkfreund/nixarchy/)[^\"]+(\";.*)#\\1${latest}\\2#" \
    "$flake_dir/flake.nix"
}

if [[ "${1:-}" == "check" ]]; then
  [[ -f "$flake_dir/flake.nix" ]] || {
    echo "NixOS flake not found: $flake_dir" >&2
    exit 1
  }
  check_nixarchy_release
  exit 0
fi

if [[ "${1:-}" == "list" ]]; then
  show_history
  echo
  "$sudo_cmd" snapper -c root list
  echo
  "$sudo_cmd" snapper -c home list
  exit 0
fi

if [[ "${1:-}" == "show" ]]; then
  show_record "${2:-}"
  exit 0
fi

while (($# > 0)); do
  case "$1" in
    --yes|-y) yes=true ;;
    --allow-dirty) allow_dirty=true ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$flake_dir/flake.nix" ]] || {
  echo "NixOS flake not found: $flake_dir" >&2
  exit 1
}

# Keep SSH-driven updates alive even if a desktop idle policy requests sleep.
if [[ "${NIXOS_UPDATE_INHIBITED:-0}" != 1 ]]; then
  export NIXOS_UPDATE_INHIBITED=1
  exec systemd-inhibit --what=sleep:idle --why="NixOS update in progress" \
    --mode=block "$0" "${original_args[@]}"
fi

current_nixarchy_release="$(nixarchy_release)"
latest_nixarchy_release="$(latest_nixarchy_release)"
[[ "$current_nixarchy_release" =~ ^v[0-9]+(\.[0-9]+)*(-[0-9]+)?$ ]] || {
  echo "Could not determine the pinned Nixarchy release from flake.nix." >&2
  exit 1
}
[[ "$latest_nixarchy_release" =~ ^v[0-9]+(\.[0-9]+)*(-[0-9]+)?$ ]] || {
  echo "Could not determine the latest Nixarchy release from GitHub." >&2
  exit 1
}
nixarchy_upgrade=false
if [[ "$current_nixarchy_release" != "$latest_nixarchy_release" ]] &&
  [[ "$(printf '%s\n%s\n' "$current_nixarchy_release" "$latest_nixarchy_release" | sort -V | tail -n1)" == "$latest_nixarchy_release" ]]; then
  nixarchy_upgrade=true
  printf 'Nixarchy update available: %s -> %s\n' "$current_nixarchy_release" "$latest_nixarchy_release"
else
  printf 'Nixarchy release: %s (latest: %s)\n' "$current_nixarchy_release" "$latest_nixarchy_release"
fi

[[ -n "$sudo_cmd" ]] || { echo "sudo is not available" >&2; exit 1; }
command -v snapper >/dev/null || { echo "snapper is not available" >&2; exit 1; }
command -v omarchy >/dev/null || { echo "omarchy is not available" >&2; exit 1; }
command -v nixos-rebuild >/dev/null || { echo "nixos-rebuild is not available" >&2; exit 1; }

if [[ "$allow_dirty" != true ]] && [[ -n "$(git -C "$flake_dir" status --porcelain)" ]]; then
  echo "NixOS configuration has uncommitted changes." >&2
  echo "Commit them first, or use --allow-dirty and inspect the record afterward." >&2
  exit 1
fi

if [[ "$yes" != true ]]; then
  if [[ "$nixarchy_upgrade" == true ]]; then
    read -r -p "Upgrade Nixarchy to $latest_nixarchy_release, create snapshots, update and switch NixOS? [y/N] " answer
  else
    read -r -p "Create / and /home snapshots, update plugins/flake, and switch NixOS? [y/N] " answer
  fi
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

timestamp="$(date --iso-8601=seconds)"
generation_before="$(current_generation)"
transaction="update-$(date +%Y%m%dT%H%M%S)-generation-${generation_before:-unknown}"
record_path="$history_dir/$transaction"
record_tmp="$(mktemp)"
trap finish EXIT

{
  printf 'transaction=%s\n' "$transaction"
  printf 'host=%s\n' "$host"
  printf 'started_at=%s\n' "$timestamp"
  printf 'generation_before=%s\n' "$generation_before"
  printf 'kernel_before=%s\n' "$(uname -r)"
  printf 'flake_dir=%s\n' "$flake_dir"
  printf 'flake_revision_before=%s\n' "$(git -C "$flake_dir" rev-parse HEAD)"
  printf 'nixarchy_release_before=%s\n' "$current_nixarchy_release"
  printf 'nixarchy_release_latest=%s\n' "$latest_nixarchy_release"
  printf 'flake_dirty_before=%s\n' "$(git -C "$flake_dir" status --porcelain | wc -l)"
  printf 'status=started\n'
} > "$record_tmp"
write_record

if [[ "$nixarchy_upgrade" == true ]]; then
  echo "Updating flake.nix Nixarchy reference to $latest_nixarchy_release..."
  upgrade_nixarchy_ref "$latest_nixarchy_release"
  append_record "nixarchy_release_after=$latest_nixarchy_release"
  write_record
fi

description="nixos-update $transaction"
echo "Creating root snapshot..."
root_snapshot="$({ "$sudo_cmd" snapper -c root create --type single --cleanup-algorithm number \
  --description "$description" --userdata "transaction=$transaction" --print-number; } | tr -d '[:space:]')"
[[ "$root_snapshot" =~ ^[0-9]+$ ]] || { echo "Failed to create root snapshot" >&2; exit 1; }
append_record "root_snapshot=$root_snapshot"
write_record

echo "Creating home snapshot..."
home_snapshot="$({ "$sudo_cmd" snapper -c home create --type single --cleanup-algorithm number \
  --description "$description" --userdata "transaction=$transaction" --print-number; } | tr -d '[:space:]')"
[[ "$home_snapshot" =~ ^[0-9]+$ ]] || { echo "Failed to create home snapshot" >&2; exit 1; }
append_record "home_snapshot=$home_snapshot"
write_record

append_record 'status=snapshots-created'
write_record

echo "Updating Omarchy plugins..."
omarchy plugin update --yes
append_record 'status=plugins-updated'
write_record

echo "Updating Nix flake inputs..."
nix flake update --flake "$flake_dir"
append_record "flake_revision_after_update=$(git -C "$flake_dir" rev-parse HEAD)"
append_record 'status=flake-updated'
write_record

echo "Building NixOS configuration for $host..."
nixos-rebuild build --flake "$flake_dir#$host"
append_record 'status=build-succeeded'
write_record

echo "Switching NixOS configuration..."
"$sudo_cmd" nixos-rebuild switch --flake "$flake_dir#$host"
append_record "generation_after=$(current_generation)"
append_record "kernel_after=$(uname -r)"
append_record "flake_revision_after_switch=$(git -C "$flake_dir" rev-parse HEAD)"
append_record 'status=switch-succeeded'
write_record

echo "Update complete: $transaction"
echo "Snapshots: root=$root_snapshot home=$home_snapshot"
echo "History: $record_path"
