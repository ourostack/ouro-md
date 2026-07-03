#!/usr/bin/env bash
#
# Thin Ouro MD adapter for the shared Apple Distribution Kit. Keep release
# policy here app-local; keep Apple distribution behavior in the shared kit.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "error: $*" >&2
  exit 1
}

if [[ -n "${APPLE_DISTRIBUTION_KIT_BIN:-}" ]]; then
  [[ -x "$APPLE_DISTRIBUTION_KIT_BIN" || -f "$APPLE_DISTRIBUTION_KIT_BIN" ]] \
    || fail "APPLE_DISTRIBUTION_KIT_BIN does not exist: $APPLE_DISTRIBUTION_KIT_BIN"
  case "$APPLE_DISTRIBUTION_KIT_BIN" in
    *.js) exec node "$APPLE_DISTRIBUTION_KIT_BIN" "$@" ;;
    *) exec "$APPLE_DISTRIBUTION_KIT_BIN" "$@" ;;
  esac
fi

if [[ -f ".ci/apple-distribution-kit/dist/cli.js" ]]; then
  exec node ".ci/apple-distribution-kit/dist/cli.js" "$@"
fi

if [[ -f "../apple-distribution-kit/dist/cli.js" ]]; then
  exec node "../apple-distribution-kit/dist/cli.js" "$@"
fi

if command -v apple-distribution-kit >/dev/null 2>&1; then
  exec apple-distribution-kit "$@"
fi

fail "apple-distribution-kit is not available; build ../apple-distribution-kit or install the shared package"
