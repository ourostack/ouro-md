#!/usr/bin/env bash
#
# Verifies the public one-line installer URL itself, not just the repository
# copy. Release verification already checks GitHub release assets; this closes
# the gap where the advertised curl URL could drift or serve stale bytes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

url="${OURO_MD_INSTALLER_URL:-https://ouro.bot/ouro-md-install.sh}"
expected_version="${OURO_MD_EXPECT_VERSION:-$(./scripts/verify-release-version.sh --print)}"
attempts="${OURO_MD_INSTALLER_ATTEMPTS:-12}"
sleep_seconds="${OURO_MD_INSTALLER_RETRY_SECONDS:-5}"

fail() {
  echo "error: $*" >&2
  exit 1
}

tmp="$(mktemp -d /tmp/ouro-md-hosted-installer.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

installer="$tmp/ouro-md-install.sh"
installed=""
for attempt in $(seq 1 "$attempts"); do
  echo "==> fetching hosted installer ($attempt/$attempts): $url"
  if curl -fsSL "$url" -o "$installer"; then
    chmod +x "$installer"
    if bash -n "$installer" && head -1 "$installer" | grep -q '^#!'; then
      install_dir="$tmp/install-$attempt"
      mkdir -p "$install_dir"
      if OURO_MD_INSTALL_DIR="$install_dir" OURO_MD_NO_OPEN=1 OURO_MD_NO_ALIAS=1 bash "$installer"; then
        candidate="$install_dir/Ouro MD.app"
        if [[ -d "$candidate" ]]; then
          version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate/Contents/Info.plist")"
          if [[ "$version" == "$expected_version" ]]; then
            installed="$candidate"
            break
          fi
          echo "hosted installer installed $version, expected $expected_version" >&2
        fi
      fi
    fi
  fi
  sleep "$sleep_seconds"
done

[[ -n "$installed" ]] || fail "hosted installer did not install Ouro MD $expected_version"
/usr/bin/codesign --verify --deep --strict "$installed"
./scripts/release-policy.sh scan "$installed"

echo "hosted installer verified: $url -> $expected_version"
