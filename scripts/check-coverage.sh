#!/usr/bin/env bash
#
# Coverage gate for the OuroMDCore library target.
#
# Ouro MD is agentically authored, so the pure logic that an agent can silently
# regress — markdown fidelity, rendering, the resource resolver, parsing — lives
# in the OuroMDCore target and must be 100% covered by tests. This script fails
# the build if ANY file under Sources/OuroMDCore/ is below 100% line OR region
# coverage.
#
# Why "region" and not "branch": Swift's `--enable-code-coverage` does not emit
# llvm branch counters (llvm-cov's Branch column is always empty for Swift). The
# Swift-native equivalent is REGION coverage — llvm-cov creates a region for each
# arm of every conditional, so 100% region coverage means every branch was taken.
#
# The GUI/AppKit/WebKit shell stays in the OuroMD executable target and is
# exercised by the headless harnesses (--undotest/--wraptest/--renderprobe/...),
# not by this gate.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

profile_dir=".build/ouro-coverage-profiles"
mkdir -p "$profile_dir"
cleanup_root_profraw() {
  if [ -f default.profraw ]; then
    mv -f default.profraw "$profile_dir/default.profraw"
  fi
}
trap cleanup_root_profraw EXIT

# CI runners default to an older toolchain; the package needs Swift 6.
if [ -d /Applications ]; then
  latest="$(ls -d /Applications/Xcode_16*.app 2>/dev/null | sort -V | tail -1 || true)"
  [ -z "${latest:-}" ] && latest="$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -1 || true)"
  [ -n "${latest:-}" ] && export DEVELOPER_DIR="$latest/Contents/Developer"
fi

echo "==> swift test --enable-code-coverage"
OURO_TEST_LOG="${OURO_TEST_LOG:-.build/ouro-coverage-swift-test.log}" \
  OURO_TEST_TIMINGS="${OURO_TEST_TIMINGS:-.build/ouro-coverage-test-timings.tsv}" \
  ./scripts/swift-test-budget.sh --enable-code-coverage

bin="$(find .build -name 'ouro-mdPackageTests' -type f -path '*MacOS*' ! -path '*dSYM*' | head -1)"
prof="$(find .build -name 'default.profdata' | head -1)"
if [ -z "$bin" ] || [ -z "$prof" ]; then
  echo "error: could not locate coverage artifacts (binary='$bin' profdata='$prof')" >&2
  exit 1
fi

echo "==> exporting coverage summary"
xcrun llvm-cov export "$bin" -instr-profile "$prof" -summary-only > .build/ouro-coverage.json

python3 - <<'PY'
import json, os, sys

with open('.build/ouro-coverage.json') as fh:
    data = json.load(fh)

files = data['data'][0]['files']
core = [f for f in files if '/Sources/OuroMDCore/' in f['filename']]
if not core:
    print('error: no OuroMDCore files present in coverage data', file=sys.stderr)
    sys.exit(1)

print()
print(f'{"":3}{"file":<34}{"lines":>16}{"regions (branch)":>20}')
print('-' * 73)
failed = []
for f in sorted(core, key=lambda f: f['filename']):
    name = os.path.basename(f['filename'])
    L = f['summary']['lines']
    R = f['summary']['regions']
    ok = L['covered'] == L['count'] and R['covered'] == R['count']
    if not ok:
        failed.append(name)
    mark = '  ' if ok else 'XX'
    print(f'{mark} {name:<34}{L["covered"]:>6}/{L["count"]:<4}{L["percent"]:>5.0f}%'
          f'{R["covered"]:>8}/{R["count"]:<4}{R["percent"]:>5.0f}%')
print('-' * 73)

if failed:
    print(f'\nFAIL: OuroMDCore must be 100% line + region covered. Uncovered: {", ".join(failed)}')
    print('Add tests for the missing lines/branches, or move not-yet-100% logic')
    print('back to the OuroMD executable target until it is fully covered.')
    sys.exit(1)

print('\nPASS: OuroMDCore is 100% line + region (branch-equivalent) covered.')
PY
