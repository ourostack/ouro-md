#!/usr/bin/env bash
#
# Local maintainer preflight: confirms the GitHub repo has the release telemetry
# secret names configured. GitHub does not expose secret values here; this only
# checks presence of the required keys.
set -euo pipefail

repo="${1:-ourostack/ouro-md}"
required=(OURO_MD_POSTHOG_KEY OURO_MD_POSTHOG_HOST)

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated"

secret_names="$(gh secret list --repo "$repo" | awk 'NF { print $1 }')"
missing=()

for name in "${required[@]}"; do
  if ! printf '%s\n' "$secret_names" | grep -qx "$name"; then
    missing+=("$name")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  fail "$repo is missing release secret(s): ${missing[*]}"
fi

echo "release secrets ok: $repo has ${required[*]}"
