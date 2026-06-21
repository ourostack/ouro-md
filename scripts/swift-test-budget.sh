#!/usr/bin/env bash
#
# Runs `swift test`, records per-test timings, annotates the slowest tests on
# GitHub Actions, and fails when any individual XCTest exceeds the configured
# budget. This catches "one test quietly ate a minute" regressions before they
# become normal.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

max_seconds="${OURO_TEST_MAX_SECONDS:-20}"
slow_count="${OURO_TEST_SLOW_COUNT:-15}"
log="${OURO_TEST_LOG:-.build/ouro-swift-test.log}"
timings="${OURO_TEST_TIMINGS:-.build/ouro-test-timings.tsv}"

mkdir -p "$(dirname "$log")" "$(dirname "$timings")"

echo "==> swift test $*"
set +e
swift test "$@" 2>&1 | tee "$log"
swift_status=${PIPESTATUS[0]}
set -e

set +e
python3 - "$log" "$timings" "$max_seconds" "$slow_count" <<'PY'
import re
import sys

log_path, timings_path, max_raw, slow_raw = sys.argv[1:5]
max_seconds = float(max_raw)
slow_count = int(slow_raw)
case_re = re.compile(r"Test Case '([^']+)' (passed|failed) \(([0-9.]+) seconds\)\.")

cases = []
with open(log_path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        match = case_re.search(line)
        if match:
            cases.append((float(match.group(3)), match.group(1), match.group(2)))

cases.sort(reverse=True)
with open(timings_path, "w", encoding="utf-8") as out:
    out.write("seconds\tstatus\ttest\n")
    for seconds, name, status in cases:
        out.write(f"{seconds:.3f}\t{status}\t{name}\n")

if not cases:
    print("warning: no XCTest case timing lines found in swift test output", file=sys.stderr)
else:
    print()
    print(f"==> slowest XCTest cases (top {min(slow_count, len(cases))})")
    for seconds, name, status in cases[:slow_count]:
        print(f"{seconds:7.3f}s  {status:<6}  {name}")
        if "GITHUB_ACTIONS" in __import__("os").environ:
            print(f"::notice title=Slow XCTest::{seconds:.3f}s {name}")

over = [(seconds, name, status) for seconds, name, status in cases if seconds > max_seconds]
if over:
    print()
    print(f"FAIL: XCTest case budget exceeded ({max_seconds:.3f}s max)", file=sys.stderr)
    for seconds, name, _ in over:
        print(f"::error title=XCTest budget exceeded::{seconds:.3f}s > {max_seconds:.3f}s {name}")
        print(f"  {seconds:.3f}s  {name}", file=sys.stderr)
    sys.exit(3)
PY
budget_status=$?
set -e

if [[ "$swift_status" -ne 0 ]]; then
  exit "$swift_status"
fi
exit "$budget_status"
