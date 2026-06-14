# Ouro MD Audit Backlog

**Status**: NEEDS_REVIEW
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
**Status**: open
**Linked work**: ../2026-06-14-1519-planning-auto-updater-reliability.md
**Notes**: Mirror Workbench's `ReleaseUpdate.swift`, `WorkbenchUpdate.swift`, and `WorkbenchUpdateInstaller.swift`, adapted for `Ouro MD.app` and `org.ourostack.ouro-md`.

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
**Status**: open
**Linked work**: ../2026-06-14-1519-planning-auto-updater-reliability.md
**Notes**: Existing route uses Vditor internals directly; tests should catch Vditor API drift.

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
**Verification**: `swift run ouro-md --version` reports `0.9.0`; README install command uses `https://ouro.bot/ouro-md-install.sh`; package manifest still emits `0.9.0`.
**Status**: open
**Linked work**: ../2026-06-14-1519-planning-auto-updater-reliability.md
**Notes**: Prefer a Swift `OuroMDRelease` descriptor that updater and CLI can share.

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
**Status**: open
**Linked work**: ../2026-06-14-1519-planning-auto-updater-reliability.md
**Notes**: This is small enough to include in the first reliability tranche.

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
**Status**: open
**Linked work**: ../2026-06-14-1519-planning-auto-updater-reliability.md
**Notes**: Deeper AppModel extraction should wait until the updater lands and the new boundaries are visible.

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
**Status**: open
**Linked work**:
**Notes**: Defer until after updater and shortcut reliability work.

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
**Status**: open
**Linked work**: ../2026-06-14-1519-planning-auto-updater-reliability.md
**Notes**: Include the doc refresh in the first tranche only where it is required to remove false version/install claims.

---
