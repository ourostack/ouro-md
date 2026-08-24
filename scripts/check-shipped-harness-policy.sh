#!/usr/bin/env bash
#
# Validates Ouro MD's shipped non-GUI CLI and hidden diagnostic harness policy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

manifest="docs/shipped-cli-and-harness-policy.json"

python3 - "$manifest" <<'PY'
import json
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
root = Path.cwd()

def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)

if not manifest_path.exists():
    fail(f"missing shipped harness policy manifest: {manifest_path}")

try:
    policy = json.loads(manifest_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    fail(f"{manifest_path}: invalid JSON: {exc}")

main = Path("Sources/OuroMD/main.swift")
main_text = main.read_text(encoding="utf-8")
main_flags = sorted(set(re.findall(r'hasFlag\("([^"]+)"\)', main_text)))
main_flags = [flag for flag in main_flags if flag.startswith("--")]

modes = policy.get("modes")
if not isinstance(modes, list) or not modes:
    fail("policy must contain a non-empty modes array")

seen = {}
for index, mode in enumerate(modes):
    if not isinstance(mode, dict):
        fail(f"modes[{index}] must be an object")
    flag = mode.get("flag")
    if not isinstance(flag, str) or not flag.startswith("--"):
        fail(f"modes[{index}].flag must be a long flag")
    if flag in seen:
        fail(f"duplicate mode flag in policy: {flag}")
    seen[flag] = mode
    category = mode.get("category")
    if category not in ("public-maintainer-cli", "hidden-diagnostic-harness"):
        fail(f"{flag}: category must be public-maintainer-cli or hidden-diagnostic-harness")
    if mode.get("source") != "Sources/OuroMD/main.swift":
        fail(f"{flag}: source must be Sources/OuroMD/main.swift")
    if not isinstance(mode.get("privacy"), str) or not mode["privacy"]:
        fail(f"{flag}: privacy must describe shipped-mode data behavior")
    if category == "hidden-diagnostic-harness":
        if mode.get("normalLaunchReachable") is not False:
            fail(f"{flag}: hidden diagnostic modes must set normalLaunchReachable=false")
        covered_by = mode.get("coveredBy")
        if not isinstance(covered_by, list) or not covered_by:
            fail(f"{flag}: hidden diagnostic modes must list coveredBy scripts")
        for script in covered_by:
            path = root / script
            if not path.exists():
                fail(f"{flag}: coveredBy script does not exist: {script}")
            if flag not in path.read_text(encoding="utf-8"):
                fail(f"{flag}: coveredBy script {script} does not invoke the flag")

missing = [flag for flag in main_flags if flag not in seen]
extra = [flag for flag in seen if flag not in main_flags]
if missing:
    fail("main.swift flags missing from policy: " + ", ".join(missing))
if extra:
    fail("policy flags not present in main.swift: " + ", ".join(extra))

fixtures = policy.get("fixtures")
if not isinstance(fixtures, list) or not fixtures:
    fail("policy must contain a non-empty fixtures array")
for index, fixture in enumerate(fixtures):
    if not isinstance(fixture, dict):
        fail(f"fixtures[{index}] must be an object")
    fixture_path = fixture.get("path")
    script_path = fixture.get("script")
    required_lines = fixture.get("requiredLines")
    if not isinstance(fixture_path, str) or not fixture_path:
        fail(f"fixtures[{index}].path must be a non-empty string")
    if not (root / fixture_path).is_file():
        fail(f"fixtures[{index}] does not exist: {fixture_path}")
    if not isinstance(script_path, str) or not script_path:
        fail(f"fixtures[{index}].script must be a non-empty string")
    script = root / script_path
    if not script.is_file():
        fail(f"fixtures[{index}] script does not exist: {script_path}")
    if not isinstance(required_lines, list) or not required_lines:
        fail(f"fixtures[{index}].requiredLines must be a non-empty array")
    script_lines = set(script.read_text(encoding="utf-8").splitlines())
    for required_line in required_lines:
        if not isinstance(required_line, str) or not required_line:
            fail(f"fixtures[{index}] contains an invalid required line")
        if required_line not in script_lines:
            fail(f"{fixture_path}: {script_path} missing exact line: {required_line}")

release_policy = Path("scripts/release-policy.sh").read_text(encoding="utf-8")
for required in (
    "Sources/OuroMD/*Test.swift|Sources/OuroMD/*Probe.swift",
    "Sources/OuroMD/Snapshot.swift|Sources/OuroMD/RoundTrip.swift|Sources/OuroMD/HeadlessHarness.swift",
    "scripts/run-native-scenarios.sh|scripts/run-visual-qa.sh|scripts/swift-test-budget.sh",
):
    if required not in release_policy:
        fail(f"release-policy.sh missing harness release-freshness classifier: {required}")

preflight = Path("scripts/pr-preflight.sh").read_text(encoding="utf-8")
if "./scripts/check-shipped-harness-policy.sh" not in preflight:
    fail("pr-preflight.sh must run scripts/check-shipped-harness-policy.sh")

print("shipped harness policy ok")
PY
