#!/usr/bin/env bash
#
# Runs `swift test`, records per-test timings, annotates the slowest tests on
# GitHub Actions, and fails when any individual XCTest exceeds the configured
# budget. This catches "one test quietly ate a minute" regressions before they
# become normal.
#
# GitHub's free macOS runners sometimes stall one WebKit test for a minute while
# every other test runs at normal speed. A test over budget in the suite run is
# therefore timed once more on its own, from the already-built bundle, with its
# coverage profile written to a throwaway path. It fails the budget only if it
# is still over (or fails) on its own: a real slowdown repeats, a runner stall
# does not. The stall seen is one test per run, so when more than
# OURO_TEST_STALL_RETRY_MAX (default 2) tests are over budget nothing is retried:
# that is a slowdown, not a stall. OURO_TEST_STALL_RETRY=0 turns the retry off.
set -euo pipefail

self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "$self")/.."

if [[ "${1:-}" == "--selftest" ]]; then
  # Drives this script against stub `swift` and `xcrun` commands, so the
  # budget and stall-retry rules are checked without building anything.
  work="$(mktemp -d "${TMPDIR:-/tmp}/ouro-test-budget-selftest.XXXXXX")"
  mkdir -p "$work/bin" "$work/OuroMDTests.xctest"
  cat > "$work/bin/swift" <<'STUB'
#!/usr/bin/env bash
echo "Test Case '-[OuroMDTests.FastTests testQuick]' passed (0.100 seconds)."
echo "Test Case '-[OuroMDTests.PrintTests testStalls]' passed (${STUB_FIRST_SECONDS:-66.000} seconds)."
for extra in ${STUB_ALSO_SLOW:-}; do
  echo "Test Case '-[OuroMDTests.PrintTests ${extra}]' passed (30.000 seconds)."
done
exit "${STUB_SWIFT_STATUS:-0}"
STUB
  cat > "$work/bin/xcrun" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_XCRUN_CALLS"
[[ "$1" == "xctest" && "$2" == "-XCTest" && "$3" == OuroMDTests.PrintTests/test* ]] || exit 64
[[ "$LLVM_PROFILE_FILE" == *ouro-test-budget-retry* ]] || exit 65
test="${3#*/}"
[[ "${STUB_RETRY_RESULT:-passed}" != crash ]] || exit 134
seconds="${STUB_RETRY_SECONDS:-2.000}"
# testSlowAlone is genuinely slow: it is over budget on its own too.
[[ "$test" != testSlowAlone ]] || seconds=30.000
echo "Test Case '-[OuroMDTests.PrintTests ${test}]' ${STUB_RETRY_RESULT:-passed} (${seconds} seconds)."
[[ "${STUB_RETRY_RESULT:-passed}" == passed ]]
STUB
  chmod +x "$work/bin/swift" "$work/bin/xcrun"
  failures=0
  expect() {
    local name="$1" want="$2" want_calls="$3" needle="$4" absent="$5"; shift 5
    local calls="$work/$name.calls" out="$work/$name.out" got
    : > "$calls"
    set +e
    env PATH="$work/bin:$PATH" STUB_XCRUN_CALLS="$calls" OURO_TEST_BUNDLE="$work/OuroMDTests.xctest" \
      OURO_TEST_LOG="$work/$name.log" OURO_TEST_TIMINGS="$work/$name.tsv" "$@" \
      "$self" > "$out" 2>&1
    got=$?
    set -e
    local got_calls; got_calls="$(wc -l < "$calls" | tr -d ' ')"
    if [[ "$got" != "$want" || "$got_calls" != "$want_calls" ]] || ! grep -q -- "$needle" "$out" \
      || { [[ -n "$absent" ]] && grep -q -- "$absent" "$out"; }; then
      echo "selftest FAIL $name: exit $got (want $want), retries $got_calls (want $want_calls), needle '$needle', absent '$absent'" >&2
      sed 's/^/    /' "$out" >&2
      failures=$((failures + 1))
    else
      echo "selftest ok   $name"
    fi
  }
  expect within-budget 0 0 "slowest XCTest cases" "budget exceeded" STUB_FIRST_SECONDS=3.000
  expect stall-then-fast-retry 0 1 "isolated retry took 2.000s" "budget exceeded" STUB_RETRY_SECONDS=2.000
  expect slow-again-on-retry 3 1 "budget exceeded" "" STUB_RETRY_SECONDS=25.000
  expect retry-fails 3 1 "budget exceeded" "" STUB_RETRY_RESULT=failed
  expect retry-crashes-without-a-result 3 1 "on its own: did not pass" "" STUB_RETRY_RESULT=crash
  expect stall-and-real-slowdown 3 2 "testSlowAlone] (on its own: 30.000)" "testStalls] (on its own" STUB_ALSO_SLOW=testSlowAlone
  expect too-many-over-budget-is-not-a-stall 3 0 "budget exceeded" "isolated retry" STUB_ALSO_SLOW="testB testC"
  expect retry-disabled 3 0 "budget exceeded" "" OURO_TEST_STALL_RETRY=0
  expect swift-failure-keeps-status 1 0 "budget exceeded" "" STUB_SWIFT_STATUS=1
  expect parser-error-fails 1 0 "Traceback" "" OURO_TEST_MAX_SECONDS=abc
  [[ "$failures" -eq 0 ]] || { echo "swift-test-budget selftest: $failures failure(s); work dir $work" >&2; exit 1; }
  echo "swift-test-budget selftest passed"
  exit 0
fi

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

over = []
for seconds, name, status in cases:
    if seconds > max_seconds and name not in [n for _, n, _ in over]:
        over.append((seconds, name, status))
with open(timings_path + ".over", "w", encoding="utf-8") as out:
    for seconds, name, _ in over:
        out.write(f"{seconds:.3f}\t{name}\n")
if over:
    sys.exit(3)
PY
budget_status=$?
set -e

if [[ "$budget_status" -ne 0 && "$budget_status" -ne 3 ]]; then
  echo "error: could not read XCTest timings (exit $budget_status)" >&2
  [[ "$swift_status" -eq 0 ]] || exit "$swift_status"
  exit "$budget_status"
fi

budget_failures=()
if [[ "$budget_status" -eq 3 ]]; then
  retry="${OURO_TEST_STALL_RETRY:-1}"
  # A failing suite is reported as-is; retries are only for timing.
  [[ "$swift_status" -eq 0 ]] || retry=0
  over_count="$(wc -l < "${timings}.over" | tr -d ' ')"
  if [[ "$retry" != 0 && "$over_count" -gt "${OURO_TEST_STALL_RETRY_MAX:-2}" ]]; then
    echo "==> ${over_count} tests are over budget; that is a slowdown, not a runner stall, so none is retried"
    retry=0
  fi
  retry_dir="$(dirname "$timings")/ouro-test-budget-retry"
  while IFS=$'\t' read -r seconds name; do
    [[ -n "$name" ]] || continue
    if [[ "$retry" == 0 ]]; then
      budget_failures+=("${seconds}s > ${max_seconds}s ${name}")
      continue
    fi
    # "-[Module.Class testName]" becomes "Module.Class/testName".
    inner="${name#-[}"; inner="${inner%]}"
    filter="${inner%% *}/${inner#* }"
    module="${filter%%.*}"
    bundle="${OURO_TEST_BUNDLE:-}"
    if [[ -z "$bundle" ]]; then
      # Xcode 27 builds one bundle per test target; Xcode 26 builds one combined bundle.
      # Newest first, so a stale bundle from another toolchain is not picked.
      bundle="$(find .build -type d \( -name "${module}.xctest" -o -name '*PackageTests.xctest' \) ! -path '*dSYM*' -exec ls -dt {} + 2>/dev/null | head -1)"
    fi
    mkdir -p "$retry_dir"
    retry_log="$retry_dir/$(echo "$filter" | tr '/.' '__').log"
    echo "==> ${name} took ${seconds}s in the suite run; timing it once on its own"
    set +e
    LLVM_PROFILE_FILE="$retry_dir/ouro-test-budget-retry-%p.profraw" \
      xcrun xctest -XCTest "$filter" "$bundle" > "$retry_log" 2>&1
    set -e
    retry_line="$(grep -F "Test Case '${name}'" "$retry_log" | grep -E '(passed|failed) \([0-9.]+ seconds\)' | tail -1 || true)"
    retry_seconds="$(echo "$retry_line" | sed -nE 's/.*passed \(([0-9.]+) seconds\).*/\1/p')"
    if [[ -n "$retry_seconds" ]] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$retry_seconds" "$max_seconds"; then
      echo "isolated retry took ${retry_seconds}s; counting the ${seconds}s suite run as a runner stall"
      if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::warning title=XCTest runner stall::${name} took ${seconds}s in the suite run and ${retry_seconds}s on its own"
      fi
    else
      tail -20 "$retry_log" | sed 's/^/    /' >&2
      budget_failures+=("${seconds}s > ${max_seconds}s ${name} (on its own: ${retry_seconds:-did not pass})")
    fi
  done < "${timings}.over"
fi

if [[ "${#budget_failures[@]}" -gt 0 ]]; then
  echo
  echo "FAIL: XCTest case budget exceeded (${max_seconds}s max)" >&2
  for failure in "${budget_failures[@]}"; do
    echo "::error title=XCTest budget exceeded::${failure}"
    echo "  ${failure}" >&2
  done
fi

if [[ "$swift_status" -ne 0 ]]; then
  exit "$swift_status"
fi
[[ "${#budget_failures[@]}" -eq 0 ]] || exit 3
exit 0
