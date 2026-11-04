#!/usr/bin/env python3
"""Checks an Ouro AX X-ray report against config/xray-expected.json.

    python3 -I scripts/check-xray.py <report.json> [--expected config/xray-expected.json]
    python3 -I scripts/check-xray.py --selftest

Every claim listed under "hold" must hold (every check on it passes). Every other claim must be listed under "open"
with the reason it can't hold yet, and must not fail. A claim that starts holding without being listed fails too, so
the expected file always says what the app proves. Exit 0 when all is as expected, 1 when not, 2 for a usage mistake.
"""
import json
import sys
from pathlib import Path


def statuses(report):
    """claim id -> "hold", "fail" or "open" (skipped or not checked)."""
    by_claim = {}
    for result in report["results"]:
        by_claim.setdefault(result["claim"], []).append(result["verdict"])
    out = {}
    for claim in report["claims"]:
        verdicts = by_claim.get(claim["id"], [])
        if "fail" in verdicts:
            out[claim["id"]] = "fail"
        elif verdicts and all(v == "pass" for v in verdicts):
            out[claim["id"]] = "hold"
        else:
            out[claim["id"]] = "open"
    return out


def check(report, expected):
    """The problems, one line each, each with its fix; empty when the report is as expected."""
    problems = []
    hold = set(expected["hold"])
    open_ = expected["open"]
    for claim, reason in open_.items():
        if not reason.strip():
            problems.append(f"{claim}: listed as open with no reason. Fix: say why it can't hold yet in config/xray-expected.json.")
    found = statuses(report)
    for claim in sorted(hold & set(open_)):
        problems.append(f"{claim}: listed under both hold and open. Fix: keep it in one of them in config/xray-expected.json.")
    for claim in sorted((hold | set(open_)) - set(found)):
        problems.append(f"{claim}: not in the report (claim set {report['claimSet']['version']}). Fix: remove it from config/xray-expected.json, or check the app still has what it covers.")
    for claim, status in found.items():
        notes = "; ".join(r["note"] for r in report["results"] if r["claim"] == claim and r["verdict"] != "pass")
        if status == "fail":
            problems.append(f"{claim}: fails ({notes}). Fix: the report's fix for {claim}, then run the X-ray again.")
        elif claim in hold and status != "hold":
            problems.append(f"{claim}: expected to hold but is open ({notes}). Fix: restore it, or move it to open with the reason.")
        elif claim not in hold and status == "hold":
            problems.append(f"{claim}: holds now but is listed as open. Fix: move it to hold in config/xray-expected.json.")
        elif claim not in hold and claim not in open_:
            problems.append(f"{claim}: open and not listed ({notes}). Fix: add it to open in config/xray-expected.json with the reason.")
    return problems


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if not argv or argv[0].startswith("-"):
        print("check-xray: give the report: python3 -I scripts/check-xray.py <report.json>", file=sys.stderr)
        return 2
    expected_path = Path(__file__).resolve().parent.parent / "config" / "xray-expected.json"
    if "--expected" in argv:
        expected_path = Path(argv[argv.index("--expected") + 1])
    report = json.loads(Path(argv[0]).read_text())
    expected = json.loads(expected_path.read_text())
    problems = check(report, expected)
    found = statuses(report)
    held = sorted(c for c, s in found.items() if s == "hold")
    print(f"X-ray: {len(held)} of {len(found)} claims hold (claim set {report['claimSet']['version']}, ax-xray {report['checker']['version']}).")
    for claim in sorted(expected["open"]):
        if found.get(claim) == "open":
            print(f"  open {claim}: {expected['open'][claim]}")
    for line in problems:
        print(f"check-xray: {line}", file=sys.stderr)
    return 1 if problems else 0


def selftest():
    def report(results, claims):
        return {"claimSet": {"version": "0.1.0"}, "checker": {"version": "0.2.0"}, "claims": [{"id": c} for c in claims],
                "results": [{"claim": c, "verdict": v, "note": f"{c} note", "surface": "app"} for c, v in results]}
    claims = ["a", "b", "c"]
    good = report([("a", "pass"), ("a", "pass"), ("b", "skip"), ("c", "skip")], claims)
    expected = {"hold": ["a"], "open": {"b": "needs a person", "c": "needs the 27.3 SDK"}}
    cases = [
        ("as expected", check(good, expected), 0),
        ("a fail", check(report([("a", "pass"), ("a", "fail"), ("b", "skip"), ("c", "skip")], claims), expected), 1),
        ("a newly holding claim", check(report([("a", "pass"), ("b", "pass"), ("c", "skip")], claims), expected), 1),
        ("an unlisted open claim", check(good, {"hold": ["a"], "open": {"b": "x"}}), 1),
        ("an open claim with no reason", check(good, {"hold": ["a"], "open": {"b": " ", "c": "x"}}), 1),
        ("a held claim that skips", check(report([("a", "skip"), ("b", "skip"), ("c", "skip")], claims), expected), 1),
        ("a claim the set dropped", check(good, {"hold": ["a", "z"], "open": {"b": "x", "c": "y"}}), 1),
        ("a claim listed twice", check(good, {"hold": ["a"], "open": {"a": "x", "b": "y", "c": "z"}}), 1),
    ]
    ok = True
    for name, problems, want in cases:
        got = len(problems)
        if got != want:
            ok = False
            print(f"FAIL {name}: {got} problems, want {want}: {problems}")
        else:
            print(f"ok   {name}")
    print("check-xray selftest: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
