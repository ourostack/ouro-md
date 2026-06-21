#!/usr/bin/env bash
#
# Runs the visual QA probes and, when a case fails, leaves screenshots behind so
# CI failures are inspectable instead of becoming "try it locally" mysteries.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

exe="${OURO_MD_EXE:-.build/debug/ouro-md}"
artifact_dir="${OURO_VISUAL_ARTIFACT_DIR:-.build/visual-qa-artifacts}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -x "$exe" ]] || fail "ouro-md executable not found or not executable: $exe"

mkdir -p "$artifact_dir"

fallback_fixture=""
cleanup() {
  if [[ -n "$fallback_fixture" ]]; then
    rm -f "$fallback_fixture"
  fi
}
trap cleanup EXIT

make_fallback_fixture() {
  fallback_fixture="$(mktemp /tmp/ouro-md-visual-fallback.XXXXXX.md)"
  cat > "$fallback_fixture" <<'MD'
# Visual QA Fallback With A Very Long Heading That Must Wrap Without Pushing The Document Sideways

![Small fixture image](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l1n1ywAAAABJRU5ErkJggg==)

> [!NOTE]
> A note callout should keep its body visible.

> [!WARNING]
> A warning callout should keep its body visible too.

| Surface | Evidence | Code |
| - | - | - |
| Long prose | The table should be readable without collapsing into ribbons, while the page itself remains stable. | `Sources/OuroMD/VisualQATest.swift` |
MD
}

shell_quote() {
  python3 - "$1" <<'PY'
import shlex
import sys
print(shlex.quote(sys.argv[1]))
PY
}

shoot_case() {
  local name="$1"
  local fixture="$2"
  local theme="$3"
  local width="${4:-1200}"
  local height="${5:-1400}"

  if [[ -z "$fixture" ]]; then
    if [[ -z "$fallback_fixture" ]]; then
      make_fallback_fixture
    fi
    fixture="$fallback_fixture"
  fi

  local out="$artifact_dir/${name}.png"
  echo "visual artifact: $out"
  if ! "$exe" --shoot "$fixture" --theme "$theme" --width "$width" --height "$height" --out "$out"; then
    echo "warning: failed to capture visual artifact for $name" >&2
  fi
}

run_case() {
  local name="$1"
  local fixture="$2"
  local theme="$3"
  local width="${4:-720}"
  local height="${5:-900}"
  local -a args=(--visualqatest --theme "$theme" --visualqa-width "$width" --visualqa-height "$height")
  if [[ -n "$fixture" ]]; then
    args+=(--visualqa-file "$fixture")
  fi

  echo "==> visual QA: $name"
  if "$exe" "${args[@]}"; then
    echo "visual QA ok: $name"
    return 0
  fi

  echo "visual QA failed: $name" >&2
  shoot_case "$name" "$fixture" "$theme" "$width" "$height"
  return 1
}

failed=0
run_case "fallback-quartz" "" "quartz" || failed=1
run_case "dogfood-quartz" "Tests/Fixtures/dogfood-visual-surface.md" "quartz" || failed=1
run_case "dogfood-graphite" "Tests/Fixtures/dogfood-visual-surface.md" "graphite" || failed=1

if [[ "$failed" == "1" ]]; then
  echo "visual QA artifacts written under $(shell_quote "$artifact_dir")" >&2
  exit 1
fi

echo "visual QA ok"
