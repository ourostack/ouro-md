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


TRIGGER = re.compile(r"^on:.*\bpull_request|^\s*-?\s*pull_request(_target)?\b", re.MULTILINE)
# The job runs only on pushes: the condition starts with the push check and adds anything else only with &&.
PUSH_ONLY = re.compile(r"^    if:\s*(\$\{\{\s*)?github\.event_name\s*==\s*'push'\s*(&&|\}\}|$)", re.MULTILINE)


def problems(name, text):
    """Each job a pull request can trigger that picks xcode-27 anywhere before its steps (runs-on, matrix, include,
    labels). Not followed: runs-on built at run time (fromJSON(vars.X)) and reusable workflows a job calls."""
    if not TRIGGER.search(text):
        return []
    parts = re.split(r"^jobs:.*$", text, maxsplit=1, flags=re.MULTILINE)
    if len(parts) < 2:
        return []
    out = []
    for block in re.split(r"\n(?=  [A-Za-z0-9_-]+:\s*(#.*)?\n)", "\n" + parts[1]):
        if block is None:
            continue
        head = re.match(r"\s*([A-Za-z0-9_-]+):", block)
        if not head:
            continue
        setup = re.split(r"^    steps:", block, maxsplit=1, flags=re.MULTILINE)[0]
        picks = [line for line in setup.splitlines()
                 if re.search(r"\bxcode-27\b", line) and not re.match(r"\s*(#|name:)", line)]
        if picks and not PUSH_ONLY.search(setup):
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
    short = "on: [pull_request, push]\njobs:\n  b:\n    runs-on: xcode-27\n"
    inline = "on: pull_request\njobs:\n  b:\n    runs-on: xcode-27\n"
    include = ("on:\n  pull_request:\njobs:\n  a:\n    strategy:\n      matrix:\n        include:\n"
               "          - runner: xcode-27\n    runs-on: ${{ matrix.runner }}\n")
    labels = "on:\n  pull_request:\njobs:\n  a:\n    runs-on: {group: x, labels: xcode-27}\n"
    in_steps = "on:\n  pull_request:\njobs:\n  a:\n    runs-on: macos-26\n    steps:\n      - uses: x\n        with: {os: xcode-27}\n"
    loose = "on:\n  pull_request:\njobs:\n  b:\n    if: github.event_name == 'push' || true\n    runs-on: xcode-27\n"
    negated = "on:\n  pull_request:\njobs:\n  b:\n    if: \"!(github.event_name == 'push')\"\n    runs-on: xcode-27\n"
    commented = "on:\n  pull_request:\njobs: # all\n  b:\n    runs-on: xcode-27\n"
    cases = [("short trigger", short, 1), ("inline trigger", inline, 1), ("include", include, 1), ("labels", labels, 1),
             ("in steps", in_steps, 0), ("loose gate", loose, 1), ("negated gate", negated, 1),
             ("commented jobs", commented, 1),("named", named, 0), ("listed", listed, 1), ("free", free, 0), ("billed", billed, 1), ("matrix", matrix, 1), ("gated", gated, 0), ("push only", push_only, 0)]
    ok = True
    for name, text, want in cases:
        got = len(problems(name, text))
        print(("ok   " if got == want else "FAIL ") + f"{name}: {got} problems, want {want}")
        ok &= got == want
    print("check-ci-runners selftest: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
