#!/usr/bin/env bash
#
# Verifies Ouro MD's Apple distribution contract without requiring signing
# secrets. Secret-backed release jobs can run the same wrapper with apply-mode
# credentials, but CI should always be able to validate the manifest/plan shape.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "error: $*" >&2
  exit 1
}

wrapper="scripts/apple-distribution-kit.sh"
manifest="distribution/apple-distribution.json"
artifact_dir="${APPLE_DISTRIBUTION_ARTIFACT_DIR:-.build/apple-distribution-kit}"
review_artifact="$artifact_dir/app-store-review-prep.json"

[[ -x "$wrapper" ]] || fail "missing thin wrapper: $wrapper"
[[ -f "$manifest" ]] || fail "missing canonical manifest: $manifest"

source_version="$(./scripts/verify-release-version.sh --print)"
manifest_version="$(
  node -e "const m = JSON.parse(require('fs').readFileSync('$manifest', 'utf8')); const c = m.channels.find((channel) => channel.id === 'mac-app-store'); console.log(c?.store?.version ?? '');"
)"
[[ "$manifest_version" == "$source_version" ]] \
  || fail "manifest mac-app-store version $manifest_version does not match OuroMDRelease.version $source_version"

node <<'NODE'
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync("distribution/apple-distribution.json", "utf8"));
const channel = manifest.channels.find((candidate) => candidate.id === "mac-app-store");
const store = channel && channel.store;
function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}
function requireString(field, limit) {
  const value = store && store[field];
  if (typeof value !== "string" || value.trim() === "") {
    fail(`mac-app-store store.${field} is required`);
  }
  if (limit && value.length > limit) {
    fail(`mac-app-store store.${field} exceeds ${limit} characters`);
  }
  return value;
}
if (!store) fail("mac-app-store store metadata is required");
if (store.category !== "DEVELOPER_TOOLS") fail("mac-app-store category must be DEVELOPER_TOOLS");
if (store.subtitle !== "Local Markdown Workspace") fail("mac-app-store subtitle must be Local Markdown Workspace");
const promotionalText = requireString("promotionalText", 170);
const description = requireString("description");
const keywords = requireString("keywords", 100);
const reviewNotes = requireString("reviewNotes");
for (const forbidden of ["The Markdown App", "quiet Markdown editor"]) {
  for (const [field, value] of Object.entries({ promotionalText, description, reviewNotes })) {
    if (value.toLowerCase().includes(forbidden.toLowerCase())) {
      fail(`mac-app-store store.${field} must not use generic phrase: ${forbidden}`);
    }
  }
}
for (const required of ["local Markdown", "command palette"]) {
  if (!promotionalText.toLowerCase().includes(required.toLowerCase())) {
    fail(`mac-app-store promotionalText must mention ${required}`);
  }
}
for (const required of ["folder search", "PDF"]) {
  if (!description.toLowerCase().includes(required.toLowerCase())) {
    fail(`mac-app-store description must mention ${required}`);
  }
}
for (const required of ["markdown", "local files", "folder search", "outline", "command palette", "pdf"]) {
  if (!keywords.toLowerCase().includes(required.toLowerCase())) {
    fail(`mac-app-store keywords must include ${required}`);
  }
}
for (const required of ["Shift-Command-O", "File Tree", "Outline", "Search", "Command Palette", "PDF", "HTML", "No account"]) {
  if (!reviewNotes.toLowerCase().includes(required.toLowerCase())) {
    fail(`mac-app-store reviewNotes must include ${required}`);
  }
}
if (!Array.isArray(store.screenshots) || store.screenshots.length === 0) {
  fail("mac-app-store screenshots must include local assets or explicit remote proof");
}
NODE

if ! grep -Eq 'apple-distribution-kit|apple-distribution-kit/dist/cli\.js' "$wrapper"; then
  fail "$wrapper must delegate to the shared apple-distribution-kit"
fi

secret_files="$(
  git ls-files -c -o --exclude-standard \
    | grep -E '(^|/)(AuthKey_[A-Za-z0-9]+\.p8|[^/]+\.(p8|p12|mobileprovision|provisionprofile|cer))$' \
    || true
)"
if [[ -n "$secret_files" ]]; then
  echo "$secret_files" >&2
  fail "Apple signing credentials/profiles must not be committed or staged in this repo"
fi

private_key_pattern='-----BEGIN ''PRIVATE KEY-----'
if git grep -n -- "$private_key_pattern" -- . ':!docs' ':!README.md' >/tmp/ouro-md-apple-secret-scan.txt; then
  cat /tmp/ouro-md-apple-secret-scan.txt >&2
  fail "private key material must not be committed"
fi

mkdir -p "$artifact_dir"
"$wrapper" manifest validate --manifest "$manifest" --json >"$artifact_dir/manifest-validation.json"
"$wrapper" plan --manifest "$manifest" --json >"$artifact_dir/distribution-plan.json"
"$wrapper" store review-plan \
  --manifest "$manifest" \
  --channel mac-app-store \
  --artifact "$review_artifact" \
  --json >"$artifact_dir/app-store-review-prep.stdout.json"

[[ -s "$review_artifact" ]] || fail "review-prep artifact was not written: $review_artifact"
python3 <<'PY'
from pathlib import Path

package_script = Path("scripts/package-app-store.sh").read_text(encoding="utf-8")
for needle in (
    "./scripts/apple-distribution-kit.sh xcode run",
    "--kind codesign",
    "--kind productbuild",
    "--kind altool-validate",
    "--kind altool-upload",
):
    if needle not in package_script:
        raise SystemExit(f"scripts/package-app-store.sh must delegate {needle!r} through apple-distribution-kit")
for forbidden in (
    "codesign --force",
    "productbuild --component",
    "xcrun altool --validate-app",
    "xcrun altool --upload-package",
):
    if forbidden in package_script:
        raise SystemExit(f"scripts/package-app-store.sh must not bypass apple-distribution-kit with {forbidden!r}")
PY
./scripts/check-shell-boundary.sh

echo "apple distribution kit contract ok"
