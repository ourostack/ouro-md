#!/usr/bin/env bash
#
# Shared headless app-scenario gate for local preflight, CI, and packaged-app
# verification. Keep the list here so scenario coverage does not drift between
# SwiftPM and release artifacts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

exe="${OURO_MD_EXE:-.build/debug/ouro-md}"
timeout_seconds="${OURO_SCENARIO_TIMEOUT_SECONDS:-90}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -x "$exe" ]] || fail "ouro-md executable not found or not executable: $exe"

run() {
  echo "==> ouro-md $*"
  perl -e 'alarm shift @ARGV; exec @ARGV' "$timeout_seconds" "$exe" "$@"
}

run --undotest
run --wraptest
run --renderprobe
run --codewraptest

OURO_MD_EXE="$exe" ./scripts/run-visual-qa.sh

run --searchrevealtest
run --uisurfacetest
run --editorsurfacetest
run --firstlaunchtest
run --tablewraptest
run --tablewraptest --tablewrap-file Tests/Fixtures/dogfood-wide-tables.md
run --tablewraptest --tablewrap-width 1000 --tablewrap-height 1300 --tablewrap-file Tests/Fixtures/dogfood-wide-tables.md
run --tablewraptest --tablewrap-width 1400 --tablewrap-height 5000 --tablewrap-file Tests/Fixtures/dogfood-wide-tables.md

tmp="$(mktemp -d /tmp/ouro-md-native-scenarios.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

roundtrip_in="$tmp/roundtrip.md"
roundtrip_out="$tmp/roundtrip-out.md"
cat > "$roundtrip_in" <<'MD'
# Native Scenario Roundtrip

Plain Markdown should survive a headless roundtrip byte-for-byte.

- one
- two

`inline code`
MD
run --roundtrip "$roundtrip_in" --out "$roundtrip_out"
cmp "$roundtrip_in" "$roundtrip_out"

echo "==> ouro-md selftest"
OURO_SELFTEST=1 perl -e 'alarm shift @ARGV; exec @ARGV' "$timeout_seconds" "$exe"

echo "native scenarios ok"
