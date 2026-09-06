#!/usr/bin/env bash
set -euo pipefail

theme_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
greeter="$(command -v sddm-greeter-qt6 || command -v sddm-greeter || true)"

if [[ -z "$greeter" ]]; then
  echo "No SDDM greeter executable found (tried sddm-greeter-qt6 and sddm-greeter)." >&2
  exit 1
fi

if command -v cage >/dev/null 2>&1; then
  exec cage -- "$greeter" --test-mode --theme "$theme_dir"
fi

echo "cage is not installed; starting the regular SDDM theme preview." >&2
exec "$greeter" --test-mode --theme "$theme_dir"
