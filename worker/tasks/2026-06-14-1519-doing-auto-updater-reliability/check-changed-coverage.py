#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path


EXCLUDED_NAMES = {
    "UndoTest.swift",
    "WrapTest.swift",
    "RenderProbe.swift",
    "RoundTrip.swift",
    "Snapshot.swift",
    "main.swift",
}


def run(args):
    return subprocess.check_output(args, text=True).strip()


def changed_swift_files(base):
    out = run(["git", "diff", "--name-only", base, "HEAD", "--", "Sources/OuroMD/*.swift"])
    files = []
    for line in out.splitlines():
        path = Path(line)
        if path.name not in EXCLUDED_NAMES:
            files.append(line)
    return files


def load_noops(path):
    noops = {}
    if not path.exists():
        return noops
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line.startswith("- ") or " - " not in line:
            continue
        spec = line[2:].split(" - ", 1)[0].strip()
        if ": " in spec:
            file_path, span = spec.split(": ", 1)
        elif ":" in spec:
            file_path, span = spec.rsplit(":", 1)
        else:
            continue
        file_path = file_path.strip()
        span = span.strip()
        if span == "all":
            noops.setdefault(file_path, []).append(None)
        elif "-" in span:
            start, end = span.split("-", 1)
            noops.setdefault(file_path, []).append((int(start), int(end)))
        else:
            value = int(span)
            noops.setdefault(file_path, []).append((value, value))
    return noops


def is_noop(noops, path, line):
    for span in noops.get(path, []):
        if span is None:
            return True
        if span[0] <= line <= span[1]:
            return True
    return False


def executable_counts(file_record):
    segments = sorted(file_record.get("segments", []), key=lambda s: (s[0], s[1]))
    counts = {}
    active = None
    active_line = None
    def mark(line, count):
        counts[line] = max(count, counts.get(line, 0))

    for segment in segments:
        line = int(segment[0])
        count = int(segment[2])
        has_count = bool(segment[3])
        if active is not None and active_line is not None:
            for covered_line in range(active_line, line):
                mark(covered_line, active)
        if has_count:
            mark(line, count)
            active = count
            active_line = line
        else:
            active = None
            active_line = line
    if active is not None and active_line is not None:
        mark(active_line, active)
    return counts


def normalize_filename(filename):
    path = Path(filename)
    try:
        return str(path.resolve().relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--coverage", required=True)
    args = parser.parse_args()

    coverage_path = Path(args.coverage)
    noops = load_noops(coverage_path.with_name("coverage-noop-disposition.md"))
    changed = set(changed_swift_files(args.base))
    payload = json.loads(coverage_path.read_text())

    records = {}
    for data in payload.get("data", []):
        for file_record in data.get("files", []):
            normalized = normalize_filename(file_record.get("filename", ""))
            if normalized in changed:
                records[normalized] = executable_counts(file_record)

    missing = []
    uncovered = []
    for path in sorted(changed):
        counts = records.get(path)
        if counts is None:
            if not is_noop(noops, path, 1):
                missing.append(path)
            continue
        for line, count in sorted(counts.items()):
            if count == 0 and not is_noop(noops, path, line):
                uncovered.append((path, line))

    checked_lines = sum(len(records.get(path, {})) for path in changed)
    noop_files = [path for path in changed if is_noop(noops, path, 1)]

    print(f"changed_files={len(changed)} checked_executable_lines={checked_lines} noop_files={len(noop_files)}")
    if noop_files:
        print("noop_files:")
        for path in sorted(noop_files):
            print(f"  {path}")
    if missing:
        print("missing_coverage_records:")
        for path in missing:
            print(f"  {path}")
    if uncovered:
        print("uncovered_lines:")
        for path, line in uncovered[:200]:
            print(f"  {path}:{line}")
        if len(uncovered) > 200:
            print(f"  ... {len(uncovered) - 200} more")
    if missing or uncovered:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
