#!/usr/bin/env bash
#
# Verifies the release version is coherent across the files humans edit during a
# release bump. Use --print to emit only the version for workflow plumbing.
set -euo pipefail
cd "$(dirname "$0")/.."

print_only=0
for arg in "$@"; do
  case "$arg" in
    --print) print_only=1 ;;
    *)
      echo "usage: $0 [--print]" >&2
      exit 2
      ;;
  esac
done

fail() {
  echo "error: $*" >&2
  exit 1
}

# OuroMDRelease.swift is the single source of truth — the version the app reports
# at runtime. make-app.sh derives its VERSION from it, so the only other place a
# human writes the version is the README status line, which is checked here.
swift_version="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/OuroMDCore/OuroMDRelease.swift | head -1)"
readme_version="$(sed -n 's/^> \*\*Status:\*\* v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' README.md | head -1)"

[[ -n "$swift_version" ]] || fail "could not read OuroMDRelease.version"
[[ -n "$readme_version" ]] || fail "could not read README status version"

[[ "$swift_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "OuroMDRelease.version is not semver: $swift_version"

# Guard the single source of truth: make-app.sh must DERIVE its version from
# OuroMDRelease.swift, never hardcode it, or the packaged Info.plist could drift.
if grep -Eq '^VERSION="[0-9]' make-app.sh; then
  fail "make-app.sh hardcodes VERSION; it must derive from OuroMDRelease.swift (single source of truth)"
fi
grep -q 'OuroMDRelease.swift' make-app.sh || fail "make-app.sh must derive VERSION from OuroMDRelease.swift"

if [[ "$readme_version" != "$swift_version" ]]; then
  fail "version mismatch: OuroMDRelease.swift=$swift_version README=$readme_version"
fi

if [[ "$print_only" == "1" ]]; then
  printf '%s\n' "$swift_version"
else
  echo "release version ok: $swift_version"
fi
