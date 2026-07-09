# Planning: Document Truth Surface

**Status**: drafting
**Created**: pending initial commit

## Goal
Make Ouro MD feel like a native macOS document editor that exposes the truth of the current file: where it lives, whether it is edited, and whether its saved edits are visible to other tools through plain file and git state. This solves the human-agent collaboration problem without adding an agent runner, sidebar dependency, hidden metadata, or heavy review UI.

## Upstream Work Items
- None

**DO NOT include time estimates (hours/days) — planning should focus on scope and criteria, not duration.**

## Scope

### In Scope
- Restore native document-title behavior by removing Ouro MD's custom title-click-to-open-panel interception while preserving ordinary window dragging.
- Preserve AppKit document chrome: `representedURL`, edited state, document proxy/path behavior, and deleted marker behavior.
- Add main-surface file truth UI that does not require the sidebar, using a small document-state surface attached to the editor/status area or titlebar-adjacent chrome.
- Add read-only file/git state detection for the current document: local file, tracked, clean, modified, mixed changes, not in git, and unavailable/inaccessible state where applicable.
- Add commands/menu/palette actions for Reveal in Finder, Copy Path, Copy Relative Path, and Copy Git Diff Command.
- Keep git integration read-only and mechanical; no commits, staging, branch management, agent sessions, or hidden protocol state.
- Add focused tests for native title behavior, command availability, file-state classification, clipboard/reveal command behavior where testable, and UI/accessibility strings.
- Run native Swift tests, shell-boundary preflight, app build/package/install validation, and screenshot-backed visual QA for the document truth surface.

### Out of Scope
- Built-in agents, model calls, agent chat, MCP control, agent orchestration, or task execution.
- Sidebar-required workflows. Sidebar highlighting may remain useful when open, but must not be required for file truth.
- Comment threads, accept/reject review flows, semantic diffs, rendered diffs, or review dashboards.
- Staging, committing, branching, stashing, checkout, or any destructive git operation.
- Hidden document metadata, sidecars as source of truth, frontmatter mutation, or proprietary feedback markers.
- App Store resubmission for this change unless release/publish validation proves it is the repo's current terminal path.

## Completion Criteria
- [ ] Native document title clicks no longer open the file picker and do not block AppKit document path/proxy behavior.
- [ ] Current document file truth is visible without opening the sidebar.
- [ ] File/git state labels are mechanical and correct for clean tracked, modified tracked, untracked/not-in-git, and inaccessible/non-file cases covered by tests.
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

## Open Questions
- [ ] None requiring human input. Native surface placement will be decided by source-fit and reviewer gates.

## Decisions Made
- The primary product primitive is "file truth", not "agent features"; agent value comes from making plain-file and git state obvious.
- The sidebar must remain optional; file truth belongs in native document chrome, status/title-adjacent surface, menus, and command palette.
- Git behavior is read-only and local. Ouro MD may detect and explain state, but must not mutate repositories.
- Source diff remains the collaboration contract. Rendered or semantic diff views are deferred.
- AppKit document affordances should be preferred over custom chrome wherever possible.

## Context / References
- `Sources/OuroMD/DocumentWindowController.swift`: current custom title-click interception and document chrome sync.
- `Sources/OuroMD/AppModel.swift`: current document state, file loading/saving, autosave, command-palette dispatch, external reload handling.
- `Sources/OuroMD/Sidebar.swift`: current editor pane, status bar, command palette, sidebar file UI.
- `Sources/OuroMDAppSupport/CommandPaletteCatalog.swift`: command catalog.
- `Sources/OuroMD/AppDelegate.swift`: menu actions and validation.
- `Tests/OuroMDTests/DocumentWindowControllerTests.swift`: current tests encode title-click-to-open-panel behavior that must change.
- `Tests/OuroMDTests/AppModelReloadTests.swift`: external agent/human file-change loop coverage.
- AppKit `NSWindow.representedURL` / `isDocumentEdited` behavior from local SDK headers.

## Notes
The implementation should feel boringly native first. The custom document truth UI should be small, calm, and secondary to system document chrome.

## Progress Log
- pending initial commit Created
