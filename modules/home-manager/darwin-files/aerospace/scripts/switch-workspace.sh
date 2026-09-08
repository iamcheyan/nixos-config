#!/usr/bin/env bash
set -euo pipefail
export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:$PATH"
AEROSPACE="$(command -v aerospace || echo /opt/homebrew/bin/aerospace)"
NUM="${1:-1}"
IS_MAIN="$("$AEROSPACE" list-monitors --focused --format '%{monitor-is-main}' 2>/dev/null || echo true)"
if [ "$IS_MAIN" = "true" ]; then
  PREFIX="1"
else
  PREFIX="2"
fi
exec "$AEROSPACE" workspace "${PREFIX}-${NUM}"
