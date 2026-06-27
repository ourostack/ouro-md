#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

checker=".build/checkouts/ouro-native-apple-app-shell/scripts/check-shell-boundary.sh"
if [[ ! -x "$checker" ]]; then
  swift package resolve >/dev/null
fi

[[ -x "$checker" ]] || {
  echo "error: missing shell boundary checker at $checker" >&2
  exit 1
}

if [[ "${1:-}" == "--selftest" ]]; then
  exec "$checker" --selftest
fi

exec "$checker" --repo "$ROOT" --allowlist "$ROOT/scripts/shell-boundary-allowlist.txt"
