#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-$ROOT/worker/tasks/2026-06-14-2236-doing-human-use-readiness}"
source "$ROOT/scripts/lib/app-version.sh"
SOURCE_VERSION="$(ouro_md_source_version "$ROOT")"
EXPECTED_LIVE_VERSION="${OURO_MD_EXPECTED_LIVE_VERSION:-$SOURCE_VERSION}"
UPDATE_FROM_VERSION="${OURO_MD_UPDATE_FROM_VERSION:-0.9.1}"
EXPECTED_LIVE_TAG="v$EXPECTED_LIVE_VERSION"
EXPECTED_LIVE_ZIP="Ouro-MD-$EXPECTED_LIVE_VERSION.zip"
EXPECTED_LIVE_MANIFEST="Ouro-MD-$EXPECTED_LIVE_VERSION.manifest.json"
mkdir -p "$ARTIFACT_DIR"

log() {
  printf '\n[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

run_logged() {
  local log_file="$1"
  shift
  log "RUN $*" | tee "$log_file"
  (cd "$ROOT" && "$@") >>"$log_file" 2>&1
  log "OK $*" | tee -a "$log_file"
}

terminate_app_pid() {
  local pid="$1"
  /usr/bin/swift -e "import AppKit; if let app = NSRunningApplication(processIdentifier: pid_t($pid)) { _ = app.terminate() }" || true
  for _ in $(seq 1 20); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  kill -9 "$pid" 2>/dev/null || true
}

make_large_doc() {
  local out="$1"
  local sections="$2"
  local rich="${3:-1}"
  : > "$out"
  {
    printf '# Synthetic Dogfood Stress Fixture\n\n'
    if [ "$rich" = "1" ]; then
      printf '> [!NOTE]\n> Alert body for render checks.\n\n'
      printf '| Column A | Column B | Column C |\n| --- | --- | --- |\n'
      printf '| one | two | three |\n\n'
      printf '$$E = mc^2$$\n\n'
      printf '[^stress]: Footnote body.\n\n'
      printf '```mermaid\ngraph TD; A-->B;\n```\n\n'
    fi
  } >> "$out"
  for i in $(seq 1 "$sections"); do
    {
      printf '## Section %05d\n\n' "$i"
      if [ "$rich" = "1" ]; then
        printf 'Paragraph %05d with **bold**, `inline code`, [a link](https://example.com), and a footnote reference[^stress].\n\n' "$i"
        printf -- '- [x] completed item %05d\n- [ ] open item %05d\n\n' "$i" "$i"
      else
        printf 'Paragraph %05d with **bold**, `inline code`, and enough plain text to exercise editor scale without table normalization.\n\n' "$i"
        printf -- '- completed item %05d\n- open item %05d\n\n' "$i" "$i"
      fi
      printf '```swift\nlet value%d = "%05d"\n```\n\n' "$i" "$i"
    } >> "$out"
  done
}

TMP_ROOT="$(mktemp -d /tmp/ouro-md-readiness.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

cd "$ROOT"

run_logged "$ARTIFACT_DIR/large-workspace.log" swift test --filter FolderBrowserTests/testLargeWorkspaceBudgetSkipsOversizedHiddenAndSymlinkedFiles

ROUNDTRIP_DOC="$ARTIFACT_DIR/large-roundtrip-fixture.md"
RENDER_DOC="$ARTIFACT_DIR/large-render-fixture.md"
VISUAL_DOC="$ARTIFACT_DIR/render-visual-fixture.md"
ROUNDTRIP_OUT="$ARTIFACT_DIR/large-doc-roundtrip.md"
make_large_doc "$ROUNDTRIP_DOC" 2500 0
make_large_doc "$RENDER_DOC" 18000 1
make_large_doc "$VISUAL_DOC" 200 1
{
  log "large-roundtrip-doc bytes=$(wc -c < "$ROUNDTRIP_DOC")"
  /usr/bin/time -p swift run ouro-md --roundtrip "$ROUNDTRIP_DOC" --out "$ROUNDTRIP_OUT"
  cmp "$ROUNDTRIP_DOC" "$ROUNDTRIP_OUT"
  log "large roundtrip cmp ok"
} > "$ARTIFACT_DIR/large-doc-roundtrip.log" 2>&1

RENDER_HTML="$ARTIFACT_DIR/render-fixture.html"
{
  log "large-render-doc bytes=$(wc -c < "$RENDER_DOC")"
  /usr/bin/time -p swift run ouro-md --render "$RENDER_DOC" --theme quartz > "$RENDER_HTML"
  test -s "$RENDER_HTML"
  grep -q 'Synthetic Dogfood Stress Fixture' "$RENDER_HTML"
  grep -q 'footnotes' "$RENDER_HTML"
  grep -q 'language-mermaid' "$RENDER_HTML"
  log "render html bytes=$(wc -c < "$RENDER_HTML")"
} > "$ARTIFACT_DIR/render-fixture.log" 2>&1

RENDER_PNG="$ARTIFACT_DIR/render-fixture.png"
{
  /usr/bin/time -p swift run ouro-md --shoot "$VISUAL_DOC" --out "$RENDER_PNG" --width 1000 --height 1300
  test -s "$RENDER_PNG"
  sips -g pixelWidth -g pixelHeight "$RENDER_PNG"
  PNG="$RENDER_PNG" /usr/bin/swift - <<'SWIFT'
import AppKit
let env = ProcessInfo.processInfo.environment
guard let path = env["PNG"],
      let image = NSImage(contentsOfFile: path),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else {
    FileHandle.standardError.write(Data("png_content_check=unreadable\n".utf8))
    exit(1)
}
let width = bitmap.pixelsWide
let height = bitmap.pixelsHigh
let xStep = max(1, width / 20)
let yStep = max(1, height / 20)
var samples = 0
var nonWhite = 0
for y in stride(from: 0, to: height, by: yStep) {
    for x in stride(from: 0, to: width, by: xStep) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        samples += 1
        let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
        if color.alphaComponent > 0.1 && brightness < 0.98 { nonWhite += 1 }
    }
}
guard samples > 0, nonWhite >= max(3, samples / 25) else {
    FileHandle.standardError.write(Data("png_content_check=too_blank nonwhite=\(nonWhite) samples=\(samples)\n".utf8))
    exit(1)
}
print("png_content_check=ok nonwhite=\(nonWhite) samples=\(samples)")
SWIFT
} > "$ARTIFACT_DIR/render-fixture-screenshot.log" 2>&1

{
  swift run ouro-md --undotest
  swift run ouro-md --wraptest
  swift run ouro-md --renderprobe
  swift test --filter AppModelReloadTests
} > "$ARTIFACT_DIR/editor-lifecycle.log" 2>&1

APP_PATH="$ROOT/OuroMD.app"
{
  ./make-app.sh
  FIRST_HOME="$TMP_ROOT/first-home"
  FIRST_TMP="$TMP_ROOT/first-tmp"
  mkdir -p "$FIRST_HOME/Library/Preferences" "$FIRST_TMP"
  HOME="$FIRST_HOME" \
    CFFIXED_USER_HOME="$FIRST_HOME" \
    CFPREFERENCES_AVOID_DAEMON=1 \
    TMPDIR="$FIRST_TMP/" \
    OURO_MD_TELEMETRY_DISABLED=1 \
    "$APP_PATH/Contents/MacOS/ouro-md" &
  APP_PID=$!
  sleep 5
  HOME="$FIRST_HOME" CFFIXED_USER_HOME="$FIRST_HOME" CFPREFERENCES_AVOID_DAEMON=1 defaults read bot.ouro.md
  terminate_app_pid "$APP_PID"
  wait "$APP_PID" || true
} > "$ARTIFACT_DIR/first-run.log" 2>&1

{
  rg -n "accessibility(Label|Identifier|Value|Hint)|help\\(" "$ROOT/Sources/OuroMD"
  AX_HOME="$TMP_ROOT/ax-home"
  AX_TMP="$TMP_ROOT/ax-tmp"
  mkdir -p "$AX_HOME/Library/Preferences" "$AX_TMP"
  HOME="$AX_HOME" \
    CFFIXED_USER_HOME="$AX_HOME" \
    CFPREFERENCES_AVOID_DAEMON=1 \
    TMPDIR="$AX_TMP/" \
    OURO_MD_TELEMETRY_DISABLED=1 \
    "$APP_PATH/Contents/MacOS/ouro-md" &
  APP_PID=$!
  sleep 4
  AX_OUT="$TMP_ROOT/ax-window.txt"
  osascript -e 'tell application "System Events" to tell first process whose unix id is '"$APP_PID"' to get role of window 1' > "$AX_OUT"
  cat "$AX_OUT"
  grep -q 'AXWindow' "$AX_OUT"
  terminate_app_pid "$APP_PID"
  wait "$APP_PID" || true
} > "$ARTIFACT_DIR/accessibility-ax.log" 2>&1

{
  LIVE_INSTALL="$TMP_ROOT/live-install"
  mkdir -p "$LIVE_INSTALL"
  curl -fsSL https://ouro.bot/ouro-md-install.sh | OURO_MD_INSTALL_DIR="$LIVE_INSTALL" OURO_MD_NO_OPEN=1 bash
  curl -fsSL https://ouro.bot/ouro-md-install.sh | OURO_MD_INSTALL_DIR="$LIVE_INSTALL" OURO_MD_NO_OPEN=1 bash
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LIVE_INSTALL/Ouro MD.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIVE_INSTALL/Ouro MD.app/Contents/Info.plist"
  /usr/bin/codesign --verify --deep --strict "$LIVE_INSTALL/Ouro MD.app"
} > "$ARTIFACT_DIR/live-installer-$EXPECTED_LIVE_TAG.log" 2>&1

{
  CLONE="$TMP_ROOT/clean-clone"
  git clone --depth 1 "$ROOT" "$CLONE"
  cd "$CLONE"
  swift test
  VERSION="$SOURCE_VERSION"
  OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY=1 ./scripts/package-release.sh
  test -s "dist/Ouro-MD-$VERSION.zip"
  test -s "dist/Ouro-MD-$VERSION.manifest.json"
  APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' OuroMD.app/Contents/Info.plist)
  printf 'version=%s\napp_version=%s\n' "$VERSION" "$APP_VERSION"
  test "$APP_VERSION" = "$VERSION"
  /usr/bin/codesign --verify --deep --strict OuroMD.app
} > "$ARTIFACT_DIR/clean-clone-release.log" 2>&1

{
  curl -fsSL -H 'Accept: application/vnd.github+json' -H "User-Agent: OuroMD/$UPDATE_FROM_VERSION" \
    'https://api.github.com/repos/ourostack/ouro-md/releases?per_page=3' > "$TMP_ROOT/releases.json"
  jq -e --arg tag "$EXPECTED_LIVE_TAG" '.[0].tag_name == $tag' "$TMP_ROOT/releases.json"
  jq -e '.[0].draft == false and .[0].prerelease == false' "$TMP_ROOT/releases.json"
  jq -e --arg zip "$EXPECTED_LIVE_ZIP" --arg manifest "$EXPECTED_LIVE_MANIFEST" \
    '([.[0].assets[].name] | index($zip) and index($manifest))' "$TMP_ROOT/releases.json"
  curl -fsSL -o "$TMP_ROOT/$EXPECTED_LIVE_MANIFEST" \
    "https://github.com/ourostack/ouro-md/releases/download/$EXPECTED_LIVE_TAG/$EXPECTED_LIVE_MANIFEST"
  jq -e --arg version "$EXPECTED_LIVE_VERSION" \
    '.version == $version and .bundleIdentifier == "bot.ouro.md"' "$TMP_ROOT/$EXPECTED_LIVE_MANIFEST"
  swift test --filter ReleaseUpdateTests
  swift test --filter OuroMDUpdateInstallerTests
  swift test --filter OuroMDUpdateCoordinatorTests
  printf 'deterministic_update_gate=ok\n'
  printf 'expected_live_version=%s\n' "$EXPECTED_LIVE_VERSION"
  printf 'update_from_version=%s\n' "$UPDATE_FROM_VERSION"
  printf 'note=repeatable stress uses release feed plus updater unit gates\n'
} > "$ARTIFACT_DIR/in-app-update-v${UPDATE_FROM_VERSION}-to-v${EXPECTED_LIVE_VERSION}.log" 2>&1

log "readiness stress complete" | tee "$ARTIFACT_DIR/readiness-stress-complete.log"
