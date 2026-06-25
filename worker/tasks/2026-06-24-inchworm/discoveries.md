# Inch-worm backlog — ouro-md (campaign started 2026-06-24)

Canonical backlog for the open inch-worm campaign. Append-only except for `Status`
updates. New discoveries get the next `D-00n` id.

---

## [D-001] — App version is triplicated; a bump can't be made atomically

**Source**: observed-during-seed (self-observed during the v0.9.36 release this session)
**What**: The app version is hand-maintained in three places — `Sources/OuroMDCore/OuroMDRelease.swift` (`version = "x.y.z"`), `make-app.sh` (`VERSION="x.y.z"`), and `README.md` (`> **Status:** vx.y.z`) — enforced only by `scripts/verify-release-version.sh`, which fails *after* the fact in CI.
**Where**: `make-app.sh:15`, `Sources/OuroMDCore/OuroMDRelease.swift:7`, `README.md:9`, `scripts/verify-release-version.sh`.
**Why it matters**: During the v0.9.36 release the bump was partial — CI failed once on `make-app.sh`, then again on `README.md`, two wasted ~4-minute CI cycles. The build script (`make-app.sh`) is the most-forgettable pin.
**Evidence**: PR #46 CI run 28131695466 failed with `version mismatch: make-app.sh=0.9.35 OuroMDRelease.swift=0.9.36`, then again on `README=0.9.35`. `scripts/readiness-stress.sh:6` already derives the version from `OuroMDRelease.swift`, so that file is the de-facto source of truth.
**Severity**: high-value
**Blast radius**: affects one module (release tooling)
**Fix shape**: Make `OuroMDRelease.swift` the single source of truth; have `make-app.sh` derive `VERSION` from it (matching `readiness-stress.sh`); update `verify-release-version.sh` to guard that make-app *stays* a derivation and that the README matches. Removes the most error-prone pin.
**Verification**: `./scripts/verify-release-version.sh`, `./scripts/verify-release-version.sh --print`, a simulated partial bump must fail, `bash -n make-app.sh scripts/verify-release-version.sh`, `./scripts/pr-preflight.sh`.
**Status**: in-progress
**Linked work**: (this PR)
**Notes**: README can't derive at build time (static docs), so it remains a manual pin — the bump-helper follow-up (see D-002) closes that gap.

---

## [D-002] — No single command to bump the version; README still hand-edited

**Source**: observed-during-seed (logged while fixing D-001)
**What**: Even after D-001 makes `make-app.sh` derive its version, a release bump still requires editing `OuroMDRelease.swift` (version + `releaseDate` + `releaseHighlights`) and the `README.md` status line by hand — two human edits that can still go out of sync.
**Where**: `Sources/OuroMDCore/OuroMDRelease.swift:7,9`, `README.md:9`.
**Why it matters**: The README is the one remaining manual pin; `verify-release-version.sh` catches a mismatch only after the fact. A `scripts/bump-version.sh x.y.z` that updates the Swift constant + `releaseDate` + README atomically would make a partial bump structurally impossible.
**Severity**: nice-to-have
**Blast radius**: self-contained (release tooling)
**Fix shape**: Add `scripts/bump-version.sh <semver>` that rewrites `OuroMDRelease.version`, sets `releaseDate` to today, and rewrites the README status line; document it in the maintainer/release section. Leave `releaseHighlights` to the human.
**Prerequisites**: D-001 (make-app derives) should land first.
**Verification**: `bash -n scripts/bump-version.sh`; run it on a scratch version and assert `verify-release-version.sh` passes; assert it's idempotent.
**Status**: open

---

## [D-003] — The "read version from OuroMDRelease.swift" sed is duplicated across three scripts

**Source**: observed-during-seed (logged while fixing D-001)
**What**: After D-001, `make-app.sh`, `scripts/verify-release-version.sh`, and `scripts/readiness-stress.sh` each independently `sed`-extract `static let version = "..."` from `OuroMDRelease.swift` (with slightly different patterns — `[^"]*` vs greedy `.*`).
**Where**: `make-app.sh:15`, `scripts/verify-release-version.sh:24`, `scripts/readiness-stress.sh:6`.
**Why it matters**: Three copies of the same extraction can drift (e.g., if the Swift declaration's formatting changes, only some patterns keep matching). Low urgency — they all currently work — but it's a quiet footgun.
**Severity**: nice-to-have
**Blast radius**: affects one module (release tooling)
**Fix shape**: Extract a tiny `scripts/lib/app-version.sh` (or a `--print-source` flag on verify) that emits the Swift version, and have the three callers source it. Keep it independent of the README check so `make-app.sh` still works when the README is mid-bump.
**Severity-note**: bundle opportunistically; not worth a standalone PR unless touched anyway.
**Status**: open

---
