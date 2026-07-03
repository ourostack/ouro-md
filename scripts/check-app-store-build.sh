#!/usr/bin/env bash
#
# Verifies App Store build-mode invariants without requiring Apple signing credentials.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "error: $*" >&2
  exit 1
}

OURO_MD_DISTRIBUTION_CHANNEL=app-store \
OURO_MD_POSTHOG_KEY=phc_test \
OURO_MD_POSTHOG_HOST=https://us.i.posthog.com \
./make-app.sh >/tmp/ouro-md-app-store-build.log

info="OuroMD.app/Contents/Info.plist"
icon="OuroMD.app/Contents/Resources/AppIcon.icns"
entitlements="config/app-store-entitlements.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
channel="$(/usr/libexec/PlistBuddy -c 'Print :OuroMDDistributionChannel' "$info")"
category="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$info")"
telemetry_key="$(/usr/libexec/PlistBuddy -c 'Print :OuroMDPostHogKey' "$info")"
uses_non_exempt_encryption="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info")"
application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$entitlements")"
team_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$entitlements")"
[[ "$bundle_id" == "bot.ouro.md" ]] || fail "expected canonical bundle id bot.ouro.md, got $bundle_id"
[[ "$channel" == "app-store" ]] || fail "expected app-store channel, got $channel"
[[ "$category" == "public.app-category.developer-tools" ]] || fail "expected Developer Tools category, got $category"
[[ "$telemetry_key" == "phc_test" ]] || fail "expected embedded telemetry key in configured App Store build"
[[ "$uses_non_exempt_encryption" == "false" ]] || fail "expected ITSAppUsesNonExemptEncryption=false"
[[ "$application_identifier" == "743GT2AJ24.bot.ouro.md" ]] || fail "expected App Store application identifier entitlement"
[[ "$team_identifier" == "743GT2AJ24" ]] || fail "expected App Store team identifier entitlement"

iconset="$(mktemp -d)"
trap 'rm -rf "$iconset"' EXIT
iconutil -c iconset "$icon" -o "$iconset/AppIcon.iconset"
[[ -f "$iconset/AppIcon.iconset/icon_512x512@2x.png" ]] || fail "AppIcon.icns must contain a 512pt @2x representation"

OURO_MD_DISTRIBUTION_CHANNEL=app-store \
OURO_MD_TELEMETRY_DISABLED=1 \
./make-app.sh >/tmp/ouro-md-app-store-no-telemetry-build.log

if /usr/libexec/PlistBuddy -c 'Print :OuroMDPostHogKey' "$info" >/dev/null 2>&1; then
  fail "OURO_MD_TELEMETRY_DISABLED=1 should omit OuroMDPostHogKey"
fi
if /usr/libexec/PlistBuddy -c 'Print :OuroMDPostHogHost' "$info" >/dev/null 2>&1; then
  fail "OURO_MD_TELEMETRY_DISABLED=1 should omit OuroMDPostHogHost"
fi

echo "app-store build contract ok"
