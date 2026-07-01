#!/usr/bin/env bash
#
# Validates the vendored Vditor distribution manifest and tracked-file digest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

manifest="docs/vditor-vendor-manifest.json"

python3 - "$manifest" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
root = Path.cwd()
vendor_root = Path("Sources/OuroMD/web/vditor")

def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)

if not manifest_path.exists():
    fail(f"missing Vditor vendor manifest: {manifest_path}")

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    fail(f"{manifest_path}: invalid JSON: {exc}")

if manifest.get("schemaVersion") != 1:
    fail("schemaVersion must be 1")
if manifest.get("vendorRoot") != str(vendor_root):
    fail(f"vendorRoot must be {vendor_root}")
if manifest.get("upstreamPackage") != "vditor":
    fail("upstreamPackage must be vditor")
if not str(manifest.get("upstreamRepository", "")).startswith("https://github.com/Vanessa219/vditor"):
    fail("upstreamRepository must point at Vanessa219/vditor")
if not manifest.get("upstreamVersion"):
    fail("upstreamVersion must be populated")
if manifest.get("licensePath") != str(vendor_root / "LICENSE"):
    fail("licensePath must point at Sources/OuroMD/web/vditor/LICENSE")
if not (root / manifest["licensePath"]).exists():
    fail(f"licensePath not found: {manifest['licensePath']}")
if "MIT" not in (root / manifest["licensePath"]).read_text(encoding="utf-8", errors="replace"):
    fail("licensePath does not contain MIT license text")

refresh = manifest.get("refresh")
if not isinstance(refresh, dict):
    fail("refresh must be an object")
for key in ("source", "buildCommand", "copyCommand", "validationCommands"):
    if key not in refresh:
        fail(f"refresh.{key} is required")
if not isinstance(refresh.get("validationCommands"), list) or not refresh["validationCommands"]:
    fail("refresh.validationCommands must be a non-empty list")

digest = manifest.get("trackedDigest")
if not isinstance(digest, dict):
    fail("trackedDigest must be an object")

tracked = subprocess.check_output(
    ["git", "ls-files", str(vendor_root)],
    text=True,
).splitlines()
tracked = sorted(path for path in tracked if path)
if not tracked:
    fail(f"no tracked files under {vendor_root}")

hasher = hashlib.sha256()
for path in tracked:
    data = (root / path).read_bytes()
    hasher.update(path.encode("utf-8"))
    hasher.update(b"\0")
    hasher.update(data)
    hasher.update(b"\0")

actual = {
    "algorithm": "sha256-path-and-bytes-v1",
    "fileCount": len(tracked),
    "sha256": hasher.hexdigest(),
}

for key, expected in actual.items():
    if digest.get(key) != expected:
        fail(f"trackedDigest.{key} mismatch: manifest={digest.get(key)!r} actual={expected!r}")

preflight = Path("scripts/pr-preflight.sh").read_text(encoding="utf-8")
if "./scripts/check-vditor-vendor.sh" not in preflight:
    fail("pr-preflight.sh must run scripts/check-vditor-vendor.sh")

release_policy = Path("scripts/release-policy.sh").read_text(encoding="utf-8")
if "selftest-vditor-vendor" not in release_policy:
    fail("release-policy.sh must expose selftest-vditor-vendor")

print("vditor vendor manifest ok")
PY
