# Ouro MD Audit Backlog

**Status**: done
**Created**: 2026-06-14 15:19
**Source report**: ./audit-report.md

## A-001 - Add in-app auto-updater

**Source**: audit
**What**: Ouro MD has release archives/manifests and a one-line installer but no native update check, staging, install, or relaunch flow.
**Why it matters**: Users must manually re-run the installer; a text editor should keep itself current without requiring source checkout knowledge.
**Evidence**: `web/ouro-md-install.sh`; `scripts/package-release.sh`; latest GitHub release `v0.9.0`; no update types in `Sources/OuroMD`.
**Severity**: high
**Blast radius**: affects multiple modules
**Dependencies**: A-003
**Recommended lane**: planner-required
**Suggested supporting skills**: work-planner, work-doer
**Verification**: Add pure unit tests for release snapshot/planning/verification; run `swift test`; run a safe staged-install harness or dry-run for app extraction and identity checks.
**Status**: done
**Linked work**: ../2026-06-14-1519-doing-auto-updater-reliability.md
**Notes**: Shipped in PR #1 and release `v0.9.1` with pure release/update logic, verified installer/stager, app coordinator, menu/preferences hooks, launch-time staging, manual install safety fixes, and live `https://ouro.bot/ouro-md-install.sh` smoke passing.

---

## A-002 - Bulletproof undo/redo shortcuts and stack behavior

**Source**: audit
**What**: Undo/redo is fixed and `--undotest` passes, but coverage only proves one real edit, one undo, and one redo.
**Why it matters**: Undo/redo is a trust boundary for a text editor. Shortcut routing, native text fields, redo invalidation, and editor rebuilds need stronger proof.
**Evidence**: `Sources/OuroMD/MenuBuilder.swift`; `Sources/OuroMD/AppDelegate.swift`; `Sources/OuroMD/web/bridge.js`; `Sources/OuroMD/UndoTest.swift`; `swift run ouro-md --undotest` passes.
**Severity**: high
**Blast radius**: affects multiple modules
**Dependencies**: None
**Recommended lane**: planner-required
**Suggested supporting skills**: work-planner, work-doer
**Verification**: Expand headless harness coverage for multi-step undo/redo, redo invalidation after new edit, empty-stack no-op, menu selector path, and focus/native-control routing where feasible.
**Status**: done
**Linked work**: ../2026-06-14-1519-doing-auto-updater-reliability.md
**Notes**: Shipped in PR #1 with native shortcut routing tests, focused native text-view preservation, and expanded `--undotest` coverage for multi-step undo/redo, redo invalidation, empty stacks, and mode rebuilds; final local harness passed before release.

---

## A-003 - Centralize and correct version/release truth

**Source**: audit
**What**: Bundle/release version is `0.9.0`, but README and CLI still report `0.1.0`, and README still leads with the raw GitHub installer URL.
**Why it matters**: Updater logic, user support, release diagnostics, and install docs all depend on truthful version identity.
**Evidence**: `make-app.sh:15`; `Sources/OuroMD/CLI.swift:5`; `README.md:9`; `README.md:43`; GitHub release `v0.9.0`.
**Severity**: medium
**Blast radius**: affects multiple modules
**Dependencies**: None
**Recommended lane**: planner-required
**Suggested supporting skills**: work-planner, work-doer
**Verification**: `swift run ouro-md --version` reports the release version; README install command uses `https://ouro.bot/ouro-md-install.sh`; package manifest emits the same release version.
**Status**: done
**Linked work**: ../2026-06-14-1519-doing-auto-updater-reliability.md
**Notes**: Shipped in PR #1/release `v0.9.1` with shared `OuroMDRelease` truth; final package manifest, bundle Info.plist, release assets, and live installed app all verified as `0.9.1`.

---

## A-004 - Remove Swift test warnings

**Source**: audit
**What**: Tests pass but emit warnings because temporary `MockBridge()` instances are assigned to a weak property and immediately deallocated.
**Why it matters**: Warning noise hides future real warnings and violates the no-warning quality bar.
**Evidence**: `Tests/OuroMDTests/AppModelReloadTests.swift`; `swift test` warning output.
**Severity**: medium
**Blast radius**: self-contained
**Dependencies**: None
**Recommended lane**: inch-worm-ready-after-reeval
**Suggested supporting skills**: work-doer
**Verification**: `swift test` passes with no warnings from weak mock bridge assignment.
**Status**: done
**Linked work**: ../2026-06-14-1519-doing-auto-updater-reliability.md
**Notes**: Shipped in PR #1 by retaining weak mock bridges in tests; final warning scans across test, coverage, harness, and package logs were empty.

---

## A-005 - Keep updater state out of AppModel god-object growth

**Source**: audit
**What**: `AppModel.swift` is already an 846-line coordinator across many subsystems.
**Why it matters**: Adding updater state directly there makes the core document model harder to test and reason about.
**Evidence**: `Sources/OuroMD/AppModel.swift`; line count audit.
**Severity**: medium
**Blast radius**: affects multiple modules
**Dependencies**: A-001
**Recommended lane**: planner-required
**Suggested supporting skills**: work-planner, work-doer
**Verification**: Updater pure logic and install staging live in separate files; AppDelegate/AppModel only expose minimal UI/action hooks.
**Status**: done
**Linked work**: ../2026-06-14-1519-doing-auto-updater-reliability.md
**Notes**: Shipped in PR #1 by keeping updater release logic, installer/stager, coordinator, and termination-save barrier outside `AppModel.swift`; AppDelegate/MenuBuilder/Preferences received focused hooks only. Deeper AppModel extraction remains deferred.

---

## A-006 - Avoid double folder scans for tree and flat views

**Source**: audit
**What**: `rescanFolder()` computes tree and flat folder views through two independent recursive scans.
**Why it matters**: Large folders pay duplicate IO/work. Current caps reduce risk, but the design leaves easy performance headroom.
**Evidence**: `Sources/OuroMD/AppModel.swift`; `Sources/OuroMD/FolderBrowser.swift`.
**Severity**: medium
**Blast radius**: affects one module
**Dependencies**: A-001, A-002, A-003, A-004
**Recommended lane**: inch-worm-ready-after-reeval
**Suggested supporting skills**: inch-worm
**Verification**: Add tests proving tree and flat outputs match current behavior; folder scan does one recursive traversal.
**Status**: done
**Linked work**: ../2026-06-14-2028-doing-v1-readiness-followups.md; commit `2c30164` (`perf(folder): scan tree and flat views once`)
**Notes**: Revalidated on `main` at `5b104b6`: `FolderScanner.snapshot(at:sort:)` builds tree and flat outputs from one recursive `scan`, `AppModel.rescanFolder()` consumes that snapshot once, and `FolderBrowserTests` cover the snapshot output, large-folder budget, truncation, symlink, sort, and duplicate-name behavior.

---

## A-007 - Refresh README after pretty URL and updater work

**Source**: audit
**What**: README install/status/roadmap text is stale relative to v0.9.0 and the live `ouro.bot` installer route.
**Why it matters**: The first user-facing surface should match the actual ship state and support path.
**Evidence**: `README.md`.
**Severity**: low
**Blast radius**: self-contained
**Dependencies**: A-001, A-003
**Recommended lane**: inch-worm-ready-after-reeval
**Suggested supporting skills**: work-doer
**Verification**: README describes live pretty URL, current version, update behavior, and remaining signing/notarization limits accurately.
**Status**: done
**Linked work**: ../2026-06-14-1519-doing-auto-updater-reliability.md
**Notes**: Shipped in PR #1/release `v0.9.1` with README status/install/updater text and installer comments refreshed for the live pretty URL; live smoke confirmed `https://ouro.bot/ouro-md-install.sh` installs `Ouro MD.app` version `0.9.1`.

---
