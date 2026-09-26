#!/usr/bin/env bash
# Labwc clipboard history backend. Reads a wl-paste payload, stores it in a
# private user state directory, and emits the JSON entry for diagnostics.
set -o pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/labwc"
image_dir="$state_dir/clipboard-images"
history_path="$state_dir/clipboard-history.json"
mkdir -p "$image_dir"

# Preserve the existing history when migrating away from Omarchy.
legacy_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
if [[ ! -e "$history_path" && -f "$legacy_dir/clipboard-history.json" ]]; then
  cp -- "$legacy_dir/clipboard-history.json" "$history_path"
  if [[ -d "$legacy_dir/clipboard-images" ]]; then
    cp -a -- "$legacy_dir/clipboard-images/." "$image_dir/"
  fi
fi

# Rewrite migrated image entries so the UI no longer depends on the legacy
# Omarchy state tree. Keep the old tree untouched as a user-owned backup.
python3 - "$history_path" "$legacy_dir" "$image_dir" <<'PY'
import json
import os
import shutil
import sys
import tempfile

history_path, legacy_dir, image_dir = sys.argv[1:]
try:
    with open(history_path, encoding="utf-8") as handle:
        history = json.load(handle)
except (FileNotFoundError, json.JSONDecodeError):
    history = []
if not isinstance(history, list):
    raise SystemExit(0)

changed = False
legacy_images = os.path.join(legacy_dir, "clipboard-images")
for entry in history:
    if not isinstance(entry, dict) or entry.get("type") != "image":
        continue
    old_path = entry.get("path")
    if not isinstance(old_path, str) or not old_path.startswith(legacy_images + os.sep):
        continue
    filename = os.path.basename(old_path)
    new_path = os.path.join(image_dir, filename)
    if os.path.isfile(old_path) and not os.path.exists(new_path):
        shutil.copy2(old_path, new_path)
    entry["path"] = new_path
    changed = True

if changed:
    directory = os.path.dirname(history_path)
    fd, temporary = tempfile.mkstemp(prefix=".clipboard-history-migrated.", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(history, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(temporary, history_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PY

types="$(wl-paste --list-types 2>/dev/null || true)"
if [[ ${CLIPBOARD_STATE:-} == sensitive ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
  exit 0
fi

append_entry() {
  local entry_file
  entry_file="$(mktemp --tmpdir="$state_dir" clipboard-entry.XXXXXX)"
  cat >"$entry_file"
  python3 - "$history_path" "$entry_file" <<'PY'
import json
import os
import sys
import tempfile
import fcntl

history_path = sys.argv[1]
entry_path = sys.argv[2]
with open(entry_path, encoding="utf-8") as handle:
    raw = handle.read().strip()
try:
    os.unlink(entry_path)
except FileNotFoundError:
    pass
if not raw:
    raise SystemExit(0)
try:
    entry = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
if not isinstance(entry, dict) or entry.get("type") not in {"text", "image"}:
    raise SystemExit(0)

lock_path = history_path + ".lock"
with open(lock_path, "a+", encoding="utf-8") as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    try:
        with open(history_path, encoding="utf-8") as handle:
            history = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        history = []
    if not isinstance(history, list):
        history = []
    history = [old for old in history if old != entry]
    history.insert(0, entry)
    history = history[:300]
    directory = os.path.dirname(history_path)
    fd, temporary = tempfile.mkstemp(prefix=".clipboard-history.", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(history, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(temporary, history_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
print(json.dumps(entry, ensure_ascii=False, separators=(",", ":")))
PY
}

emit_image() {
  local mime="$1" ext tmp hash file
  ext="${mime#image/}"
  [[ $ext == jpeg ]] && ext=jpg
  tmp="$(mktemp --tmpdir="$image_dir" clipboard.XXXXXX)" || return 0
  cat >"$tmp"
  [[ -s $tmp ]] || { rm -f -- "$tmp"; return 0; }
  hash="$(sha256sum "$tmp" | awk '{print $1}')"
  file="$image_dir/$hash.$ext"
  if [[ -e $file ]]; then rm -f -- "$tmp"; else mv -- "$tmp" "$file"; fi
  printf '%s\n' "{\"type\":\"image\",\"mime\":\"$mime\",\"path\":\"$file\",\"capturedAt\":\"$(date '+%A %H:%M')\"}" | append_entry
}

emit_text() {
  python3 -c 'import json,sys; value=sys.stdin.buffer.read().decode("utf-8", "replace"); print(json.dumps({"type":"text","text":value}, ensure_ascii=False, separators=(",", ":")))' | append_entry
}

case "${1:-}" in
  text) emit_text; exit 0 ;;
  image/*) emit_image "$1"; exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if grep -qx "$mime" <<<"$types"; then
    timeout 2s wl-paste --type "$mime" 2>/dev/null | emit_image "$mime"
    exit 0
  fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  wl-paste --type text --no-newline 2>/dev/null | emit_text
fi
