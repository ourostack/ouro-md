#!/usr/bin/env bash
#
# Builds and packages Ouro MD for Mac App Store upload.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="OuroMD.app"
OUT_DIR="dist/app-store"
ENTITLEMENTS="config/app-store-entitlements.plist"

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/package-app-store.sh [--validate] [--upload]

Required env:
  OURO_APP_STORE_APP_IDENTITY        app signing identity
  OURO_APP_STORE_INSTALLER_IDENTITY  pkg signing identity

Optional env:
  OURO_APP_STORE_PROVISIONING_PROFILE  path to a Mac App Store provisioning profile

Validation/upload auth, choose one:
  APP_STORE_CONNECT_API_KEY_ID + APP_STORE_CONNECT_API_ISSUER_ID
  APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD

If the account has multiple providers, set APP_STORE_CONNECT_PROVIDER_PUBLIC_ID.
USAGE
}

validate=0
upload=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate) validate=1; shift ;;
    --upload) upload=1; validate=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

[[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements: $ENTITLEMENTS"
command -v codesign >/dev/null 2>&1 || fail "codesign is required"
command -v productbuild >/dev/null 2>&1 || fail "productbuild is required"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
xcrun altool --help >/dev/null 2>&1 || fail "xcrun altool is required"

APP_IDENTITY="${OURO_APP_STORE_APP_IDENTITY:-}"
INSTALLER_IDENTITY="${OURO_APP_STORE_INSTALLER_IDENTITY:-}"
[[ -n "$APP_IDENTITY" ]] || fail "OURO_APP_STORE_APP_IDENTITY is required"
[[ -n "$INSTALLER_IDENTITY" ]] || fail "OURO_APP_STORE_INSTALLER_IDENTITY is required"
security find-identity -v -p codesigning | grep -Fq "$APP_IDENTITY" \
  || fail "app signing identity was not found in this keychain"
security find-identity -v | grep -Fq "$INSTALLER_IDENTITY" \
  || fail "installer signing identity was not found in this keychain"

OURO_MD_DISTRIBUTION_CHANNEL=app-store ./make-app.sh

if [[ -n "${OURO_APP_STORE_PROVISIONING_PROFILE:-}" ]]; then
  [[ -f "$OURO_APP_STORE_PROVISIONING_PROFILE" ]] || fail "provisioning profile not found"
  cp "$OURO_APP_STORE_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$APP_IDENTITY" \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
channel="$(/usr/libexec/PlistBuddy -c 'Print :OuroMDDistributionChannel' "$APP/Contents/Info.plist")"
[[ "$channel" == "app-store" ]] || fail "expected app-store distribution channel, got $channel"

mkdir -p "$OUT_DIR"
pkg="$OUT_DIR/Ouro-MD-${version}-app-store.pkg"
rm -f "$pkg"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$pkg"

auth_args=()
if [[ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" && -n "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]]; then
  auth_args=(--api-key "$APP_STORE_CONNECT_API_KEY_ID" --api-issuer "$APP_STORE_CONNECT_API_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  auth_args=(--username "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
else
  auth_args=()
fi
if [[ -n "${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-}" ]]; then
  auth_args+=(--provider-public-id "$APP_STORE_CONNECT_PROVIDER_PUBLIC_ID")
fi

if [[ "$validate" == "1" || "$upload" == "1" ]]; then
  [[ "${#auth_args[@]}" -gt 0 ]] || fail "App Store validation/upload requires App Store Connect auth env"
  xcrun altool --validate-app "$pkg" "${auth_args[@]}" --output-format json
fi

if [[ "$upload" == "1" ]]; then
  xcrun altool --upload-package "$pkg" "${auth_args[@]}" --output-format json --wait
fi

echo "app store package ready: $pkg"
echo "bundle id: $bundle_id"
echo "version: $version"
