# Planning: File Picker, Table Layout, And Brand Cleanup

**Status**: NEEDS_REVIEW
**Created**: 2026-06-20 09:44

## Goal
Make Ouro MD behave more like a trustworthy macOS document editor during dogfood: clicking the document title opens the standard file picker, large Markdown tables remain readable instead of collapsing or cropping, and all traces of the prohibited third-party editor brand are removed from repository content.

## Upstream Work Items
- None

## Scope

### In Scope
- Change native title/proxy-icon click behavior from inline rename to the standard Open panel path for the active document window.
- Preserve window dragging from the title bar and keep explicit rename available through File -> Rename.
- Rework live-editor table CSS so tables use natural column sizing, remain readable, and use horizontal table-level scrolling when the table is wider than the editor column instead of squeezing cells into unusable vertical fragments.
- Apply the same table policy to standalone HTML/PDF/export CSS so rendered output matches the editor.
- Expand table validation beyond the existing single synthetic wrap case using read-only fixtures from `/Users/arimendelow/Projects/spoonjoy-apple/tasks/2026-06-16-1754-doing-siri-full-access-parity.md`.
- Remove prohibited-brand references from source comments, docs, notices, release bundle metadata, and any generated app-visible strings in this repository.
- Add an automated repo scan that fails if the prohibited brand literal appears case-insensitively in tracked repository content.
- Validate with source tests/probes and a packaged-app or app-bundle smoke path sufficient to prove the title click and table behavior are not only source-level assumptions.

### Out of Scope
- Editing `/Users/arimendelow/Projects/spoonjoy-apple/tasks/2026-06-16-1754-doing-siri-full-access-parity.md`; it is read-only dogfood input.
- Removing Vditor or changing the editor engine.
- Replacing the File -> Rename command or the underlying `renameCurrentFile` behavior.
- Changing Markdown table source formatting or round-trip semantics.
- Changing telemetry payload policy beyond ensuring no prohibited-brand string is introduced.
- Developer ID signing, notarization, or release publishing.

## Completion Criteria
- [ ] Clicking the AppKit-rendered filename/proxy icon opens the same file picker behavior as File -> Open for the active window, including existing dirty-document discard protection.
- [ ] Dragging the title bar still moves the window instead of opening the picker.
- [ ] File -> Rename still opens the rename popover and all existing rename tests remain green.
- [ ] The dogfood doc's eight table shapes are covered by automated fixtures: small natural tables, medium multi-column ownership tables, endpoint lists, artifact/path tables, and very wide prose tables.
- [ ] Table tests prove no document-level horizontal cropping, no pathological column collapse, and intentional table-level overflow/scroll behavior when natural width exceeds the editor column.
- [ ] Editor CSS and exported HTML/PDF CSS share the same table policy.
- [ ] A case-insensitive prohibited-brand scan of tracked repo content returns no results.
- [ ] 100% test coverage on all new code.
- [ ] All tests pass.
- [ ] No warnings.

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code.
- All branches covered, including title-click vs title-drag behavior and dirty-document open-panel routing.
- All table classification/measurement branches covered, including natural-width, wide-scroll, long-token, inline-code/path, and prose-heavy cells.
- Error paths tested for any new scan/probe helper.
- Edge cases: untitled document title click, titled document title click, empty table cells, long unbroken inline-code content, and very wide prose cells.

## Open Questions
- [ ] None. The requested behavior is sufficiently specific: title click opens the file picker, the dogfood doc is read-only input, and the prohibited brand literal must not exist in repository content.

## Decisions Made
- Use branch `worker/file-picker-tables-brand-cleanup` in dedicated worktree `/Users/arimendelow/Projects/_worktrees/ouro-md-file-picker-tables-brand-cleanup`; clean up the worktree after completion.
- Treat the dogfood doc as a fixture source only; tests may copy representative table Markdown into repo-owned fixtures or generated test strings, but must never edit the live doing doc.
- Prefer a natural-width table model with table-level horizontal scrolling over forced full-width wrapping for every table, because the screenshots show both squeezed columns and cropped/wide tables as distinct failure modes.
- Keep explicit rename as a menu command rather than overloading title click; this preserves rename capability while matching the requested title-click file-picker behavior.
- Avoid writing the prohibited brand literal in new repo docs or tests; scan commands can construct the literal at runtime to avoid reintroducing the failing string into tracked files.

## Context / References
- `Sources/OuroMD/DocumentWindowController.swift`: title click currently calls `presentRename()` via `window.onTitleClicked`.
- `Sources/OuroMD/AppModel.swift`: `openPanel()` and `open(url:)` already implement the desired File -> Open path and dirty-document confirmation.
- `Sources/OuroMD/Themes.swift`: live editor and reader/export table CSS currently force `width:100%; max-width:100%` and aggressive word breaking.
- `Sources/OuroMD/TableWrapTest.swift`: existing synthetic table probe passes but only checks one long-token wrapping case.
- `/Users/arimendelow/Projects/spoonjoy-apple/tasks/2026-06-16-1754-doing-siri-full-access-parity.md`: read-only dogfood source with eight Markdown tables.
- Recent `origin/main` context: `f61bc83` added wide-table wrapping/open-file-window work; `394930e` switched narrow tables to auto layout.
- Current prohibited-brand scan hits before cleanup: `NOTICE`, `make-app.sh`, `README.md`, `ContentView.swift`, `Themes.swift`, `AppModel.swift`, `FolderBrowser.swift`, `Sidebar.swift`, `bridge.js`, `ContentSearcher.swift`, and `web/index.html`.

## Notes
- Dogfood table inventory: table 1 line 28 has 4 columns and path/test cells; table 5 line 178 has long artifact paths; table 6 line 188 has 4 prose-heavy columns with rows over 1,000 characters; table 7 line 202 has 2 huge prose columns.
- Existing `swift run ouro-md --tablewraptest` on 2026-06-20 built successfully and passed with `page horizontal overflow: 0.0px` and `table horizontal overflow: -1.0px`; this is useful baseline evidence but not sufficient table-layout coverage.
- The table fix should be validated visually or via DOM measurement against the same classes of table shown in the user screenshots, not just by checking that `scrollWidth <= clientWidth`.
- Tinfoil hat pass: the main hidden risk is accidentally satisfying overflow tests by over-wrapping text into unreadable columns. Completion criteria therefore require both no cropping and no pathological column collapse.

## Progress Log
- 2026-06-20 09:44 Created planning doc after source/dogfood grounding.
