#!/usr/bin/env bash
set -Eeuo pipefail

flake_dir="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
orca_file="$flake_dir/modules/packages/orca.nix"
cindy_file="$flake_dir/modules/packages/cindy.nix"

current_version() {
  sed -nE 's/^[[:space:]]*version = "([0-9]+\.[0-9]+\.[0-9]+)";.*/\1/p' "$1" | head -n1
}

echo "Checking official stable Orca release..."
orca_release="$(curl --fail --silent --show-error --location \
  https://api.github.com/repos/stablyai/orca/releases/latest)"
orca_version="$(jq -er '.tag_name | ltrimstr("v")' <<<"$orca_release")"
orca_url="$(jq -er '[.assets[] | select(.name == "orca-linux.AppImage")][0].browser_download_url' \
  <<<"$orca_release")"
[[ "$orca_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Unexpected Orca release version: $orca_version" >&2
  exit 1
}
[[ "$orca_url" == "https://github.com/stablyai/orca/releases/download/v$orca_version/orca-linux.AppImage" ]] || {
  echo "Unexpected Orca AppImage URL: $orca_url" >&2
  exit 1
}
if [[ "$(current_version "$orca_file")" != "$orca_version" ]]; then
  echo "Pinning Orca $orca_version and verifying its AppImage hash..."
  orca_hash="$(nix store prefetch-file --json "$orca_url" | jq -er .hash)"
  ORCA_VERSION="$orca_version" ORCA_HASH="$orca_hash" python3 - "$orca_file" <<'PY'
from pathlib import Path
import os, re, sys

path = Path(sys.argv[1])
text = path.read_text()
text, versions = re.subn(r'(?m)^(\s*version = ")[0-9]+\.[0-9]+\.[0-9]+(";)$',
                         rf'\g<1>{os.environ["ORCA_VERSION"]}\2', text, count=1)
text, hashes = re.subn(r'(?m)^(\s*hash = ")[^"]+(";)$',
                       rf'\g<1>{os.environ["ORCA_HASH"]}\2', text, count=1)
if versions != 1 or hashes != 1:
    raise SystemExit("Could not safely update the Orca version and hash pins")
path.write_text(text)
PY
else
  echo "Orca is already pinned to $orca_version."
fi

echo "Checking official stable Cindy package manifest..."
cindy_manifest="$(curl --fail --silent --show-error --location \
  https://hotfix.cindy.app/cindy/manifest-linux-x64.json)"
cindy_version="$(jq -er '.app.version' <<<"$cindy_manifest")"
cindy_file_name="$(jq -er '.app.installer.file' <<<"$cindy_manifest")"
cindy_sha256="$(jq -er '.app.installer.sha256' <<<"$cindy_manifest")"
[[ "$cindy_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Unexpected Cindy release version: $cindy_version" >&2
  exit 1
}
[[ "$cindy_file_name" =~ ^app/linux-x64/cindy-[0-9]+\.[0-9]+\.[0-9]+-amd64\.deb$ ]] || {
  echo "Unexpected Cindy package path: $cindy_file_name" >&2
  exit 1
}
[[ "$cindy_sha256" =~ ^[a-fA-F0-9]{64}$ ]] || {
  echo "Unexpected Cindy package SHA-256 in manifest" >&2
  exit 1
}
cindy_url="https://hotfix.cindy.app/cindy/$cindy_file_name"
if [[ "$(current_version "$cindy_file")" != "$cindy_version" ]]; then
  echo "Pinning Cindy $cindy_version from its official manifest..."
  CINDY_VERSION="$cindy_version" CINDY_HASH="$cindy_sha256" CINDY_URL="$cindy_url" \
    python3 - "$cindy_file" <<'PY'
from pathlib import Path
import os, re, sys

path = Path(sys.argv[1])
text = path.read_text()
text, versions = re.subn(r'(?m)^(\s*version = ")[0-9]+\.[0-9]+\.[0-9]+(";)$',
                         rf'\g<1>{os.environ["CINDY_VERSION"]}\2', text, count=1)
text, urls = re.subn(r'(?m)^(\s*url = ")[^"]+(";)$',
                     rf'\g<1>{os.environ["CINDY_URL"]}\2', text, count=1)
text, hashes = re.subn(r'(?m)^(\s*sha256 = ")[^"]+(";)$',
                       rf'\g<1>{os.environ["CINDY_HASH"]}\2', text, count=1)
if versions != 1 or urls != 1 or hashes != 1:
    raise SystemExit("Could not safely update the Cindy version, URL, and hash pins")
path.write_text(text)
PY
else
  echo "Cindy is already pinned to $cindy_version."
fi
