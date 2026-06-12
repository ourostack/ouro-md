#!/usr/bin/env bash
#
# Builds Ouro MD and installs it to /Applications.
#
#   ./install.sh            build + install
#   ./install.sh --update   git pull first, then build + install
#
# Where it lives:   /Applications/Ouro MD.app
# How to launch:    open -a "Ouro MD"   (or the `md` shell alias, or double-click)
# How to update:    ./install.sh --update     (re-run any time to get the latest)
#
# Note: the app is not yet Developer-ID signed/notarized, so it's installed with
# the quarantine flag cleared and re-registered with Launch Services. Once a
# signing identity exists, this becomes a signed + notarized build (and Sparkle
# auto-update can replace the manual `--update` step).
set -euo pipefail
cd "$(dirname "$0")"

# SwiftPM keeps a bare-repo dependency cache. Some machines restrict bare repos
# (git's safe.bareRepository=explicit); permit it for this build only. Harmless
# where the restriction isn't set.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

if [[ "${1:-}" == "--update" ]]; then
  echo "==> Updating source…"
  git pull --ff-only
fi

./make-app.sh

DEST="/Applications/Ouro MD.app"
echo "==> Installing to ${DEST}…"
rm -rf "$DEST"
cp -R "OuroMD.app" "$DEST"

# Clear quarantine + register with Launch Services so the icon, name, and
# `open -a "Ouro MD"` resolve immediately.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$DEST" 2>/dev/null || true

echo "==> Installed: ${DEST}"
echo "    Launch:  open -a \"Ouro MD\"   ·   or:  md <file.md>   ·   or double-click in Finder"
