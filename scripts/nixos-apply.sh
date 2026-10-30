#!/usr/bin/env bash
# nixos-apply.sh — shared deploy entrypoint for the nixos-config pipeline.
#   --controller : apply a CI-verified ref deterministically (no input float)
#   --fallback   : controller unreachable -> run full local `nixos-update`
#   --ref REF    : git ref to deploy in controller mode (default: main)
#   --flake-dir DIR
#   --dry-run    : print actions, change nothing
# Safety: never `git reset --hard`; uncommitted work is stashed and restored.
set -Eeuo pipefail

FLAKE_DIR="${NIXOS_CONFIG:-$HOME/nixos-config}"
HOST="$(hostname -s)"
MODE=""
REF="main"
DRY_RUN=0
FALLBACK_GRACE_HOURS=26
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nixos-deploy"
SENTINEL="$STATE_DIR/last-controller-apply"
LOCK="$STATE_DIR/lock"

while (($# > 0)); do
  case "$1" in
    --controller) MODE=controller ;;
    --fallback)   MODE=fallback ;;
    --ref)        REF="${2:-}"; shift ;;
    --flake-dir)  FLAKE_DIR="${2:-}"; shift ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -n "$MODE" ]] || { echo "error: specify --controller or --fallback" >&2; exit 2; }
[[ -d "$FLAKE_DIR/.git" ]] || { echo "error: not a git repo: $FLAKE_DIR" >&2; exit 1; }

log() { echo "[nixos-apply $(date +%T)] $*"; }
run() { if ((DRY_RUN)); then printf '  (dry-run)'; printf ' %q' "$@"; echo; else "$@"; fi; }

STASH_REF=""
cleanup() {
  local rc=$?
  if [[ -n "$STASH_REF" ]]; then
    log "restoring stashed work ($STASH_REF)…"
    if ! git -C "$FLAKE_DIR" stash pop "$STASH_REF" 2>/dev/null; then
      log "WARN: stash pop failed — work remains in '$STASH_REF'; resolve manually."
    fi
  fi
  exit $rc
}
trap cleanup EXIT

# Single instance: never let controller and fallback run a rebuild concurrently.
mkdir -p "$STATE_DIR"
exec 9>"$LOCK"
flock -n 9 || { echo "error: another nixos-apply is running" >&2; exit 1; }

# Fallback gating: skip if the controller applied recently.
if [[ "$MODE" == fallback ]]; then
  if [[ -f "$SENTINEL" ]]; then
    age_h=$(( ( $(date +%s) - $(stat -c %Y "$SENTINEL") ) / 3600 ))
    if (( age_h < FALLBACK_GRACE_HOURS )); then
      log "controller applied ${age_h}h ago (< ${FALLBACK_GRACE_HOURS}h grace) — fallback skipped."
      exit 0
    fi
    log "controller last seen ${age_h}h ago — running fallback update."
  else
    log "no controller sentinel — running fallback update."
  fi
fi

# Stash uncommitted work so the tree is clean for build/checkout.
if ((DRY_RUN == 0)) && [[ -n "$(git -C "$FLAKE_DIR" status --porcelain)" ]]; then
  log "stashing uncommitted changes…"
  STASH_REF="$(git -C "$FLAKE_DIR" stash push --include-untracked -m "nixos-apply auto-stash $(date -Iseconds)")"
  log "stashed: $STASH_REF"
fi

if [[ "$MODE" == controller ]]; then
  log "controller mode: deploying ref '$REF' (deterministic, no input float)"
  run git -C "$FLAKE_DIR" fetch origin "$REF"
  run git -C "$FLAKE_DIR" checkout --detach "origin/$REF"
  run sudo nixos-rebuild switch --impure --flake "$FLAKE_DIR#$HOST"
  log "writing controller sentinel…"
  run mkdir -p "$STATE_DIR"
  run touch "$SENTINEL"
else
  log "fallback mode: running full nixos-update (floats inputs + omarchy plugins)"
  run "$FLAKE_DIR/scripts/nixos-update.sh" --yes
fi

log "done."
