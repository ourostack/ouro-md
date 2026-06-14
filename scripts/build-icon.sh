#!/usr/bin/env bash
#
# Builds the Ouro MD app icon from the editable vector source:
#   Resources/AppIcon.svg   (source of truth — edit this, e.g. in Sketch)
#     ↓ rasterize (WebKit; qlmanage can't be trusted with rx/filters)
#   Resources/AppIcon.png   (1024×1024 master)
#     ↓ iconset
#   Resources/AppIcon.icns  (all dock/Finder sizes)
#
# See Resources/icon-spec.md. Reproducible: edit the SVG, re-run this, view.
set -euo pipefail
cd "$(dirname "$0")/.."

SVG="Resources/AppIcon.svg"
MASTER="Resources/AppIcon.png"
ICNS="Resources/AppIcon.icns"

echo "==> Rasterizing ${SVG} → ${MASTER} (1024px, WebKit)…"
swift scripts/rasterize-svg.swift "$SVG" "$MASTER" 1024

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
echo "    $SVG    (editable vector — source of truth)"
echo "    $MASTER  ($(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/{print $2}')px)"
echo "    $ICNS    ($(du -h "$ICNS" | awk '{print $1}'))"
