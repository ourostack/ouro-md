# Doing: Ouro MD Auto-Updater And Reliability Hardening

**Status**: READY_FOR_EXECUTION
**Execution Mode**: direct
**Created**: 2026-06-14 15:34
**Planning**: ./2026-06-14-1519-planning-auto-updater-reliability.md
**Artifacts**: ./2026-06-14-1519-doing-auto-updater-reliability/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts (non-autopilot interactive mode only; autopilot must convert this to `spawn` or `direct` unless a hard exception is present)
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Add the in-app auto-updater and use the full-system audit to harden the release, shortcut, warning, and documentation surfaces that most affect day-to-day trust in Ouro MD.

## Upstream Work Items
- A-001 - Add in-app auto-updater
- A-002 - Bulletproof undo/redo shortcuts and stack behavior
- A-003 - Centralize and correct version/release truth
- A-004 - Remove Swift test warnings
- A-005 - Keep updater state out of AppModel god-object growth
- A-007 - Refresh README after pretty URL and updater work

## Completion Criteria
- [ ] In-app update check can detect current, update-available, unavailable, missing asset, and malformed manifest cases.
- [ ] Update installation refuses bad sha256, byte count, archive name, bundle id, non-newer version, missing app bundle, and failed codesign checks.
- [ ] A safe manual update UI/action exists and does not swap the running app unless staging and verification succeeded.
- [ ] Launch-time update checking is enabled by default, has a persisted opt-out, is throttled to 3600 seconds by default, does not block document editing startup, stages verified updates in the background, and applies a staged update only on normal app quit or explicit manual install/relaunch.
- [ ] Updater implementation keeps pure logic and installer/stager code outside `AppModel.swift`; existing files get only focused lifecycle/menu hooks.
- [ ] Undo/redo harness coverage proves multi-step undo/redo, redo invalidation after a new edit, empty-stack no-op safety, behavior across Vditor mode rebuilds, native menu selector forwarding, and native text-field focus preservation; any non-automated AppKit focus proof has an explicit no-op disposition plus a manual smoke command.
- [ ] `swift run ouro-md --undotest` passes.
- [ ] `swift run ouro-md --wraptest` passes.
- [ ] `swift run ouro-md --renderprobe` passes.
- [ ] Release/version truth is consistent across CLI, bundle metadata, README, and updater configuration.
- [ ] `swift test` passes and emits no Swift compiler warnings for repo source or test files.
- [ ] `swift test --enable-code-coverage` runs successfully; `xcrun llvm-cov export` output is saved to the doing artifacts as `coverage.json`; the doing artifacts include and run `check-changed-coverage.py` with `BASE_REF="$(git merge-base origin/main HEAD)"`, path filter `Sources/OuroMD/*.swift` excluding harness files (`UndoTest.swift`, `WrapTest.swift`, `RenderProbe.swift`, `RoundTrip.swift`, `Snapshot.swift`, `main.swift`), and it fails unless every executable line in changed/new non-harness Swift files is covered or the doing doc records an explicit no-op disposition for external-process/AppKit boundary code already exercised by an E2E harness.
- [ ] All verification commands pass: `swift test`, `swift test --enable-code-coverage`, `python3 worker/tasks/2026-06-14-1519-doing-auto-updater-reliability/check-changed-coverage.py --base "$(git merge-base origin/main HEAD)" --coverage worker/tasks/2026-06-14-1519-doing-auto-updater-reliability/coverage.json`, `swift run ouro-md --undotest`, `swift run ouro-md --wraptest`, `swift run ouro-md --renderprobe`, `swift run ouro-md --roundtrip sample.md`, `./scripts/package-release.sh`, and the safe live installer smoke `tmp="$(mktemp -d)"; curl -fsSL https://ouro.bot/ouro-md-install.sh | OURO_MD_INSTALL_DIR="$tmp" OURO_MD_NO_OPEN=1 bash` after the release is published.
- [ ] No warnings from Swift compilation or release packaging commands.

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch, try/catch)
- All error paths tested
- Edge cases: null, empty, boundary values

## TDD Requirements
**Strict TDD - no exceptions:**
1. **Tests first**: Write failing tests BEFORE any implementation
2. **Verify failure**: Run tests, confirm they FAIL (red)
3. **Minimal implementation**: Write just enough code to pass
4. **Verify pass**: Run tests, confirm they PASS (green)
5. **Refactor**: Clean up, keep tests green
6. **No skipping**: Never write implementation without failing test first

## Work Units

### Legend
⬜ Not started · 🔄 In progress · ✅ Done · ❌ Blocked

**CRITICAL: Every unit header MUST start with status emoji (⬜ for new units).**

### ✅ Unit 0: Setup/Research
**What**: Snapshot current verification state, save baseline logs to artifacts, and confirm Workbench updater references and current Ouro MD release metadata.
**Output**: Baseline logs under `./2026-06-14-1519-doing-auto-updater-reliability/`.
**Acceptance**: Artifacts include baseline `swift test`, `--undotest`, release metadata, and source-reference notes.

### ✅ Unit 1a: Release Truth And Pure Updater Logic - Tests
**What**: Write failing tests for a new Ouro MD release descriptor, release update snapshot parsing, update planning, manifest decoding, semantic version comparison, auto-update policy, and archive verification failures.
**Acceptance**: New tests fail before implementation because the new release/update types do not exist or return missing behavior.

### ✅ Unit 1b: Release Truth And Pure Updater Logic - Implementation
**What**: Add focused pure Swift updater types outside `AppModel.swift`, centralize version/bundle identity for CLI/updater use, and satisfy Unit 1a tests.
**Acceptance**: Unit 1a tests pass; CLI version is sourced from the new release descriptor.

### ✅ Unit 1c: Release Truth And Pure Updater Logic - Coverage & Refactor
**What**: Refactor pure updater logic, add missing branch/error tests, and keep release descriptor naming clear.
**Acceptance**: Pure updater tests cover success, boundary, and error paths; `swift test` passes for the targeted test set.

### ✅ Unit 2a: Update Installer/Stager - Tests
**What**: Write failing tests or a testable seam for download/stage/verify/extract behavior: manifest decode failure, sha mismatch, byte mismatch, archive-name mismatch, bundle-id mismatch, non-newer version, missing staged app, and staged Info.plist mismatch.
**Acceptance**: Tests fail before implementation because installer/stager seams and errors are missing.

### ✅ Unit 2b: Update Installer/Stager - Implementation
**What**: Add an Ouro MD installer/stager adapted from Workbench, with side effects isolated from AppModel and with helper-process apply/relaunch logic using the verified staged app.
**Acceptance**: Unit 2a tests pass; the swap helper is isolated and does not run during tests.

### ✅ Unit 2c: Update Installer/Stager - Coverage & Refactor
**What**: Add remaining tests for installer/stager error paths and document any external-process/AppKit boundary coverage no-op dispositions.
**Acceptance**: Stager pure/seam logic has direct branch coverage; any no-op disposition is explicit in this doing doc.

### ⬜ Unit 3a: App Integration And Update UI - Tests
**What**: Write failing tests for auto-update policy/defaults, persisted opt-out, 3600-second throttling, manual update prompt state, and thin app coordinator behavior where testable.
**Acceptance**: Tests fail before implementation because app integration/update state does not exist.

### ⬜ Unit 3b: App Integration And Update UI - Implementation
**What**: Add `Check for Updates...`, update prompt/status state, launch-time background staging, install-on-quit, persisted opt-out, and preferences/menu hooks while keeping existing files thin.
**Acceptance**: Unit 3a tests pass; updater logic remains outside `AppModel.swift` except for minimal UI/lifecycle hooks if unavoidable.

### ⬜ Unit 3c: App Integration And Update UI - Coverage & Refactor
**What**: Refactor app integration for clarity and add missing tests for defaults/throttle/prompt transitions.
**Acceptance**: Integration tests cover policy and state transitions; UI hooks are documented and narrow.

### ⬜ Unit 4a: Undo/Redo Bulletproofing - Tests
**What**: Expand the headless undo harness and/or add native unit seams to fail on multi-step undo/redo, redo invalidation after a new edit, empty-stack no-op safety, behavior across Vditor mode rebuilds, native menu selector forwarding, and native text-field focus preservation.
**Acceptance**: Expanded tests fail before implementation or harness changes because current proof does not cover the new cases.

### ⬜ Unit 4b: Undo/Redo Bulletproofing - Implementation
**What**: Adjust undo/redo bridge/menu behavior only as required by Unit 4a; otherwise make the harness prove the existing implementation is correct.
**Acceptance**: Expanded undo/redo tests pass and existing `--undotest` remains green.

### ⬜ Unit 4c: Undo/Redo Bulletproofing - Coverage & Refactor
**What**: Refactor undo test output for clear pass/fail evidence and record any native AppKit focus no-op disposition if automation is not reliable.
**Acceptance**: `swift run ouro-md --undotest` proves all required undo/redo cases or the doing doc records an explicit no-op disposition with manual smoke command.

### ⬜ Unit 5a: Warning Cleanup And Documentation Truth - Tests
**What**: Write failing or currently-warning verification for weak `MockBridge` assignments and add doc/install truth checks if practical.
**Acceptance**: Baseline verification shows the current warnings or stale text before fixes.

### ⬜ Unit 5b: Warning Cleanup And Documentation Truth - Implementation
**What**: Fix weak mock bridge warning patterns, update README and `web/ouro-md-install.sh` comments for v0.9.0, pretty URL, and updater behavior, and keep package/install behavior unchanged.
**Acceptance**: `swift test` emits no weak `MockBridge` warnings; docs and installer comments no longer claim the pretty URL is unwired or the app is v0.1.0.

### ⬜ Unit 5c: Warning Cleanup And Documentation Truth - Coverage & Refactor
**What**: Run warning-clean verification, ensure docs are accurate after updater behavior is known, and update audit backlog items with in-progress linked work/progress notes only.
**Acceptance**: Warning output is clean; A-001/A-002/A-003/A-004/A-005/A-007 point at this doing doc/branch without terminal fixed dispositions before merge, release, and live smoke are complete.

### ⬜ Unit 6a: Pre-Merge Full Verification And Package Dry Run
**What**: Run the full verification matrix on the feature branch, save coverage artifacts, and run `./scripts/package-release.sh` as a dry-run packaging verification only.
**Output**: Verification logs, coverage artifacts, `coverage.json`, coverage-check output, and package dry-run output under artifacts.
**Acceptance**: All local verification commands pass on the feature branch; package dry run succeeds but no GitHub release is created from the branch SHA.

### ⬜ Unit 6b: PR, Review, Merge, And Cleanup
**What**: Open a PR, run/record GitHub checks; if no `.github/workflows` or required external CI exists, record a no-CI disposition and rely on the complete local verification matrix; merge through GitHub; fetch `origin/main`; clean local/remote feature branch safely.
**Output**: PR URL, merge commit, GitHub check/no-CI evidence, cleanup evidence.
**Acceptance**: PR is merged to `main`; no dirty worktree; no unpushed commits; no stale local or remote feature branch if safe to delete. The merged PR remains as project history and is not considered residue.

### ⬜ Unit 6c: Publish From Merged Main And Live E2E Smoke
**What**: From merged `origin/main`, package the final release so the manifest embeds the merged main SHA, publish the GitHub release, smoke `https://ouro.bot/ouro-md-install.sh` into a temp directory with `OURO_MD_NO_OPEN=1`, verify installed bundle version/bundle id, update audit backlog terminal statuses, desk task, and final artifacts.
**Output**: Release URL, final manifest/zip names, live installer smoke output, installed bundle identity/version, final backlog/task updates.
**Acceptance**: Release is published from merged main; `https://ouro.bot/ouro-md-install.sh` installs the new release into a temp directory without opening the app; installed bundle id/version match expectations; no dirty worktree, unpushed commits, open PR from this run, or unsafe branch residue remains.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- TDD applies to code-changing units. Evidence/release units (`Unit 0`, `Unit 6a`, `Unit 6b`, `Unit 6c`) must produce and verify artifacts, but do not need artificial red tests.
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- **All artifacts**: Save outputs, logs, data to `./2026-06-14-1519-doing-auto-updater-reliability/`
- **Fixes/blockers**: Spawn sub-agent immediately - don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- 2026-06-14 15:34 Created from planning doc after Round 4 harsh reviewer convergence
- 2026-06-14 15:56 Unit 0 complete: saved baseline release metadata and verification logs; baseline `swift test`, `--undotest`, `--wraptest`, `--renderprobe`, and `--roundtrip sample.md` all exited successfully
- 2026-06-14 15:58 Unit 1a complete: added pure updater/release tests and saved the expected red `swift test` compile failure to `./2026-06-14-1519-doing-auto-updater-reliability/unit1a-red-swift-test.log`
- 2026-06-14 16:01 Unit 1b complete: added `OuroMDRelease`, release snapshot parsing, update planning, manifest verification, and auto-update policy; `swift test`, `swift build`, and `swift run ouro-md --version` passed with evidence in `unit1b-*.log`
- 2026-06-14 16:06 Unit 1c complete: added request-shape/status tests for the default GitHub loader, release configuration coverage, malformed-tag coverage, and prerelease filtering; `swift test --filter ReleaseUpdateTests`, `swift test`, `swift build`, and `swift test --enable-code-coverage` passed with evidence in `unit1c-*.log` (coverage log still shows the pre-existing weak `MockBridge` warnings routed to Unit 5)
- 2026-06-14 16:10 Unit 2a complete: added installer/stager seam tests for manifest decode, archive verification, extraction, staged Info.plist identity/version, and codesign failures; saved expected red compile failure to `./2026-06-14-1519-doing-auto-updater-reliability/unit2a-red-installer-tests.log`
- 2026-06-14 16:14 Unit 2b complete: added isolated `OuroMDUpdateInstaller` staging and apply helper; `swift test --filter OuroMDUpdateInstallerTests`, `swift test`, and `swift build` passed with evidence in `unit2b-*.log`
- 2026-06-14 16:19 Unit 2b review fix complete: cold reviewer found unsafe apply-helper backup/install failure handling; added `applyScript` regression coverage and fail-fast backup/install/rollback shell flow, verified by `unit2b-review-fix-*.log`
- 2026-06-14 16:24 Unit 2b Round 2 review fix complete: cold reviewer found backup cleanup/reopen still happened before final destination proof; added ordering and temp-dir execution tests, then gated backup deletion, reopen, and staging cleanup on safe destination shape with evidence in `unit2b-review2-fix-*.log`
- 2026-06-14 16:29 Unit 2b Round 3 review fix complete: cold reviewer found initial cleanup still destroyed a stale rollback backup; added stale-backup restore regression coverage and changed apply script to remove only `.update-new` up front, restore existing backups when destination is missing/bad, and discard stale backups only after proving a live destination, with evidence in `unit2b-review3-fix-*.log`
- 2026-06-14 16:35 Unit 2c complete: added installer error-description and unzip fallback coverage, saved coverage export/show/summary artifacts, and recorded explicit no-op disposition for real network/process/app-swap boundaries in `unit2c-no-op-disposition.md`; `swift test --filter OuroMDUpdateInstallerTests`, `swift test`, `swift build`, and `swift test --enable-code-coverage` passed
- 2026-06-14 16:38 Unit 2c review fix complete: cold reviewer found injected `dataLoader` failure handling was testable but uncovered; added generic failure wrapping and `InstallError` pass-through tests, regenerated coverage artifacts, and corrected `unit2c-no-op-disposition.md`, with evidence in `unit2c-review-fix-*.log`
