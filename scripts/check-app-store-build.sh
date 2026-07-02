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
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
channel="$(/usr/libexec/PlistBuddy -c 'Print :OuroMDDistributionChannel' "$info")"
category="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$info")"
telemetry_key="$(/usr/libexec/PlistBuddy -c 'Print :OuroMDPostHogKey' "$info")"
[[ "$bundle_id" == "bot.ouro.md" ]] || fail "expected canonical bundle id bot.ouro.md, got $bundle_id"
[[ "$channel" == "app-store" ]] || fail "expected app-store channel, got $channel"
[[ "$category" == "public.app-category.developer-tools" ]] || fail "expected Developer Tools category, got $category"
[[ "$telemetry_key" == "phc_test" ]] || fail "expected embedded telemetry key in configured App Store build"

OURO_MD_DISTRIBUTION_CHANNEL=app-store \
OURO_MD_TELEMETRY_DISABLED=1 \
./make-app.sh >/tmp/ouro-md-app-store-no-telemetry-build.log

if /usr/libexec/PlistBuddy -c 'Print :OuroMDPostHogKey' "$info" >/dev/null 2>&1; then
  fail "OURO_MD_TELEMETRY_DISABLED=1 should omit OuroMDPostHogKey"
fi

echo "app-store build contract ok"
