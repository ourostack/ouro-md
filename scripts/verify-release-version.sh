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

make_version="$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' make-app.sh | head -1)"
swift_version="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/OuroMDCore/OuroMDRelease.swift | head -1)"
readme_version="$(sed -n 's/^> \*\*Status:\*\* v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' README.md | head -1)"

[[ -n "$make_version" ]] || fail "could not read VERSION from make-app.sh"
[[ -n "$swift_version" ]] || fail "could not read OuroMDRelease.version"
[[ -n "$readme_version" ]] || fail "could not read README status version"

[[ "$make_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "make-app.sh VERSION is not semver: $make_version"

if [[ "$swift_version" != "$make_version" ]]; then
  fail "version mismatch: make-app.sh=$make_version OuroMDRelease.swift=$swift_version"
fi

if [[ "$readme_version" != "$make_version" ]]; then
  fail "version mismatch: make-app.sh=$make_version README=$readme_version"
fi

if [[ "$print_only" == "1" ]]; then
  printf '%s\n' "$make_version"
else
  echo "release version ok: $make_version"
fi
