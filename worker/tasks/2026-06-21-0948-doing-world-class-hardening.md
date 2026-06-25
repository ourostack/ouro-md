# Doing: Ouro MD World-Class Hardening

**Status**: done
**Execution Mode**: direct
**Created**: 2026-06-21 09:48
**Planning**: ./2026-06-21-0948-planning-world-class-hardening.md
**Artifacts**: ./2026-06-21-0948-doing-world-class-hardening/

> **Closeout note (2026-06-24).** All 25 acceptance rows and Units 0–5 landed in
> `main` and are live in the shipped app — verified by presence of every claimed
> artifact (`scripts/pr-preflight.sh`, `scripts/swift-test-budget.sh`,
> `scripts/check-live-update-path.sh`, `scripts/check-signing-readiness.sh`,
> `FirstLaunchTest.swift`, `CommandReferenceView.swift`, the hardened table/folder
> probes, etc.) and by the `harden`/`preflight`/`palette` commits now in `main`
> (`5fa290e`, `b1d4e16`, `e69ceba`, `e21f9fc`, `b336952`, `6b6912b`, `18ca164`,
> `bf65fe4`).
>
> Unit 6 was committed mid-flight at `6b6912b` (2026-06-21) and never re-touched,
> so its checklist below still reads unfinished. In reality the work did **not**
> ship as this doc's single-PR + reviewer-gate plan — it was reshaped into a
> stream of small PRs (#26–45) over 2026-06-21 → 06-23, during which the app
> advanced from the doc's target `0.9.16` all the way to `0.9.35`. The Unit 6
> boxes are left unticked on purpose: those exact steps were superseded, not
> executed as written. No stale branch/worktree/PR from this run remains
> (`git worktree list` = root only; no open PRs). Closing as shipped/superseded.

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

- [x] The evidence matrix below has all 25 rows closed with one of: implemented, test/probe-covered, or hard-exception.
- [x] Every non-hard-exception row records concrete evidence: changed file(s), test/probe name, and the validation command that passed.
- [x] New or changed probes run in both local/package verification and CI when the behavior can be exercised in those environments.
- [x] CI produces durable debugging artifacts/annotations for slow tests and visual failures.
- [x] `swift test` passes.
- [x] `./scripts/check-coverage.sh` passes with 100% line and region coverage for `OuroMDCore`.
- [x] Native scenario verification passes against SwiftPM output.
- [x] Packaged app verification passes against the `.app` bundle.
- [x] PR preflight passes locally.
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
| 1 | Local PR preflight mirrors freshness/source policy | `scripts/pr-preflight.sh` runs release version, freshness, PR-base self-test, source scan, build, timed tests, coverage, and native scenarios; README maintainer section points to it | `bash -n ...`; `./scripts/release-policy.sh scan .`; `./scripts/release-policy.sh selftest-pr-base`; `./scripts/release-policy.sh freshness --mode pr --base-ref origin/main`; final full `OURO_PR_BASE_REF=origin/main ./scripts/pr-preflight.sh` passed in Unit 6 | implemented |
| 2 | Node 20 warning handled | `.github/workflows/ci.yml` and `.github/workflows/release.yml` use `actions/upload-artifact@v6` | `rg -n "upload-artifact@v5|upload-artifact@v6"` shows only v6 | implemented |
| 3 | Slowest-test annotations/artifact | `scripts/swift-test-budget.sh` prints slowest XCTest cases, writes `.build/ouro-test-timings.tsv`, and CI uploads timing artifacts | `OURO_TEST_LOG=.build/unit1-swift-test.log OURO_TEST_TIMINGS=.build/unit1-test-timings.tsv ./scripts/swift-test-budget.sh --filter ReleaseUpdateTests/testReleaseDescriptorMatchesCurrentDistribution`; final full `./scripts/pr-preflight.sh` printed slowest XCTest cases | implemented |
| 4 | Individual XCTest runtime budget | `scripts/swift-test-budget.sh` fails when any XCTest exceeds `OURO_TEST_MAX_SECONDS` | filtered wrapper run validated timing parse; final full `./scripts/pr-preflight.sh` ran the full timed suite, 239 tests, 0 failures | implemented |
| 5 | Visual QA screenshots on failure | `scripts/run-visual-qa.sh` captures PNG artifacts with `--shoot`; CI uploads `${{ runner.temp }}/ouro-md-artifacts` on native scenario failure | `OURO_VISUAL_ARTIFACT_DIR=.build/unit1-visual-artifacts ./scripts/run-native-scenarios.sh` | implemented |
| 6 | Visual QA covers prefs/search/update/menu | `UISurfaceTest` now covers Preferences, search sidebar, update progress installing/error states, and menu topology; native scenario runner calls it | `./scripts/run-native-scenarios.sh`; focused `--uisurfacetest` passed | implemented |
| 7 | Accessibility audit | Added explicit SwiftUI labels for Preferences/sidebar/find/update surfaces, headless exposed-label checks, WCAG contrast tests, and reduced-motion CSS guard | `swift-test-budget --filter ThemeAccessibilityTests`; `--uisurfacetest` passed | implemented |
| 8 | Title/click/open flows | Extracted `TitleClickGesture`, tested title click open handler, click-vs-drag threshold, saved/renamed/deleted chrome states | `swift-test-budget --filter DocumentWindowControllerTests` passed | implemented |
| 9 | Open Recent isolation | Injected recent URL provider and clear handler; tested populated/empty recent menu without `NSDocumentController.shared` global state | `swift-test-budget --filter UndoRedoRoutingTests` passed | implemented |
| 10 | Multi-window regressions | Added active-controller tracking and tests for open routing, save/rename targeting, theme/sidebar/search independence, and menu validation | `swift-test-budget --filter AppDelegateWindowRoutingTests` passed | implemented |
| 11 | Dirty doc + update install + quit cancel | `TerminationSaveCoordinatorTests/testSaveFailureCancelsPendingManualUpdateBeforeQuitReply` proves dirty save failure cancels scheduled update before quit reply and preserves retry state | `OURO_TEST_LOG=.build/unit3-focused.log OURO_TEST_TIMINGS=.build/unit3-focused.tsv ./scripts/swift-test-budget.sh --filter 'OuroMDUpdateCoordinatorTests|OuroMDUpdateInstallerTests|TerminationSaveCoordinatorTests'` | implemented |
| 12 | Web crash/reload smoke | `--editorsurfacetest` loads the real WebKit editor, invokes the termination delegate, waits for a fresh ready event, and asserts recovered Markdown is restored | `./scripts/run-native-scenarios.sh` | implemented |
| 13 | Large folders/deep/unusual/symlink | `FolderScanner` reports depth truncation/cancellation; tests cover deep cap, 5k budget, unusual names, duplicate basenames, and symlink traps | `swift-test-budget --filter 'FolderBrowserTests|ContentSearcherTests|FolderDisplayTests'` | implemented |
| 14 | Folder search UX edge cases | Search now exposes Cancel, cancelled state, skipped binary/unreadable counts, and truncation; tests cover cancellation plus binary/unreadable skips without path leakage | `swift-test-budget --filter 'FolderBrowserTests|ContentSearcherTests|FolderDisplayTests'`; `--uisurfacetest` in native scenarios | implemented |
| 15 | Drag/drop file open + image paste/drop | `EditorDropWebView` accepts Markdown/text file drops while images stay in JS; `--editorsurfacetest` synthesizes paste and drop image transfers and waits for data URI Markdown | `swift-test-budget --filter EditorWebViewTests`; `./scripts/run-native-scenarios.sh` | implemented |
| 16 | Pathological tables | `dogfood-wide-tables.md` now includes empty, alignment, HTML, URL, sparse, long-code, and stress-grid tables; `--tablewraptest` gates category coverage and geometry/overflow at 448/1000/1400px | `swift-test-budget --filter 'MarkdownRendererTests|TableLayoutPolicyTests'`; `./scripts/run-native-scenarios.sh` | implemented |
| 17 | Print/PDF export probe | `--editorsurfacetest` constructs a non-modal print operation and renders a PDF via WebKit, validating `%PDF` header and byte size | `./scripts/run-native-scenarios.sh` | implemented |
| 18 | HTML export snapshots all themes | `--editorsurfacetest` writes standalone HTML exports for all built-in themes and checks document wrapper, theme CSS, table/body content, and inlined image data | `./scripts/run-native-scenarios.sh` | implemented |
| 19 | Older-live to latest-live update e2e | `scripts/check-live-update-path.sh` installs an older published release into a temp bundle, then `--liveupdatetest` uses the real update feed/planner/installer/apply script to update it to latest; release workflow runs it after publish | `bash -n scripts/check-live-update-path.sh`; `./scripts/check-live-update-path.sh` verified live `0.9.14 -> 0.9.15`; release workflow `Verify published release and installer` runs `OURO_MD_LIVE_UPDATE_TO_VERSION=<version> ./scripts/check-live-update-path.sh` | implemented |
| 20 | Rollback after backup creation | `OuroMDUpdateInstaller.applyScript` restores backup if the replacement is not a valid app bundle; `web/ouro-md-install.sh` no longer swallows restore failures | focused installer tests plus `bash -n web/ouro-md-install.sh scripts/*.sh` | implemented |
| 21 | Cancellable/recoverable updater progress | `OuroMDUpdateCoordinator` owns manual install tasks with structured progress/cancel/retry; `UpdateProgressView` exposes Cancel/Retry controls | focused coordinator tests; `./scripts/run-native-scenarios.sh`; `--uisurfacetest` | implemented |
| 22 | First-launch blank/empty gate | `FirstLaunchTester` loads the bundled welcome document in a real offscreen WebKit window, asserts rendered welcome content, and counts nonblank snapshot pixels; `--firstlaunchtest` is wired into CLI help, `main.swift`, and native scenarios | `.build/debug/ouro-md --firstlaunchtest`; `OURO_VISUAL_ARTIFACT_DIR=.build/unit5-visual-artifacts ./scripts/run-native-scenarios.sh` | implemented |
| 23 | Command palette/searchable actions | `CommandPaletteCatalog`/`AppModel` add searchable actions and dispatch; `CommandPaletteView` renders responsive palette; Edit menu exposes `Shift-Command-P`; tests cover filtering, dispatch, shortcut, and validation | `OURO_TEST_LOG=.build/unit5-command-menu-rerun.log OURO_TEST_TIMINGS=.build/unit5-command-menu-rerun.tsv ./scripts/swift-test-budget.sh --filter 'CommandPaletteTests|UndoRedoRoutingTests'`; `--uisurfacetest`; native scenarios | implemented |
| 24 | Compact document stats/status | `DocumentStatusBar` overlays compact word/char/mode/theme/dirty state; `UISurfaceTest` verifies editor palette/status fitting and semantic status/palette state | `.build/debug/ouro-md --uisurfacetest`; `OURO_VISUAL_ARTIFACT_DIR=.build/unit5-visual-artifacts ./scripts/run-native-scenarios.sh` | implemented |
| 25 | Signing/notarization readiness | `scripts/check-signing-readiness.sh` verifies signing/notary tooling, credential shape, optional live validation, and fail-closed `OURO_REQUIRE_NOTARIZATION=1`; PR preflight, CI, release workflow, release policy, and README run/document it. Credentials are not configured locally and remain allowed until the require flag is enabled | `bash -n scripts/check-signing-readiness.sh scripts/pr-preflight.sh scripts/run-native-scenarios.sh`; `./scripts/check-signing-readiness.sh`; `OURO_REQUIRE_NOTARIZATION=1 ./scripts/check-signing-readiness.sh` fails closed as expected | implemented |

## Work Units

### Unit 0: Planning Gate

- [x] Planning reviewer converges.
- [x] Patch planning/doing docs after reviewer findings.
- [x] Commit docs.

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

- [x] Inject recents provider through `RecentMenuDelegate` and test without `NSDocumentController.shared`.
- [x] Extract/test title click-vs-drag decision.
- [x] Add app/file-open state tests for untitled, saved, renamed, and missing-file documents.
- [x] Add two-window tests for menu validation, theme/sidebar/search independence, save/rename targeting.
- [x] Extend `UISurfaceTest` for Preferences/search/update progress/menu layout and AX labels/actions/focus.
- [x] Add contrast and reduced-motion guardrails.

### Unit 3: Updater Cancellable Progress And Rollback

- [x] Introduce structured install progress state.
- [x] Add install cancellation while staging is in-flight.
- [x] Render Cancel/Retry/status affordances in update progress.
- [x] Add dirty-doc install quit-cancel test that prevents apply and preserves retry.
- [x] Harden one-line installer rollback verification.
- [x] Add forced post-backup rollback test/harness for apply script.

### Unit 4: Editor, Search, Folder, Tables, Image Transfer, Export

- [x] Extend large-folder/deep/unusual/symlink tests.
- [x] Add search truncation/cancel/binary/unreadable/permissions coverage.
- [x] Add `--imagetransfertest` or equivalent bridge transfer probe.
- [x] Extend pathological table fixture and table gate.
- [x] Add HTML export checks for all themes.
- [x] Add PDF/print export probe.
- [x] Add WebKit crash/reload headless smoke.

### Unit 5: Product Polish

- [x] Add first-launch nonblank/themed screenshot or pixel smoke.
- [x] Implement searchable command palette.
- [x] Add compact document stats/status surface.
- [x] Add signing/notarization readiness check and document hard exception if credentials unavailable.

### Unit 6: Verification, Review, Merge, Release

- [x] Run `git diff --check`.
- [x] Run targeted tests/probes for each changed unit.
- [x] Run `swift test`.
- [x] Run `./scripts/check-coverage.sh`.
- [x] Run app bundle verification.
- [x] Run PR preflight.
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
- 2026-06-21 10:25 Completed Unit 2 native UI/accessibility/open-flow layer. Validation: focused `DocumentWindowControllerTests|UndoRedoRoutingTests|AppDelegateWindowRoutingTests|ThemeAccessibilityTests` passed through `scripts/swift-test-budget.sh`; `./scripts/run-native-scenarios.sh` passed.
- 2026-06-21 10:41 Completed Unit 3 updater/rollback layer. Validation: `bash -n web/ouro-md-install.sh scripts/*.sh`, `git diff --check`, focused `OuroMDUpdateCoordinatorTests|OuroMDUpdateInstallerTests|TerminationSaveCoordinatorTests`, `--uisurfacetest`, and `./scripts/run-native-scenarios.sh` passed.
- 2026-06-21 10:57 Completed Unit 4 editor/search/folder/tables/export layer. Validation: focused `EditorWebViewTests`, focused `FolderBrowserTests|ContentSearcherTests|FolderDisplayTests`, focused `MarkdownRendererTests|TableLayoutPolicyTests`, `--editorsurfacetest`, dogfood tablewrap at 448/1000/1400px, `git diff --check`, and `./scripts/run-native-scenarios.sh` passed.
- 2026-06-21 11:15 Completed Unit 5 product polish layer. Validation: focused `CommandPaletteTests|UndoRedoRoutingTests`, `--firstlaunchtest`, `--uisurfacetest`, signing readiness normal/fail-closed checks, `git diff --check`, script syntax checks, and `./scripts/run-native-scenarios.sh` passed.
- 2026-06-21 11:23 Closed evidence row 19 with a permanent live-update gate. Validation: `bash -n scripts/check-live-update-path.sh`, `swift build`, `git diff --check`, and `./scripts/check-live-update-path.sh` passed against published releases `0.9.14 -> 0.9.15`.
- 2026-06-21 11:28 Bumped app version to 0.9.16 for app-affecting changes after confirming latest published release is v0.9.15.
- 2026-06-21 11:43 Completed local Unit 6 gates. Validation: `git diff --check`, focused unit probes, full timed XCTest through `scripts/swift-test-budget.sh` (239 tests, 0 failures), `./scripts/check-coverage.sh` (100% `OuroMDCore` line + region coverage), `OURO_VISUAL_ARTIFACT_DIR=.build/unit6-visual-artifacts ./scripts/run-native-scenarios.sh`, packaged `.app` verification, live update path check, and final `./scripts/pr-preflight.sh` all passed.
- 2026-06-21 12:12 Addressed final reviewer gate finding: PR freshness now normalizes `main`/`origin/main`/full ref names and fails hard on unresolved bases, `selftest-pr-base` is wired into local preflight and CI, and coverage/native scenario profiles are routed under `.build/`. Validation: `bash -n scripts/release-policy.sh scripts/check-coverage.sh scripts/pr-preflight.sh scripts/run-native-scenarios.sh`, `./scripts/release-policy.sh selftest-pr-base`, `./scripts/release-policy.sh freshness --mode pr --base-ref origin/main`, bogus base failure check, `git diff --check`, and final `OURO_PR_BASE_REF=origin/main ./scripts/pr-preflight.sh` passed; worktree root had no `default.profraw`.
- 2026-06-24 (closeout) Reconciled doc against `main` while resuming: all Units 0–5 + every acceptance-matrix artifact are present and live in `main`; the work shipped incrementally as PRs #26–45 (not the single-PR/reviewer-gate path Unit 6 describes), advancing the app from the target `0.9.16` to `0.9.35`. No stale branch/worktree/PR remains. Marked Status COMPLETE — shipped/superseded.
