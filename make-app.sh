#!/usr/bin/env bash
#
# Builds an unsigned (ad-hoc signed) OuroMD.app bundle from the SwiftPM build.
# Note: this app is not yet Developer-ID signed or notarized, so first launch
# needs right-click -> Open (or `xattr -dr com.apple.quarantine OuroMD.app`).
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="OuroMD"
APP="${APP_NAME}.app"
CONFIG="release"
BIN_NAME="ouro-md"
BUNDLE_ID="bot.ouro.md"
OURO_MD_DISTRIBUTION_CHANNEL="${OURO_MD_DISTRIBUTION_CHANNEL:-developer-id}"
# Single-sourced from OuroMDRelease.swift (the version the app reports at
# runtime); never hardcode it here or the packaged Info.plist can silently drift
# from the runtime version on a release bump. verify-release-version.sh enforces
# that this stays a derivation.
source scripts/lib/app-version.sh
VERSION="$(ouro_md_source_version)"
[[ -n "${VERSION}" ]] || { echo "error: could not read version from Sources/OuroMDCore/OuroMDRelease.swift" >&2; exit 1; }
GIT_SHA="${OURO_MD_GIT_SHA:-$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)}"
POSTHOG_KEY="${OURO_MD_POSTHOG_KEY:-${VITE_POSTHOG_KEY:-}}"
POSTHOG_HOST="${OURO_MD_POSTHOG_HOST:-${VITE_POSTHOG_HOST:-https://us.i.posthog.com}}"
POSTHOG_DISABLED="${OURO_MD_TELEMETRY_DISABLED:-${VITE_POSTHOG_DISABLED:-}}"
POSTHOG_DISABLED_NORMALIZED="$(printf '%s' "${POSTHOG_DISABLED}" | tr '[:upper:]' '[:lower:]')"

case "${POSTHOG_DISABLED_NORMALIZED}" in
  1|true|yes|on)
    POSTHOG_KEY=""
    ;;
esac

case "${OURO_MD_DISTRIBUTION_CHANNEL}" in
  developer-id|app-store|local) ;;
  *)
    echo "error: OURO_MD_DISTRIBUTION_CHANNEL must be developer-id, app-store, or local" >&2
    exit 1
    ;;
esac

APP_CATEGORY="public.app-category.productivity"
if [[ "${OURO_MD_DISTRIBUTION_CHANNEL}" == "app-store" ]]; then
  APP_CATEGORY="public.app-category.developer-tools"
fi

echo "==> Building (${CONFIG})…"
swift build -c "${CONFIG}"

BIN_DIR=".build/${CONFIG}"
RES_BUNDLE="${BIN_DIR}/ouro-md_OuroMD.bundle"

if [[ ! -d "${RES_BUNDLE}" ]]; then
  echo "error: resource bundle not found at ${RES_BUNDLE}" >&2
  exit 1
fi

echo "==> Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_DIR}/${BIN_NAME}" "${APP}/Contents/MacOS/${BIN_NAME}"
cp -R "${RES_BUNDLE}" "${APP}/Contents/Resources/"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ouro MD</string>
    <key>CFBundleDisplayName</key><string>Ouro MD</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>OuroMDGitSHA</key><string>${GIT_SHA}</string>
    <key>OuroMDDistributionChannel</key><string>${OURO_MD_DISTRIBUTION_CHANNEL}</string>
    <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>${APP_CATEGORY}</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Ari Mendelow.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Markdown Document</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
                <string>mkd</string>
                <string>mdtext</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [[ -n "${POSTHOG_KEY}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :OuroMDPostHogKey string ${POSTHOG_KEY}" "${APP}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :OuroMDPostHogHost string ${POSTHOG_HOST}" "${APP}/Contents/Info.plist"
  echo "==> Telemetry: PostHog configured for ${POSTHOG_HOST}"
elif [[ -n "${POSTHOG_DISABLED}" ]]; then
  echo "==> Telemetry: disabled by OURO_MD_TELEMETRY_DISABLED/VITE_POSTHOG_DISABLED"
else
  echo "==> Telemetry: disabled (set OURO_MD_POSTHOG_KEY or VITE_POSTHOG_KEY to configure)"
fi

echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "${APP}" 2>/dev/null || echo "note: ad-hoc codesign skipped (continuing)"

echo "==> Done: ${PWD}/${APP}"
echo "    Launch with:  open ${APP}"
