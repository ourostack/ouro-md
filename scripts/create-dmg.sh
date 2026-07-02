#!/usr/bin/env bash
#
# Creates a standard drag-to-Applications macOS DMG from an already-built .app.
set -euo pipefail

APP_PATH=""
OUT_PATH=""
VOLUME_NAME=""
TMP_ROOT=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/create-dmg.sh --app PATH --out PATH --volume-name NAME
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 && -n "$2" ]] || { usage; exit 64; }
      APP_PATH="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 && -n "$2" ]] || { usage; exit 64; }
      OUT_PATH="$2"
      shift 2
      ;;
    --volume-name)
      [[ $# -ge 2 && -n "$2" ]] || { usage; exit 64; }
      VOLUME_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

[[ -n "$APP_PATH" ]] || { usage; exit 64; }
[[ -n "$OUT_PATH" ]] || { usage; exit 64; }
[[ -n "$VOLUME_NAME" ]] || { usage; exit 64; }
[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is required"

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
OUT_DIR="$(cd "$(dirname "$OUT_PATH")" && pwd)"
OUT_PATH="$OUT_DIR/$(basename "$OUT_PATH")"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ouro-md-dmg.XXXXXX")"
STAGE="$TMP_ROOT/stage"

mkdir -p "$STAGE"
ditto "$APP_PATH" "$STAGE/$(basename "$APP_PATH")"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$OUT_PATH" >/dev/null

codesign --verify --deep --strict "$APP_PATH"
echo "dmg created: $OUT_PATH"
