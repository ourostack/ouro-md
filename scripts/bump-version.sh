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

# True (exit 0) when version $1 <= $2, compared numerically per component (so
# 0.9.50 > 0.9.5 and 0.10.0 > 0.9.99 — a lexical/string sort gets both wrong).
version_le() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  (( a1 < b1 || (a1 == b1 && (a2 < b2 || (a2 == b2 && a3 <= b3))) ))
}

# --selftest: exercise the guard's comparison without touching any files.
if [[ "${1:-}" == "--selftest" ]]; then
  fail=0
  check() { if version_le "$1" "$2"; then got=le; else got=gt; fi
    if [[ "$got" == "$3" ]]; then echo "ok: $1 vs $2 -> $got"
    else echo "FAIL: $1 vs $2 -> $got (want $3)"; fail=1; fi; }
  check 0.9.47 0.9.49 le   # the bug: a stale source version going backwards
  check 0.9.49 0.9.47 gt   # a normal forward bump
  check 0.9.49 0.9.49 le   # re-bumping to the same version is refused too
  check 0.9.5  0.9.50 le   # numeric patch compare (5 < 50)
  check 0.10.0 0.9.99 gt   # numeric minor compare (10 > 9)
  check 1.0.0  0.9.99 gt
  [[ "$fail" -eq 0 ]] && echo "bump-version selftest: PASS" || echo "bump-version selftest: FAIL"
  exit "$fail"
fi

new=""
allow_downgrade=0
for arg in "$@"; do
  case "$arg" in
    --allow-downgrade) allow_downgrade=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) new="$arg" ;;
  esac
done
if [[ ! "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $(basename "$0") <major.minor.patch> [--allow-downgrade]" >&2
  exit 2
fi

swift_file="Sources/OuroMDCore/OuroMDRelease.swift"
readme="README.md"
today="$(date +%Y-%m-%d)"

# Refuse to go backwards (or sideways): a stale source version silently
# overwriting a newer one is the footgun that cascades into release-version
# collisions. Override with --allow-downgrade for a deliberate rollback.
current="$(sed -nE 's/.*static let version = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$swift_file" | head -1)"
if [[ -n "$current" && "$allow_downgrade" -ne 1 ]] && version_le "$new" "$current"; then
  echo "error: $new is not newer than the current version $current." >&2
  echo "       Version bumps must increase; use --allow-downgrade for a deliberate rollback." >&2
  exit 2
fi

sed -i '' -E "s/(static let version = \")[0-9]+\.[0-9]+\.[0-9]+(\")/\1${new}\2/" "$swift_file"
sed -i '' -E "s/(static let releaseDate = \")[0-9]{4}-[0-9]{2}-[0-9]{2}(\")/\1${today}\2/" "$swift_file"
sed -i '' -E "s/(> \*\*Status:\*\* v)[0-9]+\.[0-9]+\.[0-9]+/\1${new}/" "$readme"

# Fail loudly if anything didn't take (e.g. a format change broke a pattern).
./scripts/verify-release-version.sh >/dev/null

echo "Bumped to v${new} (releaseDate ${today})."
echo "Next: update releaseHighlights in ${swift_file}, then commit + merge to main."
