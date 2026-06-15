#!/usr/bin/env bash
#
# Ouro MD — one-line installer.
#
#   curl -fsSL https://ouro.bot/ouro-md-install.sh | bash
#
# Direct GitHub fallback:
#   curl -fsSL https://raw.githubusercontent.com/ourostack/ouro-md/main/web/ouro-md-install.sh | bash
#
# Self-contained: needs only tools present on a stock macOS (curl, ditto,
# shasum). No git checkout, no GitHub CLI, no jq/python. Downloads the latest
# published release, verifies its sha256 against the release manifest, installs
# the app, clears the download quarantine, and opens it.
#
# Env overrides:
#   OURO_MD_REPO         GitHub owner/repo        (default: ourostack/ouro-md)
#   OURO_MD_INSTALL_DIR  install destination dir  (default: /Applications, falling
#                                                  back to ~/Applications)
#   OURO_MD_NO_OPEN=1    don't open the app after installing
set -euo pipefail

REPO="${OURO_MD_REPO:-ourostack/ouro-md}"
API="https://api.github.com/repos/${REPO}/releases?per_page=1"

say()  { printf '\033[1;36m▸\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Ouro MD is macOS-only (this is $(uname -s))."
for tool in curl shasum ditto; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

# Choose an install dir we can actually write to (no sudo prompt).
INSTALL_DIR="${OURO_MD_INSTALL_DIR:-/Applications}"
if [ -z "${OURO_MD_INSTALL_DIR:-}" ] && ! { [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; }; then
  INSTALL_DIR="$HOME/Applications"
fi

say "Finding the latest Ouro MD release…"
rel="$(curl -fsSL "$API")" || die "couldn't reach the GitHub release API."

# Pull the asset URLs out of the (newest) release object without jq.
zip_url="$(printf '%s' "$rel" | grep -o '"browser_download_url": *"[^"]*\.zip"' | sed 's/.*"\(https[^"]*\)"/\1/' | head -1)"
manifest_url="$(printf '%s' "$rel" | grep -o '"browser_download_url": *"[^"]*\.manifest\.json"' | sed 's/.*"\(https[^"]*\)"/\1/' | head -1)"
[ -n "$zip_url" ] || die "no .zip asset on the latest release."
[ -n "$manifest_url" ] || die "no .manifest.json asset on the latest release."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" "${new_dest:-}"' EXIT
zip_path="$tmp/$(basename "$zip_url")"

say "Downloading $(basename "$zip_url")…"
curl -fsSL "$zip_url" -o "$zip_path" || die "download failed."
manifest="$(curl -fsSL "$manifest_url")" || die "couldn't fetch the release manifest."

# Verify the archive against the sha256 recorded in the manifest.
expected="$(printf '%s' "$manifest" | grep -o '"sha256": *"[0-9a-f]*"' | sed 's/.*"\([0-9a-f]*\)"/\1/' | head -1)"
[ -n "$expected" ] || die "manifest has no sha256 to verify against."
actual="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
[ "$actual" = "$expected" ] || die "checksum mismatch (expected $expected, got $actual). Aborting."
say "Checksum verified."

say "Extracting…"
ditto -x -k "$zip_path" "$tmp/extracted"
app_src="$(find "$tmp/extracted" -maxdepth 2 -name '*.app' -type d | head -1)"
[ -n "$app_src" ] || die "no .app found inside the archive."
app_name="$(basename "$app_src")"

mkdir -p "$INSTALL_DIR"
dest="$INSTALL_DIR/$app_name"
ver="$(printf '%s' "$manifest" | grep -o '"version": *"[^"]*"' | sed 's/.*"\([^"]*\)"/\1/' | head -1)"
bundle_id="$(printf '%s' "$manifest" | grep -o '"bundleIdentifier": *"[^"]*"' | sed 's/.*"\([^"]*\)"/\1/' | head -1)"
new_dest="${dest}.update-new.$$"
bak_dest="${dest}.update-bak.$$"
rm -rf "$new_dest" "$bak_dest"

say "Preparing install…"
ditto "$app_src" "$new_dest" || die "couldn't copy the new app into a staging location."
xattr -cr "$new_dest" 2>/dev/null || true
info="$new_dest/Contents/Info.plist"
[ -f "$info" ] || die "staged app is missing Info.plist."
staged_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info" 2>/dev/null || true)"
[ -z "$ver" ] || [ "$staged_ver" = "$ver" ] || die "staged app version $staged_ver did not match manifest version $ver."
if [ -n "$bundle_id" ]; then
  staged_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info" 2>/dev/null || true)"
  [ "$staged_bundle_id" = "$bundle_id" ] || die "staged app bundle id $staged_bundle_id did not match manifest bundle id $bundle_id."
fi
/usr/bin/codesign --verify --deep --strict "$new_dest" >/dev/null 2>&1 || die "staged app failed code-signature verification."

if [ -d "$dest" ]; then
  say "Replacing existing install at $dest"
  mv "$dest" "$bak_dest" || die "couldn't move the existing app aside."
  if mv "$new_dest" "$dest"; then
    rm -rf "$bak_dest"
  else
    mv "$bak_dest" "$dest" 2>/dev/null || true
    die "couldn't move the new app into place; restored the previous install."
  fi
else
  mv "$new_dest" "$dest" || die "couldn't move the new app into place."
fi

# The download set the com.apple.quarantine xattr; the build is ad-hoc-signed
# (not yet notarized), so strip it to avoid the Gatekeeper "unidentified
# developer" / "damaged" prompt. lsregister refresh keeps Launch Services tidy.
xattr -cr "$dest" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$dest" >/dev/null 2>&1 || true

say "Installed ${app_name%.app} ${ver:-} → $dest"

# Wire up the `md` shell alias so `md file.md` opens the editor. Idempotent and
# conservative: only touches a shell rc that exists, never overwrites an existing
# `md` alias (yours or ours). Opt out with OURO_MD_NO_ALIAS=1.
alias_line="alias md='open -a \"${app_name%.app}\"'"
if [ "${OURO_MD_NO_ALIAS:-}" = "1" ]; then
  :
else
  case "${SHELL##*/}" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)    rc="$HOME/.zshrc" ;;   # macOS default shell is zsh
  esac
  if [ -f "$rc" ] && grep -qE '^[[:space:]]*alias[[:space:]]+md=' "$rc"; then
    if grep -qF "$alias_line" "$rc"; then
      say "Shell alias 'md' already set in ${rc/#$HOME/~}."
    else
      warn "An 'md' alias already exists in ${rc/#$HOME/~}; left it untouched."
    fi
  else
    [ -f "$rc" ] || : > "$rc"
    printf '\n# Open markdown files in %s:  md <file>\n%s\n' "${app_name%.app}" "$alias_line" >> "$rc"
    say "Added 'md' shell alias to ${rc/#$HOME/~} — run:  source ${rc/#$HOME/~}   (or open a new terminal)"
  fi
fi

if [ "${OURO_MD_NO_OPEN:-}" != "1" ]; then
  open "$dest" || warn "couldn't auto-open; launch it from $INSTALL_DIR."
fi

cat <<'NEXT'

Next:
  • Open a markdown file:  md some-file.md   (after opening a new terminal)
  • Or:                    open -a "Ouro MD" some-file.md
  • Or just double-click any .md in Finder.
NEXT
