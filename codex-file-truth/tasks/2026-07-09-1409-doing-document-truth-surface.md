# Doing: Document Truth Surface

**Status**: drafting
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
- [ ] Native document title clicks no longer open the file picker and do not block AppKit document path/proxy behavior.
- [ ] Current document file truth is visible without opening the sidebar.
- [ ] File/git state labels are mechanical and correct for clean tracked, modified tracked, mixed staged/unstaged changes, untracked/not-in-git, and inaccessible/non-file cases covered by focused classification tests.
- [ ] Git unavailable, sandbox/inaccessible metadata, and non-repo files show honest fallback state without blocking normal editing.
- [ ] Commands exist for Reveal in Finder, Copy Path, Copy Relative Path, and Copy Git Diff Command, with disabled or fallback behavior when no current file/repo exists.
- [ ] Human edits saved to disk can be surfaced as "modified / visible in git diff" without writing any git state.
- [ ] No hidden metadata or formatting churn is introduced by the file truth work.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No warnings
- [ ] If UI/rendering/layout changed: `visual-qa-dogfood` evidence captured, absurdity ledger closed, and automated visual metrics still pass

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

### ⬜ Unit 0: Setup/Research
**What**: Confirm the source-owned title interception, command routing, status surface, and test targets before code edits.
**Output**: Notes in the artifact folder and no code changes.
**Acceptance**: Relevant files and validation commands are known; no hidden branch/worktree drift.

### ⬜ Unit 1a: Native Title Chrome - Tests
**What**: Replace tests that expect title-click-to-open-panel with failing tests that require no custom file-picker interception while preserving `representedURL`, edited, subtitle/deleted, and drag-friendly native chrome state.
**Acceptance**: Focused window-controller tests fail against the current implementation for the old title-click behavior.

### ⬜ Unit 1b: Native Title Chrome - Implementation
**What**: Remove the custom title-click open-panel hook and any now-dead hit-testing helpers while keeping existing chrome sync and ordinary window dragging.
**Acceptance**: Unit 1a tests pass, no new warnings.

### ⬜ Unit 1c: Native Title Chrome - Coverage & Refactor
**What**: Remove obsolete test/implementation seams and keep title chrome behavior covered by stable assertions.
**Acceptance**: Window-controller tests pass and no obsolete title-click code remains.

### ⬜ Unit 2a: File/Git Truth Model - Tests
**What**: Add failing tests for read-only classification of non-file, local/non-repo, tracked clean, tracked modified, mixed staged/unstaged changes, untracked, unavailable/inaccessible, label text, and command string helpers.
**Acceptance**: New model tests fail before implementation and cover all branches.

### ⬜ Unit 2b: File/Git Truth Model - Implementation
**What**: Add the smallest source-fit file truth model/provider with injected read-only git runner, honest fallback states, relative-path support, and no git mutation.
**Acceptance**: Unit 2a tests pass, no warnings, and failures degrade to unavailable/not-in-git instead of interrupting editing.

### ⬜ Unit 2c: File/Git Truth Model - Coverage & Refactor
**What**: Run focused coverage-oriented tests, trim unused abstractions, and verify every new branch/error path is exercised.
**Acceptance**: 100% coverage on new file truth code by test inspection and suite output remains green.

### ⬜ Unit 3a: File Truth Commands - Tests
**What**: Add failing tests for command palette items, menu validation where source-fit, copy path, copy relative path, copy git diff command, and reveal-in-Finder routing with no-current-file fallbacks.
**Acceptance**: Focused command tests fail against current catalog/model/menu behavior.

### ⬜ Unit 3b: File Truth Commands - Implementation
**What**: Wire command palette/menu actions to model commands using testable pasteboard and reveal hooks.
**Acceptance**: Unit 3a tests pass, command availability is honest for untitled/non-git documents, and commands do not write git state.

### ⬜ Unit 3c: File Truth Commands - Coverage & Refactor
**What**: Tighten command APIs and tests so copy/reveal behavior is deterministic and platform seams are isolated.
**Acceptance**: Command tests pass and no untested command branches remain.

### ⬜ Unit 4a: Sidebar-Free Document Truth UI - Tests
**What**: Add failing SwiftUI/accessibility tests for a compact document truth control visible without the sidebar/status bar dependency, with labels and menu actions exposed.
**Acceptance**: UI-facing tests fail before implementation.

### ⬜ Unit 4b: Sidebar-Free Document Truth UI - Implementation
**What**: Add a compact document truth control to the editor/status/title-adjacent surface using existing styling patterns, with a small action menu and honest labels.
**Acceptance**: Unit 4a tests pass, the control is visible without opening the sidebar, and it does not overlap editor content.

### ⬜ Unit 4c: Sidebar-Free Document Truth UI - Coverage & Refactor
**What**: Refine layout, accessibility strings, and status-bar interaction while keeping the control lightweight.
**Acceptance**: UI tests pass and source-fit review finds no dashboard/agent overreach.

### ⬜ Unit 4d: Sidebar-Free Document Truth UI - Visual QA Dogfood
**What**: Run screenshot-backed visual QA on the touched document surface with sidebar closed and status bar hidden/visible where applicable.
**Acceptance**: Screenshots/live evidence captured in artifacts, absurdity ledger closed, automated visual metrics still pass.

### ⬜ Unit 5: Full Native Validation, Review, Publish
**What**: Run full test/preflight/build/package/install validation, spawn harsh final reviewer gates, address findings, push/publish the branch or PR, and leave the app ready for user testing.
**Output**: Terminal evidence in this doing doc/artifacts, commits pushed, and a ready-to-test installed or launchable app.
**Acceptance**: All completion criteria checked, final reviewer gate converged, and no human-only blocker remains.

## Execution
- **TDD strictly enforced**: tests -> red -> implement -> green -> refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete when a remote is configured
- Run full test suite before marking unit done
- For UI/rendering/layout units, run `visual-qa-dogfood` before declaring the unit or task complete
