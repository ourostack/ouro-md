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
    Package.swift|Package.resolved|make-app.sh) return 0 ;;
    Sources/*|Resources/*|web/*) return 0 ;;
    scripts/check-hosted-installer.sh|scripts/check-signing-readiness.sh|scripts/package-release.sh|scripts/pr-preflight.sh) return 0 ;;
    scripts/run-native-scenarios.sh|scripts/run-visual-qa.sh|scripts/swift-test-budget.sh) return 0 ;;
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
  git rev-parse "$1^{commit}" 2>/dev/null || printf '%s\n' "$1"
}

changed_files_for_pr() {
  local base_ref="$1"
  git fetch --no-tags origin "$base_ref" >/dev/null 2>&1 || true
  {
    git diff --name-only "origin/${base_ref}"...HEAD
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
    changed="$(changed_files_for_pr "$base_ref")"
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
  verify-local) verify_local_mode "$@" ;;
  verify-published) verify_published_mode "$@" ;;
  *) usage ;;
esac
