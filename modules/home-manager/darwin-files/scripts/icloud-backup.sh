#!/usr/bin/env bash
#
# Sync iCloud Drive to the NAS backup volume.
#
# This is intentionally a macOS-only Home Manager file. The script refuses to
# run on other systems and refuses to run when either path is unavailable.

set -euo pipefail

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
NAS_BACKUP_DIR="/Volumes/NAS/Backups/iCloud"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok() { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err() { printf "${RED}[ERR]${NC}   %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script only runs on macOS"
[[ -d "$ICLOUD_DIR" ]] || die "iCloud Drive not found: $ICLOUD_DIR"
[[ -d "$NAS_BACKUP_DIR" ]] || die "NAS backup directory not found: $NAS_BACKUP_DIR\nPlease mount NAS first."
command -v rsync >/dev/null 2>&1 || die "rsync is required"

info "Starting iCloud backup..."
info "Source: $ICLOUD_DIR"
info "Target: $NAS_BACKUP_DIR"
echo

rsync -avh --progress \
  --delete \
  --exclude='.DS_Store' \
  --exclude='.Trash' \
  --exclude='.Spotlight-V100' \
  --exclude='.TemporaryItems' \
  "$ICLOUD_DIR/" \
  "$NAS_BACKUP_DIR/"

echo
ok "iCloud backup completed!"
