#!/usr/bin/env python3
"""Fails if a pull request could run a job on the billed xcode-27 runner.

    python3 -I scripts/check-ci-runners.py            # checks .github/workflows
    python3 -I scripts/check-ci-runners.py --selftest

Pull requests run on GitHub's free runners only. xcode-27 is for checks that truly need Xcode 27, on pushes to main
and releases; a job in a workflow that pull requests trigger may use it only behind an `if:` that limits it to pushes.
"""
import re
import sys
from pathlib import Path


RUNNER = re.compile(r"^\s*(runs-on|[A-Za-z_-]*runner[A-Za-z_-]*|os)\s*:.*\bxcode-27\b|^\s*-\s*xcode-27\s*$", re.MULTILINE)


def problems(name, text):
    if not re.search(r"^\s*pull_request(_target)?\s*:", text, re.MULTILINE):
        return []
    out = []
    # Split into jobs: two-space-indented keys under `jobs:`.
    jobs = text.split("\njobs:\n", 1)[1] if "\njobs:\n" in text else ""
    for block in re.split(r"\n(?=  [A-Za-z0-9_-]+:\s*\n)", "\n" + jobs):
        head = re.match(r"\s*([A-Za-z0-9_-]+):", block)
        # Only where a job picks its runner (runs-on, or a matrix value), not names, comments or scripts.
        if not head or not RUNNER.search(block):
            continue
        gated = re.search(r"^    if: .*github\.event_name == 'push'", block, re.MULTILINE)
        if not gated:
            out.append(f"{name}: job {head.group(1)} can run on xcode-27 for a pull request. "
                       "Fix: run it on macos-26, or gate it with `if: github.event_name == 'push' && ...`.")
    return out


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    root = Path(__file__).resolve().parent.parent / ".github" / "workflows"
    found = [p for f in sorted(root.glob("*.yml")) for p in problems(f.name, f.read_text(encoding="utf-8"))]
    for line in found:
        print(f"check-ci-runners: {line}", file=sys.stderr)
    if not found:
        print("check-ci-runners: no pull request job uses xcode-27")
    return 1 if found else 0


def selftest():
    free = "on:\n  pull_request:\njobs:\n  a:\n    runs-on: macos-26\n"
    billed = "on:\n  pull_request:\njobs:\n  a:\n    runs-on: macos-26\n  b:\n    runs-on: xcode-27\n"
    matrix = "on:\n  pull_request:\njobs:\n  a:\n    strategy:\n      matrix:\n        runner: [macos-26, xcode-27]\n"
    gated = ("on:\n  pull_request:\n  push:\njobs:\n  b:\n    if: github.event_name == 'push' && github.ref == 'refs/heads/main'\n"
             "    runs-on: xcode-27\n")
    push_only = "on:\n  push:\n    branches: [main]\njobs:\n  b:\n    runs-on: xcode-27\n"
    named = "on:\n  pull_request:\njobs:\n  a:\n    runs-on: macos-26\n    steps:\n      - name: no xcode-27 here\n"
    listed = "on:\n  pull_request:\njobs:\n  a:\n    strategy:\n      matrix:\n        runner:\n          - xcode-27\n"
    cases = [("named", named, 0), ("listed", listed, 1), ("free", free, 0), ("billed", billed, 1), ("matrix", matrix, 1), ("gated", gated, 0), ("push only", push_only, 0)]
    ok = True
    for name, text, want in cases:
        got = len(problems(name, text))
        print(("ok   " if got == want else "FAIL ") + f"{name}: {got} problems, want {want}")
        ok &= got == want
    print("check-ci-runners selftest: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
