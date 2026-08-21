# Doing: Reference-style link rendering and anchor navigation

**Status**: drafting
**Execution Mode**: direct
**Created**: 2026-08-21 12:30
**Planning**: ./2026-08-21-1214-planning-reference-links-and-anchors.md
**Artifacts**: ./2026-08-21-1214-doing-reference-links-and-anchors/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts only when the user explicitly requested interactive per-unit approval; otherwise convert this to `spawn` or `direct` unless a hard exception is present.
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous).
- **direct**: Execute units sequentially in the current task worktree because the link pipeline is one continuous JavaScript-to-Swift trace and the units share the same live WebKit harness.

## Objective
Make valid CommonMark reference-style links read and behave like links in every Ouro MD editor mode, and make heading-fragment links navigate reliably within the current document or a linked Markdown document without rewriting the author's source.

## Upstream Work Items
- None.

## Completion Criteria
- [ ] Full, collapsed, and shortcut reference-style links show only their rendered label in IR mode, with no adjacent reference identifier or syntax markers while focused.
- [ ] External reference-style links preserve Command-click browser opening, and relative Markdown reference-style links preserve normal-click in-app opening.
- [ ] Full, collapsed, and shortcut reference-style links resolve consistently in IR, WYSIWYG, Split/preview, `window.ouro.getHTML()` HTML/PDF export input, and standalone `--render` output.
- [ ] Same-document inline and reference-style fragment links scroll to the intended heading in IR, WYSIWYG, and Split/preview modes.
- [ ] Existing exact-ID anchors, including live footnote references and back-references, continue to navigate.
- [ ] `other.md#fragment` opens or activates the target document window and scrolls after that editor is ready.
- [ ] Heading anchors use the same normalization and duplicate suffixes in live-editor navigation and HTML/PDF output, including percent-encoded fragments.
- [ ] App HTML/PDF export input from `bridge.getHTML()` contains heading IDs under the shared anchor contract; this is tested independently from the pure `MarkdownRenderer` export harness.
- [ ] App-export heading-ID reconciliation changes only heading IDs and leaves Vditor/Lute footnote and back-reference IDs byte-unchanged.
- [ ] Source Code mode shows the original reference syntax and a no-edit open/save round trip remains byte-identical.
- [ ] Editing nearby prose does not rewrite or inline unrelated reference-style links.
- [ ] Undefined or malformed reference labels remain source text and do not become clickable or lose syntax markers.
- [ ] Existing inline external, bare autolink, and relative Markdown link behavior remains unchanged.
- [ ] Fragment lookup is safe for digit-leading and punctuation-bearing anchors, and document-controlled fragments cross the Swift-to-JavaScript boundary only through the existing JSON-string escaping helper.
- [ ] Fragment activation is handled exactly once, suppresses WebKit's default hash navigation, and leaves the bundled editor document URL unchanged.
- [ ] The headless link harness fails before the fix and passes after the fix for both reported defects.
- [ ] The shared `scripts/run-native-scenarios.sh` gate runs the expanded link harness and a reference-style round-trip fixture through its byte-for-byte `cmp`.
- [ ] Live visual evidence shows the reference identifier absent and anchor navigation landing on the intended heading; the visual absurdity ledger is closed.
- [ ] 100% test coverage on all new code.
- [ ] All tests pass.
- [ ] No warnings.

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code.
- Cover full, collapsed, shortcut, unresolved, escaped-label, normalized-label, titled, external, local Markdown, same-document fragment, and cross-document fragment references.
- Cover same-document, new-document, existing-document, missing-heading, malformed/encoded, digit-leading, punctuation-bearing, duplicate-heading, exact-ID, footnote, and back-reference anchor paths.
- Cover IR, WYSIWYG, Split/preview, Source Code round-trip, app `bridge.getHTML()` export input, standalone renderer, and PDF-producing parity paths.
- Keep unsupported schemes and unresolved targets fail-closed.
- Exercise the real WebKit/Vditor surface through shipped headless scenarios in addition to pure Swift tests.

## TDD Requirements
**Strict TDD — no exceptions:**
1. **Tests first**: Write failing tests BEFORE any implementation.
2. **Verify failure**: Run tests, confirm they FAIL for the expected missing behavior.
3. **Minimal implementation**: Write just enough code to pass.
4. **Verify pass**: Run tests, confirm they PASS.
5. **Refactor**: Clean up, keep tests green.
6. **No skipping**: Never write implementation without failing test first.

## Work Units

### Legend
⬜ Not started · 🔄 In progress · ✅ Done · ❌ Blocked

### ⬜ Unit 0: Baseline and fixture contract
**What**: Reproduce both defects at HEAD with a compact fixture containing full, collapsed, shortcut, unresolved, external, local Markdown, same-document fragment, duplicate-heading, encoded-fragment, footnote, and back-reference cases. Record the current IR DOM, `window.ouro.getHTML()` output, clicked-target routing, editor page URL, scroll positions, and byte-for-byte round-trip result.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/unit0-baseline.md` plus captured DOM/HTML snippets and screenshots.
**Acceptance**: The reference identifier is demonstrably exposed when its IR node is active; reference nodes have no direct `href`; fragment clicks fail to land on authored heading targets; app-export and standalone-render paths are distinguished; round-trip remains byte-identical.

### ⬜ Unit 1a: Reference-style links — Tests
**What**: Extend `Sources/OuroMD/LinkTest.swift`, `Tests/OuroMDTests/MarkdownRendererTests.swift`, and the shared round-trip fixture to assert full/collapsed/shortcut resolution, IR marker hiding while focused, parser-normalized labels/titles, external Command-click, local Markdown normal-click, unresolved fail-closed behavior, all live editor modes, app `getHTML()` output, standalone rendering, and source preservation.
**Output**: Failing reference-link regression coverage in the shipped harness and unit tests.
**Acceptance**: New assertions fail for the current missing IR presentation and destination-routing behavior while existing inline-link and round-trip assertions remain green.

### ⬜ Unit 1b: Reference-style links — Implementation
**What**: Update `Sources/OuroMD/web/index.html` and `Sources/OuroMD/web/bridge.js` so resolved `data-type="link-ref"` nodes keep reference syntax markers hidden in IR, and resolve their actual destinations from the checked-in Lute parser's structured output across IR/WYSIWYG/Split instead of parsing CommonMark reference definitions by regex. Feed the resolved target through the existing external/local/fragment gesture policy without mutating `state.value` or the Vditor document.
**Output**: Render-only reference-marker handling and parser-owned destination routing.
**Acceptance**: Unit 1a is green; unresolved references remain visibly editable and non-clickable; external/local gestures match inline-link behavior; `window.ouro.getValue()` remains byte-identical before and after clicks/focus changes.

### ⬜ Unit 1c: Reference-style links — Coverage and refactor
**What**: Add edge coverage for repeated labels, whitespace/case normalization, escaped labels, optional titles, missing definitions, malformed destinations, and definition blocks far from their uses. Cache parser-derived reference targets only against the exact current Markdown value and invalidate on every edit/reload/mode rebuild.
**Output**: Complete branch coverage and a single narrow reference-target helper in `bridge.js`.
**Acceptance**: 100% coverage on new Swift seams and explicit headless assertions for each JavaScript branch; no handwritten reference-definition parser; all link and round-trip tests remain green.

### ⬜ Unit 1d: Reference-style links — Visual QA dogfood
**What**: Run `visual-qa-dogfood` against focused and unfocused full/collapsed/shortcut references in IR, then inspect WYSIWYG, Split, and Source Code modes for absurd syntax leakage or loss of editability.
**Output**: Screenshots and `./2026-08-21-1214-doing-reference-links-and-anchors/reference-links-visual-absurdity-ledger.md`.
**Acceptance**: Only the rendered label is visible in IR even while focused; Source Code retains the original syntax; the absurdity ledger has no open ready or reviewer-gated items; automated visual metrics stay green.

### ⬜ Unit 2a: Anchor routing — Tests
**What**: Extend `Tests/OuroMDAppSupportTests/DocumentLinkTests.swift`, `Tests/OuroMDTests/EditorWebViewTests.swift`, `Tests/OuroMDTests/AppDelegateWindowRoutingTests.swift`, `Tests/OuroMDTests/MarkdownRendererTests.swift`, and `Sources/OuroMD/LinkTest.swift` for optional fragment preservation, safe Swift-to-JavaScript escaping, same-document scrolling in IR/WYSIWYG/Split, exact DOM IDs, footnotes/back-references, GitHub-style heading slugs, duplicate suffixes, encoded/digit-leading/punctuation fragments, missing headings, cross-document new/existing windows, editor-readiness ordering, one-shot gesture handling, and unchanged editor page URL.
**Output**: Failing pure and live anchor-navigation tests.
**Acceptance**: Tests fail on the current `.inDocumentAnchor` no-op, stripped file fragments, mode-specific heading IDs, missing app-export heading IDs, and WebKit default hash navigation without failing unrelated link routing.

### ⬜ Unit 2b: Anchor routing — Implementation
**What**: Make fragments first-class in `DocumentLinkTarget`, `DocumentLinkResolver`, `EditorWebView.Coordinator`, `AppModel`, and `AppDelegate`; preserve an optional fragment beside the standardized Markdown file URL; queue cross-document scrolling until the target editor has loaded/rendered; and add a bridge-owned anchor scroller that tries `getElementById` before the shared heading-slug map. Intercept fragment gestures once, suppress WebKit hash navigation, decode fragments safely, and pass native fragment strings through `Coordinator.jsString`.
**Output**: Same-document and cross-document anchor navigation with readiness-safe native/JavaScript handoff.
**Acceptance**: Unit 2a is green; missing anchors are harmless no-ops; unsupported schemes remain blocked; activating a fragment never changes the editor page URL or executes unescaped script.

### ⬜ Unit 2c: Anchor routing — Coverage and refactor
**What**: Centralize heading occurrence counting separately from base slug normalization, cover duplicate and empty-slug headings, and verify pending fragments are consumed once after open/reuse/recovery without contaminating subsequent document loads.
**Output**: Complete anchor-routing branch coverage and isolated slug/deduplication helpers.
**Acceptance**: 100% coverage on new Swift logic; headless coverage exercises JavaScript fallbacks; footnote IDs and back-reference targets remain unchanged.

### ⬜ Unit 2d: Anchor routing — Visual QA dogfood
**What**: Run `visual-qa-dogfood` with distant headings, duplicate headings, encoded fragments, and exact-ID footnotes in each rendered editor mode, including a cross-document jump.
**Output**: Before/after screenshots and `./2026-08-21-1214-doing-reference-links-and-anchors/anchors-visual-absurdity-ledger.md`.
**Acceptance**: Each jump lands with the intended heading visibly at the top of the reading region, no double-scroll or URL mutation occurs, and the absurdity ledger is closed with automated visual metrics green.

### ⬜ Unit 3a: Export anchor parity — Tests
**What**: Extend `Sources/OuroMD/MarkdownParityTest.swift`, `Sources/OuroMD/EditorSurfaceTest.swift`, `Tests/OuroMDTests/MarkdownRendererTests.swift`, and the live link harness to compare heading/reference output from `window.ouro.getHTML()` and `MarkdownRenderer.renderHTMLBody`. Assert shared heading IDs and duplicate suffixes while snapshotting non-heading Vditor/Lute footnote and back-reference IDs before reconciliation.
**Output**: Failing app-export and standalone-render parity tests that distinguish the two production paths.
**Acceptance**: Current app-export input fails the shared heading-ID contract; reference links already resolved by Lute remain resolved; tests prove a broad ID rewrite would regress footnotes.

### ⬜ Unit 3b: Export anchor parity — Implementation
**What**: Reconcile heading IDs only in the HTML returned by `window.ouro.getHTML()` using the same JavaScript heading contract as live navigation, without touching other `id`/`href` attributes. Update `MarkdownRenderer` to apply duplicate suffixes at heading-render time while leaving the generic base slug used by footnotes unchanged.
**Output**: Matching heading/reference contracts in app HTML/PDF input and standalone HTML/PDF rendering.
**Acceptance**: Unit 3a is green; only heading IDs change; footnote/back-reference IDs are byte-identical; app and standalone exports navigate repeated headings consistently.

### ⬜ Unit 3c: Export anchor parity — Coverage and refactor
**What**: Add parity fixtures for inline formatting in headings, Unicode, punctuation-only headings, duplicates, exact-ID footnotes, and reference links targeting external/local/fragment destinations.
**Output**: Complete export-path edge coverage without broad HTML rewriting.
**Acceptance**: 100% coverage on new Swift renderer state; live scenario assertions cover JavaScript export reconciliation; HTML and PDF generation remain green.

### ⬜ Unit 4: Integrated regression and preflight
**What**: Wire the reference/anchor fixtures into `scripts/run-native-scenarios.sh`, including its byte-for-byte round-trip `cmp`; run targeted Swift tests, `swift build`, the complete shared native scenarios and visual QA, `./scripts/check-shell-boundary.sh --selftest`, `./scripts/check-shell-boundary.sh`, vendor integrity, coverage, and `./scripts/pr-preflight.sh`. Inspect the full branch diff for vendor-file changes, unrelated files, and source-format churn.
**Output**: Green local CI-parity evidence under `./2026-08-21-1214-doing-reference-links-and-anchors/`, with final screenshots and command logs.
**Acceptance**: All completion criteria are evidenced; `scripts/check-vditor-vendor.sh` confirms no vendored Vditor files changed; the full preflight passes with no warnings; the diff contains only the planned integration, tests, harness updates, and task artifacts.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor.
- Commit after each phase (1a, 1b, 1c).
- Push after each unit complete.
- Run full test suite before marking a unit done.
- Run `visual-qa-dogfood` for Units 1d and 2d before declaring either behavior complete.
- Save every baseline, DOM/HTML snapshot, screenshot, test log, and final evidence file under `./2026-08-21-1214-doing-reference-links-and-anchors/`.
- Spawn a focused reviewer only if a unit uncovers a distinct blocker; keep the continuous link trace in direct mode.
- Update this doing doc and the planning doc immediately when evidence changes a decision.

## Progress Log
- 2026-08-21 12:30 Created from the approved planning doc.
