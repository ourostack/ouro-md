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
  scripts/package-app-store.sh [--readiness] [--validate] [--upload]

Required env:
  OURO_APP_STORE_APP_IDENTITY        app signing identity
  OURO_APP_STORE_INSTALLER_IDENTITY  pkg signing identity

Optional env:
  OURO_APP_STORE_PROVISIONING_PROFILE  path to a Mac App Store provisioning profile
  APP_STORE_CONNECT_API_KEY_PATH        path to AuthKey_<key-id>.p8
  OURO_MD_APP_STORE_ENABLE_TELEMETRY=1  opt in to embedded telemetry for App Store builds

Validation/upload auth, choose one:
  APP_STORE_CONNECT_API_KEY_ID + APP_STORE_CONNECT_API_ISSUER_ID
  APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD

If the account has multiple providers, set APP_STORE_CONNECT_PROVIDER_PUBLIC_ID.
USAGE
}

validate=0
upload=0
readiness=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --readiness) readiness=1; shift ;;
    --validate) validate=1; shift ;;
    --upload) upload=1; validate=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

have_all() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || return 1
  done
}

require_tooling() {
  [[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements: $ENTITLEMENTS"
  command -v codesign >/dev/null 2>&1 || fail "codesign is required"
  command -v productbuild >/dev/null 2>&1 || fail "productbuild is required"
  command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
  xcrun altool --help >/dev/null 2>&1 || fail "xcrun altool is required"
}

require_identity_env() {
  local env_name="$1"
  local hint="$2"
  [[ -n "${!env_name:-}" ]] || fail "$env_name is required, for example: $hint"
}

require_app_store_identities() {
  APP_IDENTITY="${OURO_APP_STORE_APP_IDENTITY:-}"
  INSTALLER_IDENTITY="${OURO_APP_STORE_INSTALLER_IDENTITY:-}"
  require_identity_env OURO_APP_STORE_APP_IDENTITY '3rd Party Mac Developer Application: Ari Mendelow (743GT2AJ24)'
  require_identity_env OURO_APP_STORE_INSTALLER_IDENTITY '3rd Party Mac Developer Installer: Ari Mendelow (743GT2AJ24)'
  security find-identity -v -p codesigning | grep -Fq "$APP_IDENTITY" \
    || fail "app signing identity was not found in this keychain: $APP_IDENTITY"
  security find-identity -v | grep -Fq "$INSTALLER_IDENTITY" \
    || fail "installer signing identity was not found in this keychain: $INSTALLER_IDENTITY"
}

build_auth_args() {
  auth_args=()
  if have_all APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_API_ISSUER_ID; then
    auth_args=(--api-key "$APP_STORE_CONNECT_API_KEY_ID" --api-issuer "$APP_STORE_CONNECT_API_ISSUER_ID")
    if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
      [[ -f "$APP_STORE_CONNECT_API_KEY_PATH" ]] || fail "APP_STORE_CONNECT_API_KEY_PATH does not point to a file"
      auth_args+=(--p8-file-path "$APP_STORE_CONNECT_API_KEY_PATH")
    fi
  elif have_all APPLE_ID APPLE_APP_SPECIFIC_PASSWORD; then
    auth_args=(--username "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
  else
    auth_args=()
  fi
  if [[ -n "${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-}" ]]; then
    auth_args+=(--provider-public-id "$APP_STORE_CONNECT_PROVIDER_PUBLIC_ID")
  fi
}

run_adk_xcode() {
  ./scripts/apple-distribution-kit.sh xcode run --mode apply "$@"
}

print_readiness() {
  require_tooling
  require_app_store_identities
  if [[ -n "${OURO_APP_STORE_PROVISIONING_PROFILE:-}" ]]; then
    [[ -f "$OURO_APP_STORE_PROVISIONING_PROFILE" ]] || fail "provisioning profile not found"
    echo "provisioning profile: $OURO_APP_STORE_PROVISIONING_PROFILE"
  else
    echo "provisioning profile: none configured"
  fi
  build_auth_args
  [[ "${#auth_args[@]}" -gt 0 ]] || fail "App Store validation/upload requires App Store Connect auth env"
  echo "app identity: $APP_IDENTITY"
  echo "installer identity: $INSTALLER_IDENTITY"
  echo "app-store auth: configured"
}

if [[ "$readiness" == "1" ]]; then
  print_readiness
  exit 0
fi

require_tooling
require_app_store_identities

make_app_env=(OURO_MD_DISTRIBUTION_CHANNEL=app-store)
if [[ "${OURO_MD_APP_STORE_ENABLE_TELEMETRY:-}" != "1" ]]; then
  make_app_env+=(OURO_MD_TELEMETRY_DISABLED=1)
fi
env "${make_app_env[@]}" ./make-app.sh

if [[ -n "${OURO_APP_STORE_PROVISIONING_PROFILE:-}" ]]; then
  [[ -f "$OURO_APP_STORE_PROVISIONING_PROFILE" ]] || fail "provisioning profile not found"
  cp "$OURO_APP_STORE_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

run_adk_xcode \
  --kind codesign \
  --identity "$APP_IDENTITY" \
  --path "$APP" \
  --entitlements "$ENTITLEMENTS"
codesign --verify --deep --strict --verbose=2 "$APP"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
channel="$(/usr/libexec/PlistBuddy -c 'Print :OuroMDDistributionChannel' "$APP/Contents/Info.plist")"
uses_non_exempt_encryption="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP/Contents/Info.plist")"
[[ "$bundle_id" == "bot.ouro.md" ]] || fail "expected canonical bundle id bot.ouro.md, got $bundle_id"
[[ "$channel" == "app-store" ]] || fail "expected app-store distribution channel, got $channel"
[[ "$uses_non_exempt_encryption" == "false" ]] || fail "expected ITSAppUsesNonExemptEncryption=false, got $uses_non_exempt_encryption"
if [[ "${OURO_MD_APP_STORE_ENABLE_TELEMETRY:-}" != "1" ]] \
  && /usr/libexec/PlistBuddy -c 'Print :OuroMDPostHogKey' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  fail "App Store package must not embed telemetry unless OURO_MD_APP_STORE_ENABLE_TELEMETRY=1"
fi

mkdir -p "$OUT_DIR"
pkg="$OUT_DIR/Ouro-MD-${version}-app-store.pkg"
rm -f "$pkg"
run_adk_xcode \
  --kind productbuild \
  --identity "$INSTALLER_IDENTITY" \
  --component "$APP" \
  --install-location /Applications \
  --output "$pkg"

build_auth_args

if [[ "$validate" == "1" || "$upload" == "1" ]]; then
  [[ "${#auth_args[@]}" -gt 0 ]] || fail "App Store validation/upload requires App Store Connect auth env"
  run_adk_xcode --kind altool-validate --package-path "$pkg" "${auth_args[@]}"
fi

if [[ "$upload" == "1" ]]; then
  run_adk_xcode --kind altool-upload --package-path "$pkg" "${auth_args[@]}"
fi

echo "app store package ready: $pkg"
echo "bundle id: $bundle_id"
echo "version: $version"
