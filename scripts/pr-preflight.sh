#!/usr/bin/env bash
#
# Local maintainer/agent preflight for PRs. This intentionally mirrors the
# release freshness/source policy and the same scenario gates CI runs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

base_ref="${OURO_PR_BASE_REF:-${GITHUB_BASE_REF:-main}}"

./scripts/verify-release-version.sh
./scripts/release-policy.sh freshness --mode pr --base-ref "$base_ref"
./scripts/release-policy.sh scan .
./scripts/check-signing-readiness.sh
swift build
./scripts/swift-test-budget.sh
./scripts/check-coverage.sh
OURO_MD_EXE="${OURO_MD_EXE:-.build/debug/ouro-md}" ./scripts/run-native-scenarios.sh

echo "PR preflight ok"
