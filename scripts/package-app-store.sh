#!/usr/bin/env bash
#
# Builds and packages Ouro MD for Mac App Store upload.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="OuroMD.app"
OUT_DIR="dist/app-store"
ENTITLEMENTS="config/app-store-entitlements.plist"

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/package-app-store.sh [--readiness [--artifact PATH]] [--validate] [--upload]

Required env:
  OURO_APP_STORE_APP_IDENTITY        app signing identity
  OURO_APP_STORE_INSTALLER_IDENTITY  pkg signing identity

Optional env:
  OURO_APP_STORE_PROVISIONING_PROFILE  path to a Mac App Store provisioning profile
  APP_STORE_CONNECT_API_KEY_PATH        path to AuthKey_<key-id>.p8
  OURO_MD_APP_STORE_ENABLE_TELEMETRY=1  opt in to embedded telemetry for App Store builds

Validation/upload auth, choose one:
  APP_STORE_CONNECT_API_KEY_ID + APP_STORE_CONNECT_API_ISSUER_ID
  APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD

If the account has multiple providers, set APP_STORE_CONNECT_PROVIDER_PUBLIC_ID.
USAGE
}

validate=0
upload=0
readiness=0
readiness_artifact=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --readiness) readiness=1; shift ;;
    --artifact)
      [[ $# -ge 2 && -n "$2" ]] || { usage; exit 64; }
      readiness_artifact="$2"
      shift 2
      ;;
    --validate) validate=1; shift ;;
    --upload) upload=1; validate=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

if [[ -n "$readiness_artifact" && "$readiness" != "1" ]]; then
  usage
  exit 64
fi

have_all() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || return 1
  done
}

require_tooling() {
  [[ -f "$ENTITLEMENTS" ]] || fail "missing entitlements: $ENTITLEMENTS"
  command -v codesign >/dev/null 2>&1 || fail "codesign is required"
  command -v productbuild >/dev/null 2>&1 || fail "productbuild is required"
  command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
  xcrun altool --help >/dev/null 2>&1 || fail "xcrun altool is required"
}

require_identity_env() {
  local env_name="$1"
  local hint="$2"
  [[ -n "${!env_name:-}" ]] || fail "$env_name is required, for example: $hint"
}

require_app_store_identities() {
  APP_IDENTITY="${OURO_APP_STORE_APP_IDENTITY:-}"
  INSTALLER_IDENTITY="${OURO_APP_STORE_INSTALLER_IDENTITY:-}"
  require_identity_env OURO_APP_STORE_APP_IDENTITY '3rd Party Mac Developer Application: Ari Mendelow (743GT2AJ24)'
  require_identity_env OURO_APP_STORE_INSTALLER_IDENTITY '3rd Party Mac Developer Installer: Ari Mendelow (743GT2AJ24)'
  security find-identity -v -p codesigning | grep -Fq "$APP_IDENTITY" \
    || fail "app signing identity was not found in this keychain: $APP_IDENTITY"
  security find-identity -v | grep -Fq "$INSTALLER_IDENTITY" \
    || fail "installer signing identity was not found in this keychain: $INSTALLER_IDENTITY"
}

build_auth_args() {
  auth_args=()
  if have_all APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_API_ISSUER_ID; then
    auth_args=(--api-key "$APP_STORE_CONNECT_API_KEY_ID" --api-issuer "$APP_STORE_CONNECT_API_ISSUER_ID")
    if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
      [[ -f "$APP_STORE_CONNECT_API_KEY_PATH" ]] || fail "APP_STORE_CONNECT_API_KEY_PATH does not point to a file"
      auth_args+=(--p8-file-path "$APP_STORE_CONNECT_API_KEY_PATH")
    fi
  elif have_all APPLE_ID APPLE_APP_SPECIFIC_PASSWORD; then
    auth_args=(--username "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
  else
    auth_args=()
  fi
  if [[ -n "${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-}" ]]; then
    auth_args+=(--provider-public-id "$APP_STORE_CONNECT_PROVIDER_PUBLIC_ID")
  fi
}

run_adk_xcode() {
  ./scripts/apple-distribution-kit.sh xcode run --mode apply "$@"
}

print_readiness() {
  READINESS_ARTIFACT="$readiness_artifact" python3 <<'PY'
import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

ROOT = Path.cwd()
ARTIFACT = os.environ.get("READINESS_ARTIFACT", "")

def command_ok(args):
    try:
        return subprocess.run(
            args,
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode == 0
    except OSError:
        return False

def read_text(path):
    return (ROOT / path).read_text(encoding="utf-8")

def constant_from_source(path, pattern):
    match = re.search(pattern, read_text(path))
    return match.group(1) if match else ""

def shell_assignment(script_body, name):
    match = re.search(rf'^{re.escape(name)}="([^"]*)"', script_body, re.MULTILINE)
    return match.group(1) if match else ""

def app_store_category_from_make_app(script_body):
    match = re.search(
        r'if \[\[ "\$\{OURO_MD_DISTRIBUTION_CHANNEL\}" == "app-store" \]\]; then\s+APP_CATEGORY="([^"]+)"',
        script_body,
        re.MULTILINE,
    )
    return match.group(1) if match else ""

def manifest_category_to_plist(category):
    return {
        "DEVELOPER_TOOLS": "public.app-category.developer-tools",
        "PRODUCTIVITY": "public.app-category.productivity",
    }.get(category, category)

def command_environment(command):
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()
    env = []
    for part in parts:
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", part):
            env.append(part)
            continue
        break
    return env

def env_value(env, name):
    prefix = f"{name}="
    for item in env:
        if item.startswith(prefix):
            return item[len(prefix):]
    return ""

def package_script_build_environment(script_body):
    env = []
    if re.search(r"make_app_env=\(OURO_MD_DISTRIBUTION_CHANNEL=app-store\)", script_body):
        env.append("OURO_MD_DISTRIBUTION_CHANNEL=app-store")
    if re.search(r"make_app_env\+=\(OURO_MD_TELEMETRY_DISABLED=1\)", script_body):
        env.append("OURO_MD_TELEMETRY_DISABLED=1")
    return env

def app_store_allows_direct_updates(distribution_source):
    match = re.search(r"case \.appStore:\s*return (true|false)", distribution_source)
    if not match:
        return None
    return match.group(1) == "true"

def make_app_declares_non_exempt_encryption_false(script_body):
    compact = re.sub(r"\s+", "", script_body)
    return "<key>ITSAppUsesNonExemptEncryption</key><false/>" in compact

def make_app_honors_telemetry_disable(script_body):
    return (
        "OURO_MD_TELEMETRY_DISABLED" in script_body
        and "POSTHOG_DISABLED" in script_body
        and 'POSTHOG_KEY=""' in script_body
    )

def source_version():
    return constant_from_source("Sources/OuroMDCore/OuroMDRelease.swift", r'static let version = "([^"]+)"')

def source_bundle_id():
    return constant_from_source("Sources/OuroMDCore/OuroMDRelease.swift", r'static let bundleIdentifier = "([^"]+)"')

def manifest_channel():
    manifest = json.loads(read_text("distribution/apple-distribution.json"))
    for channel in manifest.get("channels", []):
        if channel.get("id") == "mac-app-store":
            return channel
    return {}

def identity_present(identity, codesigning_only=True):
    if not identity:
        return False
    args = ["security", "find-identity", "-v"]
    if codesigning_only:
        args.extend(["-p", "codesigning"])
    try:
        result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=False)
    except OSError:
        return False
    return identity in result.stdout

def git_output(args):
    result = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)
    return result.stdout if result.returncode == 0 else ""

def secret_scan():
    matches = []
    credential_name = re.compile(r"(^|/)(AuthKey_[A-Za-z0-9]+\.p8|[^/]+\.(p8|p12|mobileprovision|provisionprofile|cer))$")
    paths = git_output(["ls-files", "-c", "-o", "--exclude-standard"]).splitlines()
    for path in paths:
        if credential_name.search(path):
            matches.append("[redacted-signing-material-filename]")

    pem_pattern = re.compile(
        r"-----BEGIN (?:RSA |EC |OPENSSH |)?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH |)?PRIVATE KEY-----"
    )
    for path in paths:
        if path in {"scripts/package-app-store.sh"} or path.startswith("docs/") or path == "README.md":
            continue
        file_path = ROOT / path
        if not file_path.is_file() or file_path.stat().st_size > 1_000_000:
            continue
        try:
            body = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if pem_pattern.search(body):
            matches.append("[redacted-private-material-block]")
    return sorted(set(matches))

def blocker(code, message):
    blockers.append({"code": code, "message": message})

blockers = []
channel = manifest_channel()
store = channel.get("store", {})
make_app = read_text("make-app.sh")
package_script = read_text("scripts/package-app-store.sh")
distribution_source = read_text("Sources/OuroMD/OuroMDDistribution.swift")

swift_version = source_version()
manifest_version = store.get("version", "")
version_coherent = bool(swift_version and swift_version == manifest_version)

release_bundle_id = source_bundle_id()
manifest_app_bundle_id = json.loads(read_text("distribution/apple-distribution.json")).get("app", {}).get("bundleId", "")
manifest_channel_bundle_id = channel.get("bundleId", "")
build_script_bundle_id = shell_assignment(make_app, "BUNDLE_ID")
bundle_id_sources = [value for value in [
    release_bundle_id,
    manifest_app_bundle_id,
    manifest_channel_bundle_id,
    build_script_bundle_id,
] if value]
bundle_id_coherent = bool(bundle_id_sources) and len(set(bundle_id_sources)) == 1

manifest_build_env = command_environment(channel.get("buildCommand", ""))
package_build_env = package_script_build_environment(package_script)
manifest_distribution = channel.get("distribution", "")
build_command_channel = env_value(manifest_build_env, "OURO_MD_DISTRIBUTION_CHANNEL")
package_script_channel = env_value(package_build_env, "OURO_MD_DISTRIBUTION_CHANNEL")
distribution_channel_coherent = (
    manifest_distribution == "app-store"
    and build_command_channel == "app-store"
    and package_script_channel == "app-store"
)

manifest_category = manifest_category_to_plist(store.get("category", ""))
build_script_category = app_store_category_from_make_app(make_app)
category_coherent = bool(manifest_category and build_script_category and manifest_category == build_script_category)

direct_updates_allowed = app_store_allows_direct_updates(distribution_source)
encryption_claim_false = make_app_declares_non_exempt_encryption_false(make_app)
build_command_disables_telemetry = "OURO_MD_TELEMETRY_DISABLED=1" in manifest_build_env
package_disables_telemetry = "OURO_MD_TELEMETRY_DISABLED=1" in package_build_env
build_script_honors_telemetry_disable = make_app_honors_telemetry_disable(make_app)
telemetry_default_disabled = (
    build_command_disables_telemetry
    and package_disables_telemetry
    and build_script_honors_telemetry_disable
)

if not version_coherent:
    blocker("version-mismatch", "Source version and App Store manifest version differ.")
if not bundle_id_coherent:
    blocker("bundle-id-mismatch", "Bundle identifier sources disagree across release source, manifest, and build script.")
if not distribution_channel_coherent:
    blocker("distribution-channel-mismatch", "App Store manifest and package/build commands do not all select the app-store channel.")
if not category_coherent:
    blocker("app-category-mismatch", "App Store category sources disagree between metadata manifest and build script.")
if direct_updates_allowed is not False:
    blocker("direct-updates-not-disabled", "App Store distribution policy does not prove direct updates are disabled.")
if not encryption_claim_false:
    blocker("encryption-claim-missing", "Build script does not prove ITSAppUsesNonExemptEncryption=false for App Store packages.")
if not telemetry_default_disabled:
    blocker("telemetry-default-not-disabled", "App Store build/package sources do not prove telemetry is disabled by default.")

tool_checks = {
    "entitlements": (ROOT / "config/app-store-entitlements.plist").is_file(),
    "codesign": shutil.which("codesign") is not None,
    "productbuild": shutil.which("productbuild") is not None,
    "xcrun": shutil.which("xcrun") is not None,
    "altool": command_ok(["xcrun", "altool", "--help"]) if shutil.which("xcrun") else False,
}
for name, ok in tool_checks.items():
    if not ok:
        blocker(f"missing-{name}", f"Required App Store packaging tool is unavailable: {name}.")

app_identity_configured = bool(os.environ.get("OURO_APP_STORE_APP_IDENTITY", ""))
installer_identity_configured = bool(os.environ.get("OURO_APP_STORE_INSTALLER_IDENTITY", ""))
app_identity_found = identity_present(os.environ.get("OURO_APP_STORE_APP_IDENTITY", ""))
installer_identity_found = identity_present(os.environ.get("OURO_APP_STORE_INSTALLER_IDENTITY", ""), codesigning_only=False)
if not app_identity_configured:
    blocker("missing-app-signing-identity-env", "App signing identity is not configured on this host.")
elif not app_identity_found:
    blocker("app-signing-identity-not-found", "Configured app signing identity was not found on this host.")
if not installer_identity_configured:
    blocker("missing-installer-signing-identity-env", "Installer signing identity is not configured on this host.")
elif not installer_identity_found:
    blocker("installer-signing-identity-not-found", "Configured installer signing identity was not found on this host.")

profile_path = os.environ.get("OURO_APP_STORE_PROVISIONING_PROFILE", "")
if profile_path and not Path(profile_path).is_file():
    blocker("provisioning-profile-not-found", "Configured provisioning profile path does not exist.")

api_auth_configured = bool(os.environ.get("APP_STORE_CONNECT_API_KEY_ID") and os.environ.get("APP_STORE_CONNECT_API_ISSUER_ID"))
api_auth_file_ok = True
api_path = os.environ.get("APP_STORE_CONNECT_API_KEY_PATH", "")
if api_path:
    api_auth_file_ok = Path(api_path).is_file()
apple_auth_configured = bool(os.environ.get("APPLE_ID") and os.environ.get("APPLE_APP_SPECIFIC_PASSWORD"))
auth_configured = api_auth_configured or apple_auth_configured
if not auth_configured:
    blocker("missing-app-store-connect-auth", "App Store Connect validation/upload auth is not configured on this host.")
elif not api_auth_file_ok:
    blocker("auth-file-not-found", "Configured App Store Connect auth file path does not exist.")

forbidden_matches = secret_scan()
if forbidden_matches:
    blocker("secret-material-present", "Apple signing material appears to be tracked or unignored in the repository.")

readiness = {
    "schemaVersion": 1,
    "mode": "readiness",
    "app": {
        "bundleId": release_bundle_id,
        "sourceBundleId": release_bundle_id,
        "manifestBundleId": manifest_app_bundle_id,
        "channelBundleId": manifest_channel_bundle_id,
        "buildScriptBundleId": build_script_bundle_id,
        "bundleIdCoherent": bundle_id_coherent,
        "sourceVersion": swift_version,
        "manifestVersion": manifest_version,
        "versionCoherent": version_coherent,
    },
    "distribution": {
        "channel": manifest_distribution,
        "manifestDistribution": manifest_distribution,
        "buildCommandChannel": build_command_channel,
        "packageScriptChannel": package_script_channel,
        "directUpdatesAllowed": direct_updates_allowed,
        "directUpdatesSource": "Sources/OuroMD/OuroMDDistribution.swift",
        "category": build_script_category,
        "manifestCategory": manifest_category,
        "buildScriptAppStoreCategory": build_script_category,
        "usesNonExemptEncryption": False if encryption_claim_false else None,
        "usesNonExemptEncryptionSource": "make-app.sh",
    },
    "telemetry": {
        "defaultDisabled": telemetry_default_disabled,
        "posthogKeyEmbeddedByDefault": not telemetry_default_disabled,
        "optInVariable": "OURO_MD_APP_STORE_ENABLE_TELEMETRY",
        "manifestBuildCommandDisablesTelemetry": build_command_disables_telemetry,
        "packageScriptDisablesTelemetryByDefault": package_disables_telemetry,
        "buildScriptHonorsTelemetryDisable": build_script_honors_telemetry_disable,
    },
    "package": {
        "script": "scripts/package-app-store.sh",
        "buildEnvironment": package_build_env,
        "manifestBuildEnvironment": manifest_build_env,
        "outputDirectory": "dist/app-store",
    },
    "tooling": tool_checks,
    "signing": {
        "appIdentityConfigured": app_identity_configured,
        "appIdentityFound": app_identity_found,
        "installerIdentityConfigured": installer_identity_configured,
        "installerIdentityFound": installer_identity_found,
        "provisioningProfileConfigured": bool(profile_path),
        "provisioningProfilePresent": bool(profile_path and Path(profile_path).is_file()),
    },
    "appStoreConnect": {
        "authConfigured": auth_configured,
        "authMode": "api" if api_auth_configured else ("apple-id" if apple_auth_configured else "not-configured"),
        "authFilePresent": bool(api_path and Path(api_path).is_file()),
    },
    "secretScan": {
        "ok": not forbidden_matches,
        "forbiddenMatches": forbidden_matches,
    },
    "blockers": blockers,
}

body = json.dumps(readiness, indent=2, sort_keys=True) + "\n"
if ARTIFACT:
    path = Path(ARTIFACT)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    print("app-store readiness artifact: written")
    print(f"app-store readiness blockers: {len(blockers)}")
else:
    print(body, end="")
PY
}

if [[ "$readiness" == "1" ]]; then
  print_readiness
  exit 0
fi

require_tooling
require_app_store_identities

make_app_env=(OURO_MD_DISTRIBUTION_CHANNEL=app-store)
if [[ "${OURO_MD_APP_STORE_ENABLE_TELEMETRY:-}" != "1" ]]; then
  make_app_env+=(OURO_MD_TELEMETRY_DISABLED=1)
fi
env "${make_app_env[@]}" ./make-app.sh

if [[ -n "${OURO_APP_STORE_PROVISIONING_PROFILE:-}" ]]; then
  [[ -f "$OURO_APP_STORE_PROVISIONING_PROFILE" ]] || fail "provisioning profile not found"
  cp "$OURO_APP_STORE_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  chmod 644 "$APP/Contents/embedded.provisionprofile"
fi

run_adk_xcode \
  --kind codesign \
  --identity "$APP_IDENTITY" \
  --path "$APP" \
  --entitlements "$ENTITLEMENTS"
codesign --verify --deep --strict --verbose=2 "$APP"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
channel="$(/usr/libexec/PlistBuddy -c 'Print :OuroMDDistributionChannel' "$APP/Contents/Info.plist")"
uses_non_exempt_encryption="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP/Contents/Info.plist")"
[[ "$bundle_id" == "bot.ouro.md" ]] || fail "expected canonical bundle id bot.ouro.md, got $bundle_id"
[[ "$channel" == "app-store" ]] || fail "expected app-store distribution channel, got $channel"
[[ "$uses_non_exempt_encryption" == "false" ]] || fail "expected ITSAppUsesNonExemptEncryption=false, got $uses_non_exempt_encryption"
if [[ "${OURO_MD_APP_STORE_ENABLE_TELEMETRY:-}" != "1" ]] \
  && /usr/libexec/PlistBuddy -c 'Print :OuroMDPostHogKey' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  fail "App Store package must not embed telemetry unless OURO_MD_APP_STORE_ENABLE_TELEMETRY=1"
fi

mkdir -p "$OUT_DIR"
pkg="$OUT_DIR/Ouro-MD-${version}-app-store.pkg"
rm -f "$pkg"
run_adk_xcode \
  --kind productbuild \
  --identity "$INSTALLER_IDENTITY" \
  --component "$APP" \
  --install-location /Applications \
  --output "$pkg"

build_auth_args

if [[ "$validate" == "1" || "$upload" == "1" ]]; then
  [[ "${#auth_args[@]}" -gt 0 ]] || fail "App Store validation/upload requires App Store Connect auth env"
  run_adk_xcode --kind altool-validate --package-path "$pkg" "${auth_args[@]}"
fi

if [[ "$upload" == "1" ]]; then
  run_adk_xcode --kind altool-upload --package-path "$pkg" "${auth_args[@]}"
fi

echo "app store package ready: $pkg"
echo "bundle id: $bundle_id"
echo "version: $version"
