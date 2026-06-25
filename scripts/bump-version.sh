#!/usr/bin/env bash
#
# Bump the app version atomically.
#
# OuroMDRelease.swift is the single source of truth (make-app.sh derives its
# VERSION from it); the only other place a human writes the version is the README
# status line. This rewrites both — plus the release date — in one shot, so a
# bump can never be applied only partway. releaseHighlights is per-release prose,
# so it's left for you to edit by hand afterward.
#
#   scripts/bump-version.sh 0.9.39
#
set -euo pipefail
cd "$(dirname "$0")/.."

new="${1:-}"
if [[ ! "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $(basename "$0") <major.minor.patch>" >&2
  exit 2
fi

swift_file="Sources/OuroMDCore/OuroMDRelease.swift"
readme="README.md"
today="$(date +%Y-%m-%d)"

sed -i '' -E "s/(static let version = \")[0-9]+\.[0-9]+\.[0-9]+(\")/\1${new}\2/" "$swift_file"
sed -i '' -E "s/(static let releaseDate = \")[0-9]{4}-[0-9]{2}-[0-9]{2}(\")/\1${today}\2/" "$swift_file"
sed -i '' -E "s/(> \*\*Status:\*\* v)[0-9]+\.[0-9]+\.[0-9]+/\1${new}/" "$readme"

# Fail loudly if anything didn't take (e.g. a format change broke a pattern).
./scripts/verify-release-version.sh >/dev/null

echo "Bumped to v${new} (releaseDate ${today})."
echo "Next: update releaseHighlights in ${swift_file}, then commit + merge to main."
