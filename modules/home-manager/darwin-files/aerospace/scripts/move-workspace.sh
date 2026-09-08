#!/usr/bin/env bash
set -euo pipefail
export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:$PATH"
AEROSPACE="$(command -v aerospace || echo /opt/homebrew/bin/aerospace)"
NUM="${1:-1}"
MODE="${2:-follow}" # follow or silent
MON_ID="$("$AEROSPACE" list-monitors --focused --format '%{monitor-id}' 2>/dev/null || echo 1)"
[ -n "$MON_ID" ] || MON_ID=1
if [ "$MODE" = "follow" ]; then
  exec "$AEROSPACE" move-node-to-workspace "${MON_ID}-${NUM}" --focus-follows-window
else
  exec "$AEROSPACE" move-node-to-workspace "${MON_ID}-${NUM}"
fi
