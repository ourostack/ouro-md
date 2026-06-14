#!/usr/bin/env bash
#
# Regenerates the Ouro MD app icon from scripts/make-icon.swift:
#   Resources/AppIcon.png  (1024×1024 master)
#   Resources/AppIcon.icns (all dock/Finder sizes)
#
# See Resources/icon-spec.md for the design. Reproducible: edit make-icon.swift,
# re-run this, view the result, commit.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="Resources/AppIcon.png"
ICNS="Resources/AppIcon.icns"

echo "==> Rendering master ${MASTER}…"
swift scripts/make-icon.swift "$MASTER"

echo "==> Building ${ICNS}…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:16" "16:32@2x" "32:32" "32:64@2x" "128:128" "128:256@2x" "256:256" "256:512@2x" "512:512" "512:1024@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" "$MASTER" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$(dirname "$ICONSET")"

echo "==> Done:"
echo "    $MASTER  ($(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/{print $2}')px)"
echo "    $ICNS    ($(du -h "$ICNS" | awk '{print $1}'))"
