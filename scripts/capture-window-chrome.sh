#!/usr/bin/env bash
#
# Captures Ouro MD's real window chrome (title bar, toolbar, sidebar, status
# bar) in light and dark themes, for visual review of the system design. Runs
# the packaged app with a restored session, so it is meant for CI runners, not
# a machine someone is using.
#
#   scripts/capture-window-chrome.sh OuroMD.app out-dir
#
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-OuroMD.app}"
out="${2:-.build/window-chrome}"
domain="bot.ouro.md"
fixtures="$PWD/Tests/Fixtures"
mkdir -p "$out"
[[ -d "$app" ]] || { echo "error: app bundle not found: $app" >&2; exit 1; }

capture() {
  local name="$1" theme="$2" appearance="$3"
  defaults write -g AppleInterfaceStyle -string "$appearance" 2>/dev/null || true
  [[ "$appearance" == "Light" ]] && defaults delete -g AppleInterfaceStyle 2>/dev/null || true
  defaults write "$domain" ouro.hasLaunched -bool true
  defaults write "$domain" ouro.theme -string "$theme"
  defaults write "$domain" ouro.sidebarMode -string files
  defaults write "$domain" ouro.session.folder -string "$fixtures"
  defaults write "$domain" ouro.session.docs -array "$fixtures/dogfood-visual-surface.md"

  open -n "$app"
  local id="" pid=""
  for _ in $(seq 1 60); do
    sleep 0.5
    pid="$(pgrep -nx ouro-md || true)"
    [[ -n "$pid" ]] || continue
    id="$(swift scripts/lib/window-id.swift "$pid" 2>"$out/$name-windows.log" || true)"
    [[ -n "$id" ]] && break
  done
  if [[ -z "$id" ]]; then
    echo "error: no Ouro MD window appeared for $name (pid ${pid:-none})" >&2
    cat "$out/$name-windows.log" >&2 || true
    screencapture -x "$out/$name-screen.png" || true
    pkill -x ouro-md || true
    return 1
  fi
  sleep 4
  screencapture -x -o -l "$id" "$out/$name-window.png"
  screencapture -x "$out/$name-screen.png"
  echo "captured $name (window $id)"
  pkill -x ouro-md || true
  sleep 1
}

failed=0
capture light quartz Light || failed=1
capture dark graphite Dark || failed=1
exit "$failed"
