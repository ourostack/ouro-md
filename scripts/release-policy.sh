#!/usr/bin/env bash
#
# Shared release policy for CI, release packaging, and local maintainer checks.
# It answers three questions:
#   freshness         Does this app/release-affecting change have a new version?
#   scan              Are source/artifacts free of a forbidden legacy brand token?
#   verify-published  Does the public release/installer point at this build?
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

repo_default="ourostack/ouro-md"

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/release-policy.sh freshness [--mode auto|pr|main] [--base-ref REF] [--repo OWNER/REPO]
  scripts/release-policy.sh release-exists --version X.Y.Z [--repo OWNER/REPO]
  scripts/release-policy.sh scan [PATH...]
  scripts/release-policy.sh selftest-pr-base
  scripts/release-policy.sh selftest-package-guards
  scripts/release-policy.sh selftest-shell-dependency-watch
  scripts/release-policy.sh selftest-live-update-runner
  scripts/release-policy.sh verify-local --version X.Y.Z --sha SHA --zip ZIP --manifest MANIFEST
  scripts/release-policy.sh verify-published [--repo OWNER/REPO] [--version X.Y.Z] [--sha SHA]
USAGE
  exit 2
}

current_version() {
  ./scripts/verify-release-version.sh --print
}

json_get() {
  local field="$1"
  python3 -c '
import json
import sys

field = sys.argv[1]
try:
    value = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)

for part in field.split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
    if value is None:
        break

if isinstance(value, bool):
    print("true" if value else "false")
elif value is not None:
    print(value)
' "$field"
}

strip_v() {
  printf '%s' "${1#v}"
}

semver_gt() {
  python3 - "$1" "$2" <<'PY'
import re
import sys

def parse(raw):
    raw = raw.removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", raw):
        raise SystemExit(2)
    return tuple(int(p) for p in raw.split("."))

sys.exit(0 if parse(sys.argv[1]) > parse(sys.argv[2]) else 1)
PY
}

semver_lt() {
  python3 - "$1" "$2" <<'PY'
import re
import sys

def parse(raw):
    raw = raw.removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", raw):
        raise SystemExit(2)
    return tuple(int(p) for p in raw.split("."))

sys.exit(0 if parse(sys.argv[1]) < parse(sys.argv[2]) else 1)
PY
}

release_relevant_path() {
  case "$1" in
    # Test-only harnesses and probe runners: they live in the binary (or run only
    # in CI) but are reachable solely via --xxxtest / --xxxprobe flags and test
    # scripts — never normal app launch — so they change nothing a user sees and
    # don't gate a user-facing release. Keep the *Test/*Probe naming (or extend the
    # explicit list) when adding a harness. NOTE: these patterns must precede the
    # Sources/* line below, since the first matching case wins.
    Sources/OuroMD/*Test.swift|Sources/OuroMD/*Probe.swift) return 1 ;;
    Sources/OuroMD/Snapshot.swift|Sources/OuroMD/RoundTrip.swift|Sources/OuroMD/HeadlessHarness.swift) return 1 ;;
    scripts/run-native-scenarios.sh|scripts/run-visual-qa.sh|scripts/swift-test-budget.sh) return 1 ;;

    # Anything that shapes the shipped artifact, or how it's built, packaged,
    # installed, or verified for publish, DOES gate a release.
    Package.swift|Package.resolved|make-app.sh) return 0 ;;
    Sources/*|Resources/*|web/*) return 0 ;;
    scripts/lib/app-version.sh) return 0 ;;
    scripts/check-hosted-installer.sh|scripts/check-live-update-path.sh|scripts/check-shell-dependency.sh|scripts/check-signing-readiness.sh|scripts/package-release.sh|scripts/pr-preflight.sh) return 0 ;;
    scripts/check-shell-boundary.sh|scripts/shell-boundary-allowlist.txt) return 0 ;;
    scripts/verify-packaged-app.sh|scripts/verify-release-version.sh|scripts/release-policy.sh) return 0 ;;
    .github/workflows/release.yml) return 0 ;;
    *) return 1 ;;
  esac
}

filter_release_relevant() {
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if release_relevant_path "$path"; then
      printf '%s\n' "$path"
    fi
  done
}

stream_has_needle() {
  local needle="$1"
  if command -v rg >/dev/null 2>&1; then
    LC_ALL=C rg -a -i -q -- "$needle"
  else
    LC_ALL=C grep -a -i -q -- "$needle"
  fi
}

content_paths_with_needle() {
  local path="$1"
  local needle="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -l -a -i --hidden --no-ignore --no-messages --glob '!.git/**' -- "$needle" "$path"
    return
  fi

  python3 - "$needle" "$path" <<'PY'
import os
import sys

needle = sys.argv[1].encode("utf-8").lower()
root = sys.argv[2]
matches = []

def contains_needle(path):
    try:
        with open(path, "rb") as fh:
            return needle in fh.read().lower()
    except OSError:
        return False

if os.path.isdir(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name != ".git"]
        for filename in filenames:
            path = os.path.join(dirpath, filename)
            if contains_needle(path):
                matches.append(path)
else:
    if contains_needle(root):
        matches.append(root)

for match in matches:
    print(match)
sys.exit(0 if matches else 1)
PY
}

release_list_json() {
  local repo="$1"
  gh release list --repo "$repo" --limit 100 --json tagName,isDraft,isPrerelease,isLatest
}

first_stable_release_tag() {
  python3 -c '
import json
import sys

for release in json.load(sys.stdin):
    if not release.get("isDraft") and not release.get("isPrerelease"):
        print(release.get("tagName", ""))
        sys.exit(0)
' 
}

release_list_has_tag() {
  local tag="$1"
  python3 -c '
import json
import sys

tag = sys.argv[1]
for release in json.load(sys.stdin):
    if release.get("tagName") == tag:
        sys.exit(0)
sys.exit(1)
' "$tag"
}

release_view_json() {
  local repo="$1"
  local tag="$2"
  gh release view "$tag" --repo "$repo" --json tagName,targetCommitish,url
}

latest_release_json() {
  local repo="$1"
  local list_json tag
  list_json="$(release_list_json "$repo")" || return $?
  tag="$(printf '%s' "$list_json" | first_stable_release_tag)"
  [[ -n "$tag" ]] || return 3
  release_view_json "$repo" "$tag"
}

release_json_for_version() {
  local repo="$1"
  local version="$2"
  release_view_json "$repo" "v${version}"
}

resolve_commit() {
  git rev-parse --verify --quiet "$1" 2>/dev/null \
    || git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null \
    || printf '%s\n' "$1"
}

resolve_pr_base_ref() {
  local base_ref="$1"
  local candidate="$base_ref"
  local fetch_branch=""

  case "$base_ref" in
    origin/*)
      candidate="$base_ref"
      fetch_branch="${base_ref#origin/}"
      ;;
    refs/remotes/origin/*)
      candidate="$base_ref"
      fetch_branch="${base_ref#refs/remotes/origin/}"
      ;;
    refs/heads/*)
      fetch_branch="${base_ref#refs/heads/}"
      candidate="origin/$fetch_branch"
      ;;
    refs/*)
      candidate="$base_ref"
      ;;
    *)
      if [[ "$base_ref" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
        candidate="$base_ref"
      else
        fetch_branch="$base_ref"
        candidate="origin/$fetch_branch"
      fi
      ;;
  esac

  if [[ -n "$fetch_branch" ]]; then
    git fetch --no-tags origin "$fetch_branch" >/dev/null 2>&1 || true
  fi

  if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
    printf '%s\n' "$candidate"
    return 0
  fi
  if [[ "$candidate" != "$base_ref" ]] && git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
    printf '%s\n' "$base_ref"
    return 0
  fi

  fail "could not resolve PR base ref '$base_ref' (tried '$candidate')"
}

changed_files_for_pr() {
  local base_ref="$1"
  local resolved_base committed
  if ! resolved_base="$(resolve_pr_base_ref "$base_ref")"; then
    return 1
  fi
  if ! git merge-base "$resolved_base" HEAD >/dev/null 2>&1; then
    echo "error: could not compute merge base between '$resolved_base' and HEAD" >&2
    return 1
  fi
  if ! committed="$(git diff --name-only "$resolved_base"...HEAD)"; then
    echo "error: could not diff PR base '$resolved_base' against HEAD" >&2
    return 1
  fi
  {
    printf '%s\n' "$committed"
    git diff --name-only
    git diff --cached --name-only
  } | sort -u
}

changed_files_since() {
  local base="$1"
  {
    git diff --name-only "$base"...HEAD 2>/dev/null || git diff --name-only "$base" HEAD
    git diff --name-only
    git diff --cached --name-only
  } | sort -u
}

freshness_mode() {
  local mode="auto"
  local base_ref="${GITHUB_BASE_REF:-main}"
  local repo="${GITHUB_REPOSITORY:-$repo_default}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --base-ref) base_ref="${2:-}"; shift 2 ;;
      --repo) repo="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [[ "$mode" =~ ^(auto|pr|main)$ ]] || usage
  [[ -n "$base_ref" ]] || fail "--base-ref must not be empty"

  if [[ "$mode" == "auto" ]]; then
    case "${GITHUB_EVENT_NAME:-}" in
      pull_request|pull_request_target) mode="pr" ;;
      push) mode="main" ;;
      *) mode="pr" ;;
    esac
  fi

  local version
  version="$(current_version)"

  local latest_json latest_status latest_tag latest_version
  set +e
  latest_json="$(latest_release_json "$repo")"
  latest_status=$?
  set -e
  if [[ "$latest_status" != "0" ]]; then
    if [[ "$latest_status" != "3" ]]; then
      fail "could not read latest release for $repo"
    fi
    echo "release freshness: no published releases found for $repo; allowing $version"
    return 0
  fi
  latest_tag="$(printf '%s' "$latest_json" | json_get tagName)"
  latest_version="$(strip_v "$latest_tag")"

  if semver_lt "$version" "$latest_version"; then
    fail "source version $version is older than latest published release $latest_tag"
  fi

  if [[ "$mode" == "pr" ]]; then
    local changed relevant
    if ! changed="$(changed_files_for_pr "$base_ref")"; then
      exit 1
    fi
    relevant="$(printf '%s\n' "$changed" | filter_release_relevant || true)"
    if [[ -z "$relevant" ]]; then
      echo "release freshness: no app/release-affecting paths changed"
      return 0
    fi
    if semver_gt "$version" "$latest_version"; then
      echo "release freshness: $version is newer than latest release $latest_tag"
      return 0
    fi
    printf '%s\n' "$relevant" >&2
    fail "app/release-affecting changes require a version greater than latest published release $latest_tag"
  fi

  local release_list current_json
  release_list="$(release_list_json "$repo")" || fail "could not list releases for $repo"
  if ! printf '%s' "$release_list" | release_list_has_tag "v${version}"; then
    echo "release freshness: v$version does not exist yet; release workflow may publish it"
    return 0
  fi
  current_json="$(release_json_for_version "$repo" "$version")" || fail "could not read release v$version for $repo"

  local target target_sha head_sha changed relevant
  target="$(printf '%s' "$current_json" | json_get targetCommitish)"
  target_sha="$(resolve_commit "$target")"
  head_sha="$(git rev-parse HEAD)"
  if [[ "$target_sha" == "$head_sha" ]]; then
    echo "release freshness: v$version already points at this commit"
    return 0
  fi

  changed="$(changed_files_since "$target_sha")"
  relevant="$(printf '%s\n' "$changed" | filter_release_relevant || true)"
  if [[ -z "$relevant" ]]; then
    echo "release freshness: v$version exists at $target_sha, but no app/release-affecting paths changed"
    return 0
  fi

  printf '%s\n' "$relevant" >&2
  fail "v$version already exists at $target_sha; app/release-affecting main changes need a new version"
}

scan_path() {
  local path="$1"
  local needle
  needle="$(printf '\x74\x79\x70\x6f\x72\x61')"

  [[ -e "$path" ]] || fail "scan path not found: $path"

  local failed=0
  if [[ -f "$path" && "$path" == *.zip ]]; then
    if ! unzip -tqq "$path" >/dev/null 2>&1; then
      echo "zip archive is unreadable or malformed: $path" >&2
      failed=1
    fi
    if unzip -p "$path" 2>/dev/null | stream_has_needle "$needle"; then
      echo "forbidden legacy brand token found inside zip: $path" >&2
      failed=1
    fi
    if unzip -Z1 "$path" 2>/dev/null | stream_has_needle "$needle"; then
      echo "forbidden legacy brand token found in zip filename: $path" >&2
      failed=1
    fi
  else
    if content_paths_with_needle "$path" "$needle"; then
      failed=1
    fi
  fi

  if [[ -d "$path" ]]; then
    if find "$path" -path '*/.git' -prune -o -iname "*$needle*" -print | grep -q .; then
      find "$path" -path '*/.git' -prune -o -iname "*$needle*" -print >&2
      failed=1
    fi
  else
    local name
    name="$(basename "$path")"
    if printf '%s\n' "$name" | stream_has_needle "$needle"; then
      echo "forbidden legacy brand token found in filename: $path" >&2
      failed=1
    fi
  fi

  return "$failed"
}

scan_mode() {
  local paths=("$@")
  if [[ "${#paths[@]}" -eq 0 ]]; then
    paths=(".")
  fi

  local failed=0
  local path
  for path in "${paths[@]}"; do
    if ! scan_path "$path"; then
      failed=1
    fi
  done

  if [[ "$failed" == "1" ]]; then
    fail "artifact policy scan failed"
  fi
  echo "release policy scan ok"
}

selftest_pr_base_mode() {
  mkdir -p .build

  local ref
  for ref in main origin/main refs/heads/main refs/remotes/origin/main; do
    changed_files_for_pr "$ref" >/dev/null \
      || fail "PR base selftest failed to resolve '$ref'"
  done

  local missing="origin/__ouro-md-missing-pr-base"
  if changed_files_for_pr "$missing" >/dev/null 2>.build/ouro-release-policy-selftest.err; then
    fail "PR base selftest unexpectedly resolved missing ref '$missing'"
  fi

  echo "release policy PR base selftest ok"
}

# Locks the release_relevant_path classifier so the "test-only changes don't gate
# a release" narrowing can't silently regress (e.g. a reordered case statement, or
# a dropped exclusion, would quietly bring the churn back).
selftest_paths_mode() {
  local must_gate=(
    Sources/OuroMD/Themes.swift
    Sources/OuroMD/AppDelegate.swift
    Sources/OuroMD/main.swift
    Sources/OuroMDCore/OuroMDRelease.swift
    Sources/OuroMD/web/bridge.js
    make-app.sh
    scripts/lib/app-version.sh
    scripts/check-shell-dependency.sh
    scripts/check-shell-boundary.sh
    scripts/verify-release-version.sh
    scripts/release-policy.sh
  )
  local must_skip=(
    Sources/OuroMD/TableWrapTest.swift
    Sources/OuroMD/RenderProbe.swift
    Sources/OuroMD/PerformanceProbe.swift
    Sources/OuroMD/Snapshot.swift
    Sources/OuroMD/RoundTrip.swift
    Sources/OuroMD/HeadlessHarness.swift
    scripts/run-native-scenarios.sh
    scripts/swift-test-budget.sh
    Tests/OuroMDTests/Example.swift
    README.md
  )
  local p
  for p in "${must_gate[@]}"; do
    release_relevant_path "$p" || fail "paths selftest: '$p' should gate a release but doesn't"
  done
  for p in "${must_skip[@]}"; do
    ! release_relevant_path "$p" || fail "paths selftest: '$p' should NOT gate a release but does"
  done
  echo "release policy paths selftest ok"
}

selftest_package_guards_mode() {
  python3 <<'PY'
from pathlib import Path

package = Path("scripts/package-release.sh").read_text(encoding="utf-8")
guard = "./scripts/check-shell-dependency.sh"
build = "./make-app.sh"

if guard not in package:
    raise SystemExit("package-release.sh must run scripts/check-shell-dependency.sh")
if build not in package:
    raise SystemExit("package-release.sh no longer runs make-app.sh; update this selftest")
if package.index(guard) > package.index(build):
    raise SystemExit("package-release.sh must run scripts/check-shell-dependency.sh before make-app.sh")

workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
if "scripts/check-shell-dependency.sh" not in workflow:
    raise SystemExit("release.yml must treat scripts/check-shell-dependency.sh as release-path input")
if "scripts/lib/app-version.sh" not in workflow:
    raise SystemExit("release.yml must treat scripts/lib/app-version.sh as release-path input")

ci = Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
preflight = Path("scripts/pr-preflight.sh").read_text(encoding="utf-8")
for surface, text in (("ci.yml", ci), ("pr-preflight.sh", preflight)):
    if "scripts/check-shell-boundary.sh" not in text:
        raise SystemExit(f"{surface} must run scripts/check-shell-boundary.sh")
PY
  echo "release package guard selftest ok"
}

selftest_shell_dependency_watch_mode() {
  bash -n scripts/refresh-shell-dependency.sh
  python3 <<'PY'
from pathlib import Path

workflow = Path(".github/workflows/shell-dependency-watch.yml").read_text(encoding="utf-8")
refresh = Path("scripts/refresh-shell-dependency.sh").read_text(encoding="utf-8")

workflow_needles = [
    "workflow_dispatch:",
    "repository_dispatch:",
    "ouro-native-apple-app-shell-main-updated",
    "schedule:",
    "contents: write",
    "pull-requests: write",
    "macos-14",
    "./scripts/check-shell-dependency.sh",
    "./scripts/refresh-shell-dependency.sh",
    "automation/ouro-md-refresh-shell-dependency",
    "already has the desired tree",
    "no open PR was found; creating one",
    "gh pr create",
]
for needle in workflow_needles:
    if needle not in workflow:
        raise SystemExit(f"shell-dependency-watch.yml must contain {needle!r}")

refresh_needles = [
    "./scripts/check-shell-dependency.sh",
    "git status --porcelain",
    "non_shell_pin_snapshot",
    'swift package update "$identity"',
    "./scripts/bump-version.sh",
    "releaseHighlights",
    "./scripts/verify-release-version.sh",
]
for needle in refresh_needles:
    if needle not in refresh:
        raise SystemExit(f"refresh-shell-dependency.sh must contain {needle!r}")
PY
  echo "shell dependency watch selftest ok"
}

selftest_live_update_runner_mode() {
  python3 <<'PY'
from pathlib import Path

script = Path("scripts/check-live-update-path.sh").read_text(encoding="utf-8")
for forbidden in ("OURO_MD_EXE", ".build/debug/ouro-md"):
    if forbidden in script:
        raise SystemExit(f"check-live-update-path.sh must not run current-source {forbidden} as the updater under test")

required = [
    'runner_app="$tmp/runner/Ouro MD.app"',
    'runner_exe="$runner_app/Contents/MacOS/ouro-md"',
    'runner_version="$(exe_version "$runner_exe" || true)"',
    '"$runner_exe" \\',
    '--liveupdatetest',
    '--live-update-destination "$dest"',
]
for needle in required:
    if needle not in script:
        raise SystemExit(f"check-live-update-path.sh must contain {needle!r}")
PY
  echo "live update runner selftest ok"
}

release_exists_mode() {
  local repo="${GITHUB_REPOSITORY:-$repo_default}"
  local version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [[ -n "$version" ]] || fail "--version is required"

  local release_list
  release_list="$(release_list_json "$repo")" || fail "could not list releases for $repo"
  if printf '%s' "$release_list" | release_list_has_tag "v${version}"; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

verify_manifest() {
  local manifest="$1"
  local version="$2"
  local sha="$3"
  local zip="$4"

  python3 - "$manifest" "$version" "$sha" "$zip" <<'PY'
import hashlib
import json
import os
import sys

manifest_path, expected_version, expected_sha, zip_path = sys.argv[1:5]
with open(manifest_path, "r", encoding="utf-8") as fh:
    manifest = json.load(fh)

errors = []
if manifest.get("version") != expected_version:
    errors.append(f"version {manifest.get('version')!r} != {expected_version!r}")
if manifest.get("build") != expected_version:
    errors.append(f"build {manifest.get('build')!r} != {expected_version!r}")
if manifest.get("bundleIdentifier") != "org.ourostack.ouro-md":
    errors.append(f"bundleIdentifier {manifest.get('bundleIdentifier')!r}")
if manifest.get("gitSha") != expected_sha:
    errors.append(f"gitSha {manifest.get('gitSha')!r} != {expected_sha!r}")
if manifest.get("archive") != os.path.basename(zip_path):
    errors.append(f"archive {manifest.get('archive')!r} != {os.path.basename(zip_path)!r}")

with open(zip_path, "rb") as fh:
    data = fh.read()
actual_sha = hashlib.sha256(data).hexdigest()
actual_bytes = len(data)
if manifest.get("sha256") != actual_sha:
    errors.append("sha256 mismatch")
if manifest.get("bytes") != actual_bytes:
    errors.append(f"bytes {manifest.get('bytes')!r} != {actual_bytes!r}")

if errors:
    for error in errors:
        print(f"manifest verification failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
}

verify_local_mode() {
  local version=""
  local sha=""
  local zip=""
  local manifest=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) version="${2:-}"; shift 2 ;;
      --sha) sha="${2:-}"; shift 2 ;;
      --zip) zip="${2:-}"; shift 2 ;;
      --manifest) manifest="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [[ -n "$version" ]] || fail "--version is required"
  [[ -n "$sha" ]] || fail "--sha is required"
  [[ -n "$zip" ]] || fail "--zip is required"
  [[ -n "$manifest" ]] || fail "--manifest is required"
  [[ -s "$zip" ]] || fail "zip missing or empty: $zip"
  [[ -s "$manifest" ]] || fail "manifest missing or empty: $manifest"

  verify_manifest "$manifest" "$version" "$sha" "$zip"
  scan_mode "$manifest" "$zip"

  local tmp app
  tmp="$(mktemp -d /tmp/ouro-md-local-release.XXXXXX)"
  mkdir -p "$tmp/extracted"
  ditto -x -k "$zip" "$tmp/extracted"
  app="$(find "$tmp/extracted" -maxdepth 2 -name '*.app' -type d | head -1)"
  [[ -n "$app" ]] || fail "release zip did not contain an app bundle"
  OURO_MD_EXPECT_GIT_SHA="$sha" ./scripts/verify-packaged-app.sh "$app"
  rm -rf "$tmp"

  echo "local release artifact verified: $zip ($sha)"
}

verify_published_mode() {
  local repo="${GITHUB_REPOSITORY:-$repo_default}"
  local version=""
  local sha=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --sha) sha="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done

  [[ -n "$version" ]] || version="$(current_version)"
  [[ -n "$sha" ]] || sha="$(git rev-parse HEAD)"

  local tag="v${version}"
  local zip_name="Ouro-MD-${version}.zip"
  local manifest_name="Ouro-MD-${version}.manifest.json"
  local tmp
  tmp="$(mktemp -d /tmp/ouro-md-published.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN

  local release_json=""
  local attempt
  for attempt in $(seq 1 18); do
    if release_json="$(gh release view "$tag" --repo "$repo" --json tagName,targetCommitish,url 2>/dev/null)"; then
      break
    fi
    sleep 5
  done
  [[ -n "$release_json" ]] || fail "published release $tag was not visible"

  local latest_json latest_tag
  latest_json="$(latest_release_json "$repo")"
  latest_tag="$(printf '%s' "$latest_json" | json_get tagName)"
  [[ "$latest_tag" == "$tag" ]] || fail "latest release is $latest_tag, expected $tag"

  local target target_sha
  target="$(printf '%s' "$release_json" | json_get targetCommitish)"
  target_sha="$(resolve_commit "$target")"
  [[ "$target_sha" == "$sha" ]] || fail "$tag targets $target_sha, expected $sha"

  gh release download "$tag" --repo "$repo" --pattern "$zip_name" --dir "$tmp" >/dev/null
  gh release download "$tag" --repo "$repo" --pattern "$manifest_name" --dir "$tmp" >/dev/null
  [[ -s "$tmp/$zip_name" ]] || fail "downloaded zip missing: $zip_name"
  [[ -s "$tmp/$manifest_name" ]] || fail "downloaded manifest missing: $manifest_name"

  OURO_MD_EXPECT_TELEMETRY=1 verify_local_mode \
    --version "$version" \
    --sha "$sha" \
    --zip "$tmp/$zip_name" \
    --manifest "$tmp/$manifest_name"

  local install_dir="$tmp/install"
  mkdir -p "$install_dir"
  OURO_MD_INSTALL_DIR="$install_dir" OURO_MD_NO_OPEN=1 OURO_MD_NO_ALIAS=1 bash web/ouro-md-install.sh
  local installed="$install_dir/Ouro MD.app"
  [[ -d "$installed" ]] || fail "installer smoke did not install Ouro MD.app"
  local installed_version
  installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed/Contents/Info.plist")"
  [[ "$installed_version" == "$version" ]] || fail "installer installed $installed_version, expected $version"
  scan_mode "$installed"

  echo "published release verified: $tag ($sha)"
}

cmd="${1:-}"
[[ -n "$cmd" ]] || usage
shift

case "$cmd" in
  freshness) freshness_mode "$@" ;;
  release-exists) release_exists_mode "$@" ;;
  scan) scan_mode "$@" ;;
  selftest-pr-base) selftest_pr_base_mode "$@" ;;
  selftest-package-guards) selftest_package_guards_mode "$@" ;;
  selftest-shell-dependency-watch) selftest_shell_dependency_watch_mode "$@" ;;
  selftest-live-update-runner) selftest_live_update_runner_mode "$@" ;;
  selftest-paths) selftest_paths_mode "$@" ;;
  verify-local) verify_local_mode "$@" ;;
  verify-published) verify_published_mode "$@" ;;
  *) usage ;;
esac
