#!/usr/bin/env bash
#
# Developer ID signs, notarizes, staples, and verifies a macOS .app bundle.
# Default release builds stay ad-hoc/unsigned; set OURO_RELEASE_SIGNING_MODE=developer-id
# or OURO_REQUIRE_NOTARIZATION=1 to require this path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH=""
APP_NAME=""
TEAM_ID="${APPLE_TEAM_ID:-${OURO_APPLE_TEAM_ID:-743GT2AJ24}}"
IDENTITY="${OURO_CODESIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
NOTARY_PROFILE="${OURO_NOTARY_PROFILE:-}"
TMP_ROOT=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/sign-notarize-app.sh --app PATH [--app-name NAME]
  scripts/sign-notarize-app.sh --selftest

Required for real signing:
  OURO_CODESIGN_IDENTITY or DEVELOPER_ID_APPLICATION

Required for notarization, choose one:
  OURO_NOTARY_PROFILE
  APP_STORE_CONNECT_API_KEY_ID + APP_STORE_CONNECT_API_ISSUER_ID + APP_STORE_CONNECT_API_KEY_PATH
  APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD
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

truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

have_all() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || return 1
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 && -n "$2" ]] || { usage; exit 64; }
      APP_PATH="$2"
      shift 2
      ;;
    --app-name)
      [[ $# -ge 2 && -n "$2" ]] || { usage; exit 64; }
      APP_NAME="$2"
      shift 2
      ;;
    --selftest)
      "$0" --help >/dev/null
      status=0
      "$0" --app /definitely/missing.app >/tmp/ouro-md-sign-notarize-selftest.out 2>/tmp/ouro-md-sign-notarize-selftest.err || status=$?
      [[ "$status" -ne 0 ]] || fail "selftest expected missing app to fail"
      echo "sign-notarize selftest ok"
      exit 0
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
[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
APP_NAME="${APP_NAME:-$(basename "$APP_PATH" .app)}"

command -v codesign >/dev/null 2>&1 || fail "codesign is required"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
xcrun notarytool --help >/dev/null 2>&1 || fail "xcrun notarytool is required"
xcrun -f stapler >/dev/null 2>&1 || fail "xcrun stapler is required"

[[ -n "$IDENTITY" ]] || fail "Developer ID signing requires OURO_CODESIGN_IDENTITY or DEVELOPER_ID_APPLICATION"
security find-identity -v -p codesigning | grep -Fq "$IDENTITY" \
  || fail "configured signing identity was not found in this keychain"

notary_args=()
if [[ -n "$NOTARY_PROFILE" ]]; then
  notary_args=(--keychain-profile "$NOTARY_PROFILE")
elif have_all APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_API_ISSUER_ID APP_STORE_CONNECT_API_KEY_PATH; then
  [[ -f "$APP_STORE_CONNECT_API_KEY_PATH" ]] || fail "APP_STORE_CONNECT_API_KEY_PATH does not point to a file"
  notary_args=(
    --key "$APP_STORE_CONNECT_API_KEY_PATH"
    --key-id "$APP_STORE_CONNECT_API_KEY_ID"
    --issuer "$APP_STORE_CONNECT_API_ISSUER_ID"
  )
elif have_all APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; then
  notary_args=(
    --apple-id "$APPLE_ID"
    --team-id "$APPLE_TEAM_ID"
    --password "$APPLE_APP_SPECIFIC_PASSWORD"
  )
else
  fail "notarization requires OURO_NOTARY_PROFILE, App Store Connect API key env, or Apple ID app-specific password env"
fi

echo "==> Developer ID signing ${APP_PATH}"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ouro-md-notary.XXXXXX")"
notary_zip="$TMP_ROOT/${APP_NAME}-notary.zip"
echo "==> Creating notarization upload ${notary_zip}"
ditto -c -k --keepParent "$APP_PATH" "$notary_zip"

echo "==> Submitting to Apple notary service"
xcrun notarytool submit "$notary_zip" "${notary_args[@]}" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

if command -v spctl >/dev/null 2>&1; then
  spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

echo "developer-id notarization ok: $APP_PATH"
