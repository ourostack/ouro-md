#!/usr/bin/env bash
#
# Refresh the shared native shell branch dependency and prepare the release bump
# required for the Package.resolved change. This is safe to run on a fresh main
# checkout: it exits without edits when the shell pin is already current.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

identity="ouro-native-apple-app-shell"

fail() {
  echo "error: $*" >&2
  exit 1
}

non_shell_pin_snapshot() {
  python3 - "$identity" <<'PY'
import json
import sys

identity = sys.argv[1]
with open("Package.resolved", encoding="utf-8") as fh:
    data = json.load(fh)

rows = []
for pin in data.get("pins", []):
    if pin.get("identity") == identity:
        continue
    state = pin.get("state", {})
    rows.append(
        "\t".join(
            [
                pin.get("identity", ""),
                pin.get("location", ""),
                state.get("branch", ""),
                state.get("revision", ""),
                state.get("version", ""),
            ]
        )
    )
print("\n".join(sorted(rows)))
PY
}

current_version="$(./scripts/verify-release-version.sh --print)"
next_version="${OURO_MD_SHELL_REFRESH_VERSION:-}"
if [[ -z "$next_version" ]]; then
  next_version="$(
    python3 - "$current_version" <<'PY'
import re
import sys

version = sys.argv[1]
match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
if not match:
    raise SystemExit(f"cannot bump non-semver version: {version}")
major, minor, patch = (int(part) for part in match.groups())
print(f"{major}.{minor}.{patch + 1}")
PY
  )"
fi

if [[ ! "$next_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "next version is not semver: $next_version"
fi

if ./scripts/check-shell-dependency.sh; then
  echo "shell dependency already fresh; no refresh needed"
  exit 0
fi

[[ -z "$(git status --porcelain)" ]] || fail "refresh requires a clean worktree"

before_non_shell_pins="$(non_shell_pin_snapshot)"

echo "Refreshing $identity to latest main..."
swift package update "$identity"

./scripts/check-shell-dependency.sh

after_non_shell_pins="$(non_shell_pin_snapshot)"
if [[ "$before_non_shell_pins" != "$after_non_shell_pins" ]]; then
  diff -u <(printf '%s\n' "$before_non_shell_pins") <(printf '%s\n' "$after_non_shell_pins") || true
  fail "refresh changed non-$identity pins; inspect and refresh deliberately"
fi

if git diff --quiet -- Package.resolved; then
  fail "$identity freshness changed but Package.resolved has no diff"
fi

./scripts/bump-version.sh "$next_version"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("Sources/OuroMDCore/OuroMDRelease.swift")
text = path.read_text(encoding="utf-8")
replacement = '''public static let releaseHighlights = [
        "Refresh the shared native app shell dependency to latest main.",
    ]'''
updated, count = re.subn(
    r'public static let releaseHighlights = \[\n(?:.|\n)*?\n    \]',
    replacement,
    text,
    count=1,
)
if count != 1:
    raise SystemExit("could not rewrite OuroMDRelease.releaseHighlights")
path.write_text(updated, encoding="utf-8")
PY

./scripts/verify-release-version.sh
echo "Prepared $identity refresh for Ouro MD v$next_version."
