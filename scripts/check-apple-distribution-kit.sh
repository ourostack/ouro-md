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

if git grep -n -- '-----BEGIN PRIVATE KEY-----' -- . ':!docs' ':!README.md' >/tmp/ouro-md-apple-secret-scan.txt; then
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
./scripts/check-shell-boundary.sh

echo "apple distribution kit contract ok"
