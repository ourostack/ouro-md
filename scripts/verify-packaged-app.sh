#!/usr/bin/env bash
#
# Runs the packaged-app checks that must pass before a release artifact is
# uploaded or published. This intentionally probes the .app bundle, not SwiftPM.
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-OuroMD.app}"
stress_cycles="${OURO_UNDO_STRESS_CYCLES:-10}"
allow_unconfigured="${OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY:-}"
expect_telemetry="${OURO_MD_EXPECT_TELEMETRY:-}"

fail() {
  echo "error: $*" >&2
  exit 1
}

truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

[[ -d "$app" ]] || fail "app bundle not found: $app"

info="$app/Contents/Info.plist"
exe="$app/Contents/MacOS/ouro-md"
[[ -f "$info" ]] || fail "Info.plist not found in $app"
[[ -x "$exe" ]] || fail "executable not found in $app"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$info"; }

version="$(plist CFBundleShortVersionString)"
bundle_id="$(plist CFBundleIdentifier)"
echo "packaged app: version=$version bundle=$bundle_id"

[[ "$bundle_id" == "org.ourostack.ouro-md" ]] || fail "unexpected bundle id: $bundle_id"

codesign --verify --deep --strict --verbose=2 "$app"

require_telemetry=1
if truthy "$allow_unconfigured"; then
  require_telemetry=0
fi

if [[ -n "$expect_telemetry" ]]; then
  if truthy "$expect_telemetry"; then
    require_telemetry=1
  else
    require_telemetry=0
  fi
fi

posthog_key="$(plist OuroMDPostHogKey 2>/dev/null || true)"
posthog_host="$(plist OuroMDPostHogHost 2>/dev/null || true)"

if [[ "$require_telemetry" == "1" ]]; then
  [[ -n "$posthog_key" ]] || fail "packaged app is missing OuroMDPostHogKey"
  [[ -n "$posthog_host" ]] || fail "packaged app is missing OuroMDPostHogHost"
fi

if [[ -n "$posthog_host" ]]; then
  [[ "$posthog_host" =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]/]+ ]] || fail "invalid embedded PostHog host: $posthog_host"
  echo "telemetry host: $posthog_host"
elif [[ "$require_telemetry" == "0" ]]; then
  echo "telemetry: not embedded (allowed for this run)"
fi

"$exe" --bundleprobe
"$exe" --renderprobe
"$exe" --alerttest
OURO_UNDO_STRESS_CYCLES="$stress_cycles" "$exe" --undotest

echo "packaged app probes ok"
