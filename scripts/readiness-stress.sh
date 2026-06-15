#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-$ROOT/worker/tasks/2026-06-14-2236-doing-human-use-readiness}"
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
ROUNDTRIP_OUT="$ARTIFACT_DIR/large-doc-roundtrip.md"
make_large_doc "$ROUNDTRIP_DOC" 2500 0
make_large_doc "$RENDER_DOC" 18000 1
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
  /usr/bin/time -p swift run ouro-md --shoot "$ROUNDTRIP_DOC" --out "$RENDER_PNG" --width 1000 --height 1300
  test -s "$RENDER_PNG"
  sips -g pixelWidth -g pixelHeight "$RENDER_PNG"
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
  /usr/bin/open -W -n -F -g \
    --env "HOME=$FIRST_HOME" \
    --env "CFFIXED_USER_HOME=$FIRST_HOME" \
    --env "TMPDIR=$FIRST_TMP/" \
    --env "OURO_MD_TELEMETRY_DISABLED=1" \
    "$APP_PATH" &
  OPEN_PID=$!
  APP_PID=""
  for _ in $(seq 1 80); do
    APP_PID="$(ps -axo pid=,args= | awk -v needle="$APP_PATH/Contents/MacOS/ouro-md" 'index($0, needle) {print $1; exit}' || true)"
    [ -n "$APP_PID" ] && break
    sleep 0.25
  done
  test -n "$APP_PID"
  sleep 5
  HOME="$FIRST_HOME" CFFIXED_USER_HOME="$FIRST_HOME" defaults read org.ourostack.ouro-md
  /usr/bin/swift -e "import AppKit; if let app = NSRunningApplication(processIdentifier: pid_t($APP_PID)) { _ = app.terminate() }"
  wait "$OPEN_PID" || true
} > "$ARTIFACT_DIR/first-run.log" 2>&1

{
  rg -n "accessibility(Label|Identifier|Value|Hint)|help\\(" "$ROOT/Sources/OuroMD" || true
  AX_HOME="$TMP_ROOT/ax-home"
  AX_TMP="$TMP_ROOT/ax-tmp"
  mkdir -p "$AX_HOME/Library/Preferences" "$AX_TMP"
  /usr/bin/open -W -n -F -g \
    --env "HOME=$AX_HOME" \
    --env "CFFIXED_USER_HOME=$AX_HOME" \
    --env "TMPDIR=$AX_TMP/" \
    --env "OURO_MD_TELEMETRY_DISABLED=1" \
    "$APP_PATH" &
  OPEN_PID=$!
  APP_PID=""
  for _ in $(seq 1 80); do
    APP_PID="$(ps -axo pid=,args= | awk -v needle="$APP_PATH/Contents/MacOS/ouro-md" 'index($0, needle) {print $1; exit}' || true)"
    [ -n "$APP_PID" ] && break
    sleep 0.25
  done
  test -n "$APP_PID"
  sleep 4
  osascript -e 'tell application "System Events" to tell first process whose unix id is '"$APP_PID"' to get {name, role, description} of UI elements of window 1' || true
  /usr/bin/swift -e "import AppKit; if let app = NSRunningApplication(processIdentifier: pid_t($APP_PID)) { _ = app.terminate() }"
  wait "$OPEN_PID" || true
} > "$ARTIFACT_DIR/accessibility-ax.log" 2>&1

{
  LIVE_INSTALL="$TMP_ROOT/live-install"
  mkdir -p "$LIVE_INSTALL"
  curl -fsSL https://ouro.bot/ouro-md-install.sh | OURO_MD_INSTALL_DIR="$LIVE_INSTALL" OURO_MD_NO_OPEN=1 bash
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LIVE_INSTALL/Ouro MD.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LIVE_INSTALL/Ouro MD.app/Contents/Info.plist"
  /usr/bin/codesign --verify --deep --strict "$LIVE_INSTALL/Ouro MD.app"
} > "$ARTIFACT_DIR/live-installer-v0.9.2.log" 2>&1

{
  CLONE="$TMP_ROOT/clean-clone"
  git clone --depth 1 "$ROOT" "$CLONE"
  cd "$CLONE"
  swift test
  VERSION="$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/OuroMD/OuroMDRelease.swift)"
  OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY=1 ./scripts/package-release.sh
  test -s "dist/Ouro-MD-$VERSION.zip"
  test -s "dist/Ouro-MD-$VERSION.manifest.json"
  APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' OuroMD.app/Contents/Info.plist)
  printf 'version=%s\napp_version=%s\n' "$VERSION" "$APP_VERSION"
  test "$APP_VERSION" = "$VERSION"
  /usr/bin/codesign --verify --deep --strict OuroMD.app
} > "$ARTIFACT_DIR/clean-clone-release.log" 2>&1

{
  UPDATE_ROOT="$TMP_ROOT/update-smoke"
  UPDATE_HOME="$UPDATE_ROOT/home"
  UPDATE_TMP="$UPDATE_ROOT/tmp"
  mkdir -p "$UPDATE_HOME/Library/Preferences" "$UPDATE_TMP"
  curl -fsSL -o "$UPDATE_ROOT/Ouro-MD-0.9.1.zip" https://github.com/ourostack/ouro-md/releases/download/v0.9.1/Ouro-MD-0.9.1.zip
  ditto -x -k "$UPDATE_ROOT/Ouro-MD-0.9.1.zip" "$UPDATE_ROOT"
  OLD_APP="$UPDATE_ROOT/Ouro MD.app"
  START_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD_APP/Contents/Info.plist")
  /usr/bin/open -W -n -F -g \
    --env "HOME=$UPDATE_HOME" \
    --env "CFFIXED_USER_HOME=$UPDATE_HOME" \
    --env "TMPDIR=$UPDATE_TMP/" \
    --env "OURO_MD_TELEMETRY_DISABLED=1" \
    "$OLD_APP" &
  OPEN_PID=$!
  APP_PID=""
  for _ in $(seq 1 80); do
    APP_PID="$(ps -axo pid=,args= | awk -v needle="$OLD_APP/Contents/MacOS/ouro-md" 'index($0, needle) {print $1; exit}' || true)"
    [ -n "$APP_PID" ] && break
    sleep 0.25
  done
  test -n "$APP_PID"
  STAGED=""
  FINAL_VERSION="$START_VERSION"
  for _ in $(seq 1 240); do
    FINAL_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD_APP/Contents/Info.plist")
    [ "$FINAL_VERSION" = "0.9.2" ] && break
    while IFS= read -r -d "" PLIST; do
      VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)
      if [ "$VERSION" = "0.9.2" ]; then
        STAGED="$PLIST"
        break
      fi
    done < <(find "$UPDATE_TMP" -path "*/extract/Ouro MD.app/Contents/Info.plist" -print0 2>/dev/null)
    [ -n "$STAGED" ] && break
    sleep 0.5
  done
  printf 'staged=%s\n' "${STAGED:-not-observed}"
  /usr/bin/swift -e "import AppKit; if let app = NSRunningApplication(processIdentifier: pid_t($APP_PID)) { _ = app.terminate() }" || true
  wait "$OPEN_PID" || true
  for _ in $(seq 1 180); do
    FINAL_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OLD_APP/Contents/Info.plist")
    [ "$FINAL_VERSION" = "0.9.2" ] && break
    sleep 0.5
  done
  printf 'start=%s\nfinal=%s\n' "$START_VERSION" "$FINAL_VERSION"
  test "$START_VERSION" = "0.9.1"
  test "$FINAL_VERSION" = "0.9.2"
  /usr/bin/codesign --verify --deep --strict "$OLD_APP"
} > "$ARTIFACT_DIR/in-app-update-v0.9.1-to-v0.9.2.log" 2>&1

log "readiness stress complete" | tee "$ARTIFACT_DIR/readiness-stress-complete.log"
