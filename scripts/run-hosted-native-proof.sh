#!/usr/bin/env bash
# Only disposable hosted jobs may present windows or change accessibility keys.
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${OURO_NATIVE_PREFERENCE_PROOF:-}" != 1 ]]; then
  echo "Hosted native proof requires GITHUB_ACTIONS=true and explicit opt-in." >&2
  exit 2
fi
mode="${1:-}"
case "$mode" in
  media) root="${OURO_SITE_MEDIA_OUTPUT:-.build/site-media}" ;;
  header) root="${OURO_HEADER_OUTPUT:-.build/header-rendering/current}" ;;
  accessibility) root=".build/accessibility-proof" ;;
  *) echo "Usage: run-hosted-native-proof.sh media|header|accessibility" >&2; exit 2 ;;
esac
backup="$root/preferences"
mkdir -p "$backup"
if [[ "${2:-}" != --restore ]]; then
  for key in reduceMotion reduceTransparency; do
    if defaults read com.apple.universalaccess "$key" > "$backup/$key.before" 2>/dev/null; then
      touch "$backup/$key.existed"
    fi
  done
  touch "$backup/initialized"
fi
bool_value() {
  case "$1" in
    1|true|TRUE|yes|YES) printf true ;;
    0|false|FALSE|no|NO) printf false ;;
    *) return 1 ;;
  esac
}
restore() {
  local test_status=$? failures=0
  set +e
  for key in reduceMotion reduceTransparency; do
    if [[ -f "$backup/$key.existed" ]]; then
      defaults write com.apple.universalaccess "$key" -bool "$(bool_value "$(cat "$backup/$key.before")")" || failures=1
      defaults read com.apple.universalaccess "$key" > "$backup/$key.restored" || failures=1
      cmp "$backup/$key.before" "$backup/$key.restored" || failures=1
    else
      defaults delete com.apple.universalaccess "$key" 2>/dev/null || true
      if defaults read com.apple.universalaccess "$key" 2>/dev/null; then failures=1; fi
    fi
  done
  echo "test_status=$test_status restoration_failures=$failures" > "$backup/restoration.txt"
  if [[ "$test_status" != 0 ]]; then exit "$test_status"; fi
  exit "$failures"
}
if [[ "${2:-}" == --restore ]]; then
  if [[ ! -f "$backup/initialized" ]]; then
    echo "No owned preference changes initialized; nothing to restore."
    exit 0
  fi
  restore
fi
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "$mode" != accessibility ]]; then
  defaults write com.apple.universalaccess reduceMotion -bool false
  defaults write com.apple.universalaccess reduceTransparency -bool false
  if [[ "$mode" == media ]]; then
    export OURO_SITE_MEDIA=1 OURO_SITE_MEDIA_STANDARD_PROFILE=1
    swift test --filter NativeSiteMediaCaptureTests
  else
    export OURO_HEADER_RENDERING=1 OURO_HEADER_STANDARD_PROFILE=1
    swift test --filter NativeHeaderRenderingTests
  fi
else
  export OURO_ACCESSIBILITY_OUTPUT="$root/${OURO_ACCESSIBILITY_STATE:?}"
  defaults write com.apple.universalaccess reduceMotion -bool "$(bool_value "${OURO_EXPECT_REDUCE_MOTION:?}")"
  defaults write com.apple.universalaccess reduceTransparency -bool "$(bool_value "${OURO_EXPECT_REDUCE_TRANSPARENCY:?}")"
  swift test --filter NativeAccessibilityPreferenceTests
fi
