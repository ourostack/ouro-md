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
expect_git_sha="${OURO_MD_EXPECT_GIT_SHA:-}"
tmp_root=""
hidden_build=""

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
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"

info="$app/Contents/Info.plist"
exe="$app/Contents/MacOS/ouro-md"
[[ -f "$info" ]] || fail "Info.plist not found in $app"
[[ -x "$exe" ]] || fail "executable not found in $app"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$info"; }

version="$(plist CFBundleShortVersionString)"
build="$(plist CFBundleVersion)"
bundle_id="$(plist CFBundleIdentifier)"
git_sha="$(plist OuroMDGitSHA 2>/dev/null || true)"
echo "packaged app: version=$version build=$build bundle=$bundle_id git=${git_sha:-unknown}"

[[ "$bundle_id" == "org.ourostack.ouro-md" ]] || fail "unexpected bundle id: $bundle_id"
[[ "$build" == "$version" ]] || fail "bundle build $build did not match version $version"
if [[ -n "$expect_git_sha" ]]; then
  [[ -n "$git_sha" ]] || fail "expected git sha $expect_git_sha but app had no OuroMDGitSHA"
  expected_prefix="${expect_git_sha:0:${#git_sha}}"
  [[ "$git_sha" == "$expected_prefix" ]] || fail "app git sha $git_sha did not match expected $expect_git_sha"
fi

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

cleanup() {
  if [[ -n "$hidden_build" && -d "$hidden_build" ]]; then
    rm -rf .build
    mv "$hidden_build" .build
  fi
  if [[ -n "$tmp_root" ]]; then
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

if [[ -d .build ]]; then
  hidden_build=".build_hidden_verify_packaged_app_$$"
  rm -rf "$hidden_build"
  mv .build "$hidden_build"
fi

version_output="$("$exe" --version)"
echo "version output: $version_output"
[[ "$version_output" == *"$version"* ]] || fail "--version output did not include $version"
if [[ -n "$git_sha" ]]; then
  [[ "$version_output" == *"$git_sha"* ]] || fail "--version output did not include git sha $git_sha"
fi

"$exe" --bundleprobe
"$exe" --renderprobe
"$exe" --alerttest
"$exe" --wraptest
"$exe" --tablewraptest
"$exe" --tablewraptest --tablewrap-file Tests/Fixtures/dogfood-wide-tables.md
"$exe" --tablewraptest --tablewrap-width 1400 --tablewrap-height 5000 --tablewrap-file Tests/Fixtures/dogfood-wide-tables.md

tmp_root="$(mktemp -d /tmp/ouro-md-packaged.XXXXXX)"
roundtrip_in="$tmp_root/roundtrip.md"
roundtrip_out="$tmp_root/roundtrip-out.md"
cat > "$roundtrip_in" <<'MD'
# Packaged Roundtrip

Plain Markdown should survive a packaged-app roundtrip byte-for-byte.

- one
- two

`inline code`
MD
"$exe" --roundtrip "$roundtrip_in" --out "$roundtrip_out"
cmp "$roundtrip_in" "$roundtrip_out"

OURO_UNDO_STRESS_CYCLES="$stress_cycles" "$exe" --undotest
./scripts/release-policy.sh scan "$app"

echo "packaged app probes ok"
