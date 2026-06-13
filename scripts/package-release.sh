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
#     --repo ourostack/ouro-md --title "Ouro MD <version>" --notes "…"
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM keeps a bare-repo dependency cache; some machines restrict bare repos.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

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

echo "==> Archiving $APP -> $archive_path"
ditto -c -k --keepParent "$APP" "$archive_path"

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
echo "    --repo ourostack/ouro-md --title \"Ouro MD ${version}\" --notes \"…\""
