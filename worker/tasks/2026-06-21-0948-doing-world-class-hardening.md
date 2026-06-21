# Doing: Ouro MD World-Class Hardening

**Status**: in-progress
**Execution Mode**: direct
**Created**: 2026-06-21 09:48
**Planning**: ./2026-06-21-0948-planning-world-class-hardening.md
**Artifacts**: ./2026-06-21-0948-doing-world-class-hardening/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts (non-autopilot interactive mode only; autopilot must convert this to `spawn` or `direct` unless a hard exception is present)
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective

Ship the "next 20+ things" world-class hardening pass for Ouro MD: convert the 25-item acceptance list into permanent CI, release, visual, native UI, update/install, export, folder, and dogfood safeguards.

The work is under autopilot/no-human-gates authority from the operator: do not pause for human approval; use sub-agent reviewer gates, merge to `main`, verify CI/release/install, and clean up branches/worktrees before completion.

## Upstream Work Items

- None

## Completion Criteria

- [ ] The evidence matrix below has all 25 rows closed with one of: implemented, test/probe-covered, or hard-exception.
- [ ] Every non-hard-exception row records concrete evidence: changed file(s), test/probe name, and the validation command that passed.
- [ ] New or changed probes run in both local/package verification and CI when the behavior can be exercised in those environments.
- [ ] CI produces durable debugging artifacts/annotations for slow tests and visual failures.
- [ ] `swift test` passes.
- [ ] `./scripts/check-coverage.sh` passes with 100% line and region coverage for `OuroMDCore`.
- [ ] Native scenario verification passes against SwiftPM output.
- [ ] Packaged app verification passes against the `.app` bundle.
- [ ] PR preflight passes locally.
- [ ] App-affecting changes are version-bumped, released, and verified from GitHub releases, unless the final evidence matrix records why release publication is non-applicable or blocked by a hard exception.
- [ ] Main is green after merge.
- [ ] No stale PR, branch, or worktree from this run remains.
- [ ] Desk task state records terminal evidence and is archived.

## Code Coverage Requirements

**MANDATORY: 100% coverage on all new pure/model code.**

- Maintain `./scripts/check-coverage.sh` passing at 100% line and region coverage for `OuroMDCore`.
- Add focused XCTest coverage for new pure/model/update/menu logic.
- Add headless CLI probes for visual/native/editor/export behavior that XCTest cannot faithfully inspect.
- Add release/package verification coverage for shipped `.app` behavior, not only SwiftPM-local behavior.
- No `[ExcludeFromCodeCoverage]` or equivalent on new code.
- All branches covered where the code lives in `OuroMDCore`.
- All error paths tested for new pure logic.
- Edge cases: empty input, missing files, unreadable files, cancellation, and boundary viewport sizes where relevant.

## TDD Requirements

**Strict TDD — no exceptions:**

1. **Tests first**: Write failing tests BEFORE any implementation when a behavior can be tested before code changes.
2. **Verify failure**: Run tests, confirm they FAIL (red), or record why a pre-existing missing harness makes red impractical.
3. **Minimal implementation**: Write just enough code to pass.
4. **Verify pass**: Run tests, confirm they PASS (green).
5. **Refactor**: Clean up, keep tests green.
6. **No skipping**: Never write implementation without either a failing test/probe first or an explicit hard-exception note in the evidence matrix.

## Acceptance Evidence Matrix

| # | Criterion | Evidence | Validation | Status |
|---|---|---|---|---|
| 1 | Local PR preflight mirrors freshness/source policy | `scripts/pr-preflight.sh` runs release version, freshness, source scan, build, timed tests, coverage, and native scenarios; README maintainer section points to it | `bash -n ...`; `./scripts/release-policy.sh scan .`; final full `./scripts/pr-preflight.sh` in Unit 6 | implemented, final full run pending |
| 2 | Node 20 warning handled | `.github/workflows/ci.yml` and `.github/workflows/release.yml` use `actions/upload-artifact@v6` | `rg -n "upload-artifact@v5|upload-artifact@v6"` shows only v6 | implemented |
| 3 | Slowest-test annotations/artifact | `scripts/swift-test-budget.sh` prints slowest XCTest cases, writes `.build/ouro-test-timings.tsv`, and CI uploads timing artifacts | `OURO_TEST_LOG=.build/unit1-swift-test.log OURO_TEST_TIMINGS=.build/unit1-test-timings.tsv ./scripts/swift-test-budget.sh --filter ReleaseUpdateTests/testReleaseDescriptorMatchesCurrentDistribution` | implemented |
| 4 | Individual XCTest runtime budget | `scripts/swift-test-budget.sh` fails when any XCTest exceeds `OURO_TEST_MAX_SECONDS` | same filtered wrapper run validated timing parse; full suite budget runs in Unit 6 | implemented, full-suite budget pending |
| 5 | Visual QA screenshots on failure | `scripts/run-visual-qa.sh` captures PNG artifacts with `--shoot`; CI uploads `${{ runner.temp }}/ouro-md-artifacts` on native scenario failure | `OURO_VISUAL_ARTIFACT_DIR=.build/unit1-visual-artifacts ./scripts/run-native-scenarios.sh` | implemented |
| 6 | Visual QA covers prefs/search/update/menu | Extend `UISurfaceTest`/menu probes | pending | pending |
| 7 | Accessibility audit | Add AX labels/focus/contrast/reduced-motion checks | pending | pending |
| 8 | Title/click/open flows | Add title decision/open-state tests | pending | pending |
| 9 | Open Recent isolation | Inject recents provider into menu delegate and tests | pending | pending |
| 10 | Multi-window regressions | Add two-window model/app tests | pending | pending |
| 11 | Dirty doc + update install + quit cancel | Add coordinator/app-level cancellation tests | pending | pending |
| 12 | Web crash/reload smoke | Add actual headless WebKit crash/reload probe | pending | pending |
| 13 | Large folders/deep/unusual/symlink | Extend folder scanner/browser tests | pending | pending |
| 14 | Folder search UX edge cases | Add truncation/cancel/binary/unreadable tests | pending | pending |
| 15 | Drag/drop file open + image paste/drop | Add file-open and JS image-transfer harness | pending | pending |
| 16 | Pathological tables | Extend fixture with empty/aligned/HTML/URL cases and gate | pending | pending |
| 17 | Print/PDF export probe | Add headless export probe with PDF validation | pending | pending |
| 18 | HTML export snapshots all themes | Add render/export checks for each built-in theme | pending | pending |
| 19 | Older-live to latest-live update e2e | Add script harness; run when feasible | pending | pending |
| 20 | Rollback after backup creation | Strengthen installer/one-line rollback tests | pending | pending |
| 21 | Cancellable/recoverable updater progress | Add structured progress/cancel/retry | pending | pending |
| 22 | First-launch blank/empty gate | Add first-launch screenshot/pixel smoke | pending | pending |
| 23 | Command palette/searchable actions | Implement and test action palette | pending | pending |
| 24 | Compact document stats/status | Add status surface and tests | pending | pending |
| 25 | Signing/notarization readiness | Add credential-aware readiness script/check | pending | pending |

## Work Units

### Unit 0: Planning Gate

- [x] Planning reviewer converges.
- [x] Patch planning/doing docs after reviewer findings.
- [ ] Commit docs.

### Unit 1: CI And Release Harnesses

- [x] Add `scripts/pr-preflight.sh`.
- [x] Add XCTest timing/budget wrapper.
- [x] Add slow-test manifest or allowlist and CI annotations/artifact.
- [x] Add visual QA artifact wrapper for screenshots on failure.
- [x] Upgrade `actions/upload-artifact` to v6.
- [x] Add hosted installer smoke/check.
- [x] Update README maintainer workflow.
- [x] Run local script validations.

### Unit 2: Native UI, Accessibility, Menus, Open Flows

- [ ] Inject recents provider through `RecentMenuDelegate` and test without `NSDocumentController.shared`.
- [ ] Extract/test title click-vs-drag decision.
- [ ] Add app/file-open state tests for untitled, saved, renamed, and missing-file documents.
- [ ] Add two-window tests for menu validation, theme/sidebar/search independence, save/rename targeting.
- [ ] Extend `UISurfaceTest` for Preferences/search/update progress/menu layout and AX labels/actions/focus.
- [ ] Add contrast and reduced-motion guardrails.

### Unit 3: Updater Cancellable Progress And Rollback

- [ ] Introduce structured install progress state.
- [ ] Add install cancellation while staging is in-flight.
- [ ] Render Cancel/Retry/status affordances in update progress.
- [ ] Add dirty-doc install quit-cancel test that prevents apply and preserves retry.
- [ ] Harden one-line installer rollback verification.
- [ ] Add forced post-backup rollback test/harness for apply script.

### Unit 4: Editor, Search, Folder, Tables, Image Transfer, Export

- [ ] Extend large-folder/deep/unusual/symlink tests.
- [ ] Add search truncation/cancel/binary/unreadable/permissions coverage.
- [ ] Add `--imagetransfertest` or equivalent bridge transfer probe.
- [ ] Extend pathological table fixture and table gate.
- [ ] Add HTML export checks for all themes.
- [ ] Add PDF/print export probe.
- [ ] Add WebKit crash/reload headless smoke.

### Unit 5: Product Polish

- [ ] Add first-launch nonblank/themed screenshot or pixel smoke.
- [ ] Implement searchable command palette.
- [ ] Add compact document stats/status surface.
- [ ] Add signing/notarization readiness check and document hard exception if credentials unavailable.

### Unit 6: Verification, Review, Merge, Release

- [ ] Run `git diff --check`.
- [ ] Run targeted tests/probes for each changed unit.
- [ ] Run `swift test`.
- [ ] Run `./scripts/check-coverage.sh`.
- [ ] Run app bundle verification.
- [ ] Run PR preflight.
- [ ] Run final sub-agent implementation reviewer gate.
- [ ] Push branch and open PR.
- [ ] Wait for PR CI.
- [ ] Merge to `main`.
- [ ] Wait for main CI and release workflow.
- [ ] Verify published release if app-affecting.
- [ ] Clean branch/worktree.
- [ ] Update and archive Desk task.

## Progress Log

- 2026-06-21 09:48 Created doing doc from audit-backed planning scope.
- 2026-06-21 09:55 Folded explorer findings into unit checklist and 25-row acceptance trace.
- 2026-06-21 10:02 Reshaped doing doc to the local template and made the evidence matrix mandatory after reviewer findings.
- 2026-06-21 10:10 Completed Unit 1 harness layer: PR preflight, XCTest timing/budget wrapper, native scenario wrapper, visual failure artifacts, hosted installer check, CI/release wiring, and README notes. Validation: script syntax/diff check, source policy scan, filtered Swift timing wrapper, and shared native scenario wrapper passed.
