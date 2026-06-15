#!/usr/bin/env bash
#
# Packages a release artifact for Ouro MD: builds the app, zips it, and writes a
# manifest.json (sha256 + byte count + bundle identity + version) alongside it.
# Both files get attached to a GitHub release; the one-line installer
# (web/ouro-md-install.sh) and any in-app auto-updater verify the download
# against the manifest before installing.
#
#   ./scripts/package-release.sh            -> dist/Ouro-MD-<version>.{zip,manifest.json}
#
# After running, publish them with:
#   gh release create v<version> dist/Ouro-MD-<version>.zip dist/Ouro-MD-<version>.manifest.json \
#     --repo ourostack/ouro-md --target "$(git rev-parse HEAD)" \
#     --title "Ouro MD <version>" --notes "…"
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM keeps a bare-repo dependency cache; some machines restrict bare repos.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: release packages require a clean git worktree" >&2
  exit 1
fi

POSTHOG_KEY="${OURO_MD_POSTHOG_KEY:-${VITE_POSTHOG_KEY:-}}"
POSTHOG_DISABLED="${OURO_MD_TELEMETRY_DISABLED:-${VITE_POSTHOG_DISABLED:-}}"
POSTHOG_DISABLED_NORMALIZED="$(printf '%s' "${POSTHOG_DISABLED}" | tr '[:upper:]' '[:lower:]')"
ALLOW_UNCONFIGURED_TELEMETRY="${OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY:-}"

case "${POSTHOG_DISABLED_NORMALIZED}" in
  1|true|yes|on)
    POSTHOG_KEY=""
    ;;
esac

if [[ -z "${POSTHOG_KEY}" && "${ALLOW_UNCONFIGURED_TELEMETRY}" != "1" ]]; then
  echo "error: release packages require OURO_MD_POSTHOG_KEY or VITE_POSTHOG_KEY" >&2
  echo "       set OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY=1 only for non-release dry runs" >&2
  exit 1
fi

./make-app.sh

APP="OuroMD.app"
INFO="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO"; }

version="$(plist CFBundleShortVersionString)"
build="$(plist CFBundleVersion)"
bundle_id="$(plist CFBundleIdentifier)"
git_sha="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

OUT_DIR="dist"
archive_name="Ouro-MD-${version}.zip"
manifest_name="Ouro-MD-${version}.manifest.json"
archive_path="$OUT_DIR/$archive_name"
manifest_path="$OUT_DIR/$manifest_name"

mkdir -p "$OUT_DIR"
rm -f "$archive_path" "$manifest_path"

# Ship the bundle under its branded, spaced name ("Ouro MD.app") so a release
# install matches the from-source install (/Applications/Ouro MD.app) and the
# `md` alias — no second, differently-named copy.
stage="$OUT_DIR/.stage"
rm -rf "$stage"
mkdir -p "$stage"
ditto "$APP" "$stage/Ouro MD.app"

echo "==> Archiving Ouro MD.app -> $archive_path"
ditto -c -k --keepParent "$stage/Ouro MD.app" "$archive_path"
rm -rf "$stage"

sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
bytes="$(stat -f %z "$archive_path")"

cat > "$manifest_path" <<JSON
{
  "appName": "Ouro MD",
  "bundleIdentifier": "${bundle_id}",
  "version": "${version}",
  "build": "${build}",
  "gitSha": "${git_sha}",
  "archive": "${archive_name}",
  "sha256": "${sha256}",
  "bytes": ${bytes},
  "createdAt": "${created_at}"
}
JSON

echo "==> Wrote ${manifest_path}"
echo "    version ${version} (build ${build}) · ${bytes} bytes · sha256 ${sha256}"
echo
echo "Publish with:"
echo "  gh release create v${version} \"${archive_path}\" \"${manifest_path}\" \\"
echo "    --repo ourostack/ouro-md --target \"$(git rev-parse HEAD)\" \\"
echo "    --title \"Ouro MD ${version}\" --notes \"…\""
