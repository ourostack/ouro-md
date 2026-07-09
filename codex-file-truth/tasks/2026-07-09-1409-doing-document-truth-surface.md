# Doing: Document Truth Surface

**Status**: in-progress
**Execution Mode**: direct
**Created**: 2026-07-09 14:22 -0700
**Planning**: ./2026-07-09-1409-planning-document-truth-surface.md
**Artifacts**: ./2026-07-09-1409-doing-document-truth-surface/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts only when the user explicitly requested interactive per-unit approval; otherwise convert this to `spawn` or `direct` unless a hard exception is present
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Make Ouro MD feel like a native macOS document editor that exposes the truth of the current file: where it lives, whether it is edited, and whether its saved edits are visible to other tools through plain file and git state. This solves the human-agent collaboration problem without adding an agent runner, sidebar dependency, hidden metadata, or heavy review UI.

## Upstream Work Items
- None

## Completion Criteria
- [x] Native document title clicks no longer open the file picker and do not block AppKit document path/proxy behavior.
- [x] Current document file truth is visible without opening the sidebar.
- [x] File/git state labels are mechanical and correct for clean tracked, modified tracked, mixed staged/unstaged changes, untracked/not-in-git, and inaccessible/non-file cases covered by focused classification tests.
- [x] Git unavailable, sandbox/inaccessible metadata, and non-repo files show honest fallback state without blocking normal editing.
- [x] Commands exist for Reveal in Finder, Copy Path, Copy Relative Path, and Copy Git Diff Command, with disabled or fallback behavior when no current file/repo exists.
- [x] Human edits saved to disk can be surfaced as "modified / visible in git diff" without writing any git state.
- [ ] No hidden metadata or formatting churn is introduced by the file truth work.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No warnings
- [x] If UI/rendering/layout changed: `visual-qa-dogfood` evidence captured, absurdity ledger closed, and automated visual metrics still pass

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
**What**: Confirm the source-owned title interception, command routing, status surface, and test targets before code edits.
**Output**: `2026-07-09-1409-doing-document-truth-surface/source-fit-notes.md`.
**Acceptance**: Relevant files and validation commands are known; no hidden branch/worktree drift. Evidence committed in `4749571`.

### ✅ Unit 1a: Native Title Chrome - Tests
**What**: Replace tests that expect title-click-to-open-panel with failing tests that require no custom file-picker interception while preserving `representedURL`, edited, subtitle/deleted, and drag-friendly native chrome state.
**Acceptance**: Focused window-controller tests fail against the current implementation for the old title-click behavior. Evidence: `2026-07-09-1409-doing-document-truth-surface/unit-1a-red.txt`.

### ✅ Unit 1b: Native Title Chrome - Implementation
**What**: Remove the custom title-click open-panel hook and any now-dead hit-testing helpers while keeping existing chrome sync and ordinary window dragging.
**Acceptance**: Unit 1a tests pass, no new warnings. Evidence: `swift test --filter DocumentWindowControllerTests` passed at 2026-07-09 14:26 -0700.

### ✅ Unit 1c: Native Title Chrome - Coverage & Refactor
**What**: Remove obsolete test/implementation seams and keep title chrome behavior covered by stable assertions.
**Acceptance**: Window-controller tests pass and no obsolete title-click code remains. Evidence: `swift test --filter DocumentWindowControllerTests` passed and scoped grep found no obsolete title-click hooks at 2026-07-09 14:27 -0700.

### ✅ Unit 2a: File/Git Truth Model - Tests
**What**: Add failing tests in the coverage-gated `OuroMDAppSupportTests` target for read-only classification of non-file, local/non-repo, tracked clean, tracked modified, mixed staged/unstaged changes, untracked, unavailable/inaccessible, label text, command availability, relative-path helpers, and shell-safe git diff command string helpers.
**Acceptance**: New model tests fail before implementation and cover all branches. Evidence: `2026-07-09-1409-doing-document-truth-surface/unit-2a-red.txt`.

### ✅ Unit 2b: File/Git Truth Model - Implementation
**What**: Add the smallest source-fit pure file truth model/provider to `Sources/OuroMDAppSupport` with injected read-only git runner, honest fallback states, relative-path support, and no git mutation.
**Acceptance**: Unit 2a tests pass, no warnings, and failures degrade to unavailable/not-in-git instead of interrupting editing. Evidence: `swift test --filter DocumentTruthTests` passed at 2026-07-09 14:30 -0700.

### ✅ Unit 2c: File/Git Truth Model - Coverage & Refactor
**What**: Run focused app-support tests and the repo coverage gate, trim unused abstractions, and verify every new branch/error path is exercised.
**Acceptance**: 100% coverage on new file truth support code under the existing `scripts/check-coverage.sh` gate, with focused tests still green. Evidence: `scripts/check-coverage.sh` passed with `DocumentTruth.swift` at 150/150 lines and 73/73 regions.

### ✅ Unit 2d: AppModel Truth Lifecycle - Tests
**What**: Add failing tests for `AppModel` refresh behavior on welcome/new, open/loadInitialFile, dirty edits, save/save-as/autosave-success path, rename, deleted/restored, external reload, and conflict resolution where testable without UI prompts.
**Acceptance**: AppModel lifecycle tests fail against current code or fail to compile because no published truth state exists. Evidence: `2026-07-09-1409-doing-document-truth-surface/unit-2d-red.txt`.

### ✅ Unit 2e: AppModel Truth Lifecycle - Implementation
**What**: Publish the latest document truth snapshot from `AppModel`, refresh it at every file lifecycle point, and overlay unsaved/deleted state without faking git certainty.
**Acceptance**: Unit 2d tests pass and saved human edits can surface as modified/visible in git diff after write without any git mutation. Evidence: `swift test --filter AppModelDocumentTruthTests` passed at 2026-07-09 14:39 -0700.

### ✅ Unit 2f: AppModel Truth Lifecycle - Coverage & Refactor
**What**: Tighten lifecycle refresh helpers and test seams so state transitions are explicit and non-flaky.
**Acceptance**: AppModel lifecycle tests pass, all new AppModel branches are exercised, and the truth state cannot remain stale after open/save/rename/delete/reload paths. Evidence: `swift test --filter 'DocumentTruthTests|AppModelDocumentTruthTests|AppModelReloadTests|AppModelDeletionTests'` passed 41 tests.

### ✅ Unit 3a: File Truth Commands - Tests
**What**: Add failing tests for command palette items, menu validation where source-fit, copy path, copy relative path, copy git diff command, and reveal-in-Finder routing with no-current-file fallbacks.
**Acceptance**: Focused command tests fail against current catalog/model/menu behavior. Evidence: `2026-07-09-1409-doing-document-truth-surface/unit-3a-red.txt`.

### ✅ Unit 3b: File Truth Commands - Implementation
**What**: Wire command palette/menu actions to model commands using testable pasteboard and reveal hooks.
**Acceptance**: Unit 3a tests pass, command availability is honest for untitled/non-git documents, and commands do not write git state. Evidence: focused command suite passed 15 tests and `swift build` passed.

### ✅ Unit 3c: File Truth Commands - Coverage & Refactor
**What**: Tighten command APIs and tests so copy/reveal behavior is deterministic and platform seams are isolated.
**Acceptance**: Command tests pass and no untested command branches remain. Evidence: broader command/menu suite passed 37 tests; `scripts/check-coverage.sh` passed 314 tests and pure support coverage stayed 100%; `swift build` passed. Also fixed a dirty Save As failure baseline bug surfaced by the coverage slow-test budget.

### ✅ Unit 4a: Sidebar-Free Document Truth UI - Tests
**What**: Add failing SwiftUI/accessibility tests for a compact document truth control visible without the sidebar/status bar dependency, with labels and menu actions exposed.
**Acceptance**: UI-facing tests fail before implementation. Evidence: `2026-07-09-1409-doing-document-truth-surface/unit-4a-red.txt`.

### ✅ Unit 4b: Sidebar-Free Document Truth UI - Implementation
**What**: Add a compact document truth control to the editor/status/title-adjacent surface using existing styling patterns, with a small action menu and honest labels.
**Acceptance**: Unit 4a tests pass, the control is visible without opening the sidebar, and it does not overlap editor content. Evidence: `swift run ouro-md --uisurfacetest`, `swift run ouro-md --accessibilityaudit`, and `swift build` passed.

### ✅ Unit 4c: Sidebar-Free Document Truth UI - Coverage & Refactor
**What**: Refine layout, accessibility strings, and status-bar interaction while keeping the control lightweight.
**Acceptance**: UI tests pass and source-fit review finds no dashboard/agent overreach. Evidence: harsh reviewer findings resolved; focused document truth/command/window suite passed 45 tests; `--uisurfacetest`, `--accessibilityaudit`, `swift build`, and `scripts/check-coverage.sh` passed with `DocumentTruth.swift` 169/169 lines and 82/82 regions.

### ✅ Unit 4d: Sidebar-Free Document Truth UI - Visual QA Dogfood
**What**: Run screenshot-backed visual QA on the touched document surface with sidebar closed and status bar hidden/visible where applicable.
**Acceptance**: Screenshots/live evidence captured in artifacts, absurdity ledger closed, automated visual metrics still pass. Evidence: `unit-4d-visual-ledger.md`, screenshot artifacts, native UI/Web visual QA logs, and harsh visual reviewer PASS committed in `af1e544`.

### ⬜ Unit 5: Full Native Validation, Review, Publish
**What**: Run full test/preflight/build/package/install validation, spawn harsh final reviewer gates, address findings, push/publish the branch or PR, and leave the app ready for user testing. Publish means branch/PR and local ready-to-test app unless release validation proves the repo's current terminal path requires a packaged release; it does not mean surprise App Store resubmission.
**Output**: Terminal evidence in this doing doc/artifacts, commits pushed, and a ready-to-test installed or launchable app.
**Acceptance**: All completion criteria checked, final reviewer gate converged, and no human-only blocker remains.

**Gate Matrix**:
- `swift test`
- `scripts/check-shell-boundary.sh`
- `scripts/check-coverage.sh`
- `scripts/pr-preflight.sh`
- `swift build -c release`
- package/install smoke from the repo-supported release path, captured in artifacts
- launch or scenario smoke of the built/installed app with the document truth surface visible
- final harsh reviewer gate on diff and validation evidence

## Execution
- **TDD strictly enforced**: tests -> red -> implement -> green -> refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete when a remote is configured
- Run full test suite before marking unit done
- For UI/rendering/layout units, run `visual-qa-dogfood` before declaring the unit or task complete

## Progress Log
- 2026-07-09 14:22 -0700 Doing doc drafted in `164d3a6`.
- 2026-07-09 14:27 -0700 Unit 0 source-fit notes captured in `4749571`.
- 2026-07-09 14:31 -0700 Doing-doc reviewer findings accepted: add lifecycle unit coverage, coverage-gated support target for pure truth logic, concrete validation gates, progress log, and scoped publish wording.
- 2026-07-09 14:25 -0700 Unit 1a red test confirmed: `swift test --filter DocumentWindowControllerTests` failed because the window still uses custom `DocumentWindow`.
- 2026-07-09 14:26 -0700 Unit 1b green test confirmed after removing active title-click interception: `swift test --filter DocumentWindowControllerTests` passed.
- 2026-07-09 14:27 -0700 Unit 1c cleanup passed: removed obsolete title-click helper type, updated stale fixture wording, focused title tests green, scoped grep found no obsolete hooks.
- 2026-07-09 14:29 -0700 Unit 2a red test confirmed: `swift test --filter DocumentTruthTests` failed because the file truth provider types do not exist yet.
- 2026-07-09 14:30 -0700 Unit 2b green test confirmed: `swift test --filter DocumentTruthTests` passed for pure file/git truth support model.
- 2026-07-09 14:34 -0700 Unit 2c coverage gate passed: `scripts/check-coverage.sh` reported `DocumentTruth.swift` 150/150 lines and 73/73 regions.
- 2026-07-09 14:36 -0700 Unit 2d red test confirmed: `swift test --filter AppModelDocumentTruthTests` failed because AppModel has no live document truth API yet.
- 2026-07-09 14:39 -0700 Unit 2e green test confirmed: `swift test --filter AppModelDocumentTruthTests` passed with live AppModel document truth refresh.
- 2026-07-09 14:41 -0700 Unit 2f lifecycle regression suite passed: `DocumentTruthTests|AppModelDocumentTruthTests|AppModelReloadTests|AppModelDeletionTests` ran 41 tests with no failures.
- 2026-07-09 14:44 -0700 Unit 3a red test confirmed: command tests failed because document truth commands/selectors are not wired yet.
- 2026-07-09 14:49 -0700 Unit 3b green test confirmed: focused command suite passed 15 tests and `swift build` completed cleanly.
- 2026-07-09 14:54 -0700 Unit 3c regression/coverage pass complete: command/menu suite passed 37 tests, `scripts/check-coverage.sh` passed 314 tests with pure support files at 100%, and failed dirty Save As no longer advances the saved-content baseline before a write succeeds.
- 2026-07-09 14:55 -0700 Unit 4a red UI checks confirmed: `--uisurfacetest` and `--accessibilityaudit` fail only because the sidebar-free document truth control is missing.
- 2026-07-09 14:57 -0700 Unit 4b green UI implementation confirmed: document truth control renders with status bar hidden, accessibility audit sees it, and `swift build` passed.
- 2026-07-09 15:11 -0700 Unit 4c review/refactor complete: harsh reviewer blocker on empty staged/untracked diff commands resolved with state-specific diff commands; visible copy changed to `File status`; control moved into a reserved bottom strip; coverage gate passed 315 tests with pure support targets at 100%.
- 2026-07-09 15:24 -0700 Unit 4d visual QA complete: native status-hidden/status-visible screenshots captured, rendered Markdown dogfood screenshots inspected, automated visual QA passed, and harsh visual reviewer returned PASS.
