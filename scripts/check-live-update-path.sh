#!/usr/bin/env bash
#
# Exercises the live older-release -> latest-release updater path against a temp
# app bundle. The release workflow runs this after publish; local/CI runs may use
# it against already-published releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

repo="${OURO_MD_RELEASE_REPO:-ourostack/ouro-md}"
api="https://api.github.com/repos/${repo}/releases?per_page=30"
tmp="$(mktemp -d /tmp/ouro-md-live-update.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v ditto >/dev/null 2>&1 || fail "ditto is required"

echo "==> reading releases from $repo"
curl -fsSL -H 'Accept: application/vnd.github+json' -H "User-Agent: OuroMD/live-update-check" \
  "$api" > "$tmp/releases.json"

latest_version="${OURO_MD_LIVE_UPDATE_TO_VERSION:-}"
if [[ -z "$latest_version" ]]; then
  latest_version="$(jq -r '[.[] | select(.draft == false and .prerelease == false)][0].tag_name | sub("^v"; "")' "$tmp/releases.json")"
fi
[[ -n "$latest_version" && "$latest_version" != "null" ]] || fail "could not resolve latest published release"

from_version="${OURO_MD_LIVE_UPDATE_FROM_VERSION:-}"
if [[ -z "$from_version" ]]; then
  from_version="$(jq -r --arg latest "v$latest_version" '[.[] | select(.draft == false and .prerelease == false and .tag_name != $latest)][0].tag_name | sub("^v"; "")' "$tmp/releases.json")"
fi
[[ -n "$from_version" && "$from_version" != "null" ]] || fail "could not resolve an older published release"
[[ "$from_version" != "$latest_version" ]] || fail "older and latest versions are both $latest_version"

from_zip="Ouro-MD-${from_version}.zip"
from_url="$(jq -r --arg tag "v$from_version" --arg name "$from_zip" '
  .[] | select(.tag_name == $tag) | .assets[] | select(.name == $name) | .browser_download_url
' "$tmp/releases.json" | head -1)"
[[ -n "$from_url" && "$from_url" != "null" ]] || fail "could not find $from_zip on release v$from_version"

echo "==> downloading older release $from_version"
curl -fL "$from_url" -o "$tmp/$from_zip"
mkdir -p "$tmp/older" "$tmp/install"
ditto -x -k "$tmp/$from_zip" "$tmp/older"

older_app="$(find "$tmp/older" -type d -name 'Ouro MD.app' -prune -print -quit)"
[[ -n "$older_app" && -d "$older_app" ]] || fail "older release archive did not contain Ouro MD.app"
dest="$tmp/install/Ouro MD.app"
ditto "$older_app" "$dest"

installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$dest/Contents/Info.plist")"
[[ "$installed_version" == "$from_version" ]] || fail "older app version $installed_version did not match $from_version"

exe="${OURO_MD_EXE:-.build/debug/ouro-md}"
if [[ ! -x "$exe" ]]; then
  swift build
fi
[[ -x "$exe" ]] || fail "ouro-md executable not found or not executable: $exe"

echo "==> exercising live updater $from_version -> $latest_version"
"$exe" \
  --liveupdatetest \
  --live-update-from-version "$from_version" \
  --live-update-to-version "$latest_version" \
  --live-update-destination "$dest"

echo "live update path verified: $from_version -> $latest_version"
