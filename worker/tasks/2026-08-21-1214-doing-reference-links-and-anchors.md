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
**What**: Reproduce both defects at HEAD with the future authoritative fixture `Tests/Fixtures/reference-links-and-anchors.md`, containing full, collapsed, shortcut, unresolved, external, local Markdown, same-document fragment, duplicate-heading, encoded-fragment, footnote, and back-reference cases. Record the current resolved and unresolved IR DOM shapes, `window.ouro.getHTML()` output, clicked-target routing, editor page URL, scroll positions, and a newly measured byte-for-byte `--roundtrip` result from the source build rather than assuming the installed-app result still holds.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/unit0/baseline.md`, `ir-dom.json`, `app-export.html`, `standalone-export.html`, `reference-focused.png`, and `anchor-before.png`.
**Acceptance**: The reference identifier is demonstrably exposed when its resolved IR node is active; resolved nodes use `data-type="link-ref"` without a direct `href`; unresolved full/collapsed/shortcut references remain plain source text and do not become `link-ref` nodes; fragment clicks fail to land on authored heading targets; app-export and standalone-render paths are distinguished; round-trip fidelity is measured. A round-trip failure becomes a required red test for Unit 1 and is fixed in scope; the fixture is never narrowed merely to make the shared gate green.

### ⬜ Unit 1a: Reference-style links — Tests
**What**: Add the authoritative `Tests/Fixtures/reference-links-and-anchors.md`; add optional `--linktest-file` parsing in `Sources/OuroMD/main.swift`; make `Sources/OuroMD/LinkTest.swift` load that file instead of embedding a second fixture; add expected-red assertions for full/collapsed/shortcut IR presentation and destination routing across live modes; add expected-green characterization tests in `Tests/OuroMDTests/MarkdownRendererTests.swift` for swift-markdown's already-correct standalone reference resolution; and run the fixture through `--roundtrip` without wiring the shared gate yet. Treat round-trip as expected-green only if Unit 0 measured it green; otherwise keep it as a required red driver.
**Output**: Failing live reference-link regression coverage, green standalone-render characterization, the source-preservation fixture, and `./2026-08-21-1214-doing-reference-links-and-anchors/unit1a/red.log`.
**Acceptance**: The named expected-red LinkTest assertions fail for missing marker hiding and destination routing; expected-green renderer/round-trip assertions pass; existing inline links remain green.

### ⬜ Unit 1b: Reference-style links — Implementation
**What**: Update `Sources/OuroMD/web/index.html` and `Sources/OuroMD/web/bridge.js` so resolved `data-type="link-ref"` nodes keep reference syntax markers hidden in IR through CSS-only presentation rules, following the existing `.ouro-alert-marker` display-only precedent. On click, call `vditor.vditor.lute.RenderJSON(currentMarkdown())`, walk `NodeLink` entries with `LinkType == 3`, collect each child `NodeLinkDest` in document order, and join the clicked DOM node by its ordinal among the active editor root's `span[data-type="link-ref"]` nodes. Cache only the exact `{markdown, mode, orderedDestinations}` triple and invalidate it on input, `setValue`, `reloadValue`, and `rebuild`. Feed the resolved target through the existing external/local/fragment gesture policy without removing marker nodes, mutating `state.value`, or rewriting the Vditor document.
**Output**: Render-only reference-marker handling and parser-owned destination routing.
**Acceptance**: Unit 1a is green; unresolved references remain visibly editable and non-clickable; external/local gestures match inline-link behavior; `window.ouro.getValue()` remains byte-identical before and after clicks/focus changes.

### ⬜ Unit 1c: Reference-style links — Coverage and refactor
**What**: Add edge coverage for repeated labels, whitespace/case normalization, escaped labels, optional titles, missing definitions, malformed destinations, and definition blocks far from their uses. Cache parser-derived reference targets only against the exact current Markdown value and invalidate on every edit/reload/mode rebuild.
**Output**: Complete branch coverage and a single narrow reference-target helper in `bridge.js`.
**Acceptance**: 100% coverage on new Swift seams and explicit headless assertions for each JavaScript branch; no handwritten reference-definition parser; all link and round-trip tests remain green.

### ⬜ Unit 1d: Reference-style links — Visual QA dogfood
**What**: Add `Tests/Fixtures/reference-links-and-anchors.md` as a named case in `scripts/run-visual-qa.sh`, run `visual-qa-dogfood` against focused and unfocused full/collapsed/shortcut references in IR, then inspect WYSIWYG, Split, and Source Code modes for absurd syntax leakage or loss of editability.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/visual/reference-ir-focused.png`, `reference-ir-unfocused.png`, `reference-wysiwyg.png`, `reference-split.png`, `reference-source.png`, and `reference-links-visual-absurdity-ledger.md`.
**Acceptance**: Only the rendered label is visible in IR even while focused; Source Code retains the original syntax; the absurdity ledger has no open ready or reviewer-gated items; `OURO_VISUAL_ARTIFACT_DIR=worker/tasks/2026-08-21-1214-doing-reference-links-and-anchors/visual ./scripts/run-visual-qa.sh` is green.

### ⬜ Unit 2a: Heading-anchor contract fixture
**What**: Write the language-neutral heading contract before either implementation: base normalization, empty-slug fallback, duplicate suffix numbering, Unicode, inline formatting, punctuation-only, and digit-leading cases. Record the rationale and add machine-readable cases at `Sources/OuroMD/web/heading-anchor-contract.json`. Swift tests load it through `OuroResources.web("heading-anchor-contract", "json")`; `LinkTest.swift` reads the same bundled file and injects the cases into its JavaScript test hook using JSON string escaping. Runtime `bridge.js` implements the algorithm and never fetches the JSON from a `file://` page.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/anchor-contract.md` and `Sources/OuroMD/web/heading-anchor-contract.json`.
**Acceptance**: Every heading case has one expected ID; duplicate numbering is explicit; footnote ID behavior is explicitly excluded from heading deduplication; both later test suites can load the same fixture.

### ⬜ Unit 2b-i: Same-document anchors — Tests
**What**: Extend `Tests/OuroMDTests/EditorWebViewTests.swift` with a pure `EditorWebView.Coordinator.anchorScript(fragment:)` escaping seam, and extend `Sources/OuroMD/LinkTest.swift` for IR/WYSIWYG/Split same-document fragments, exact DOM IDs, footnotes/back-references, injected contract-fixture heading cases, encoded/digit-leading/punctuation fragments, duplicates, missing headings, one-shot gesture handling, and unchanged editor page URL. Keep live URL stability out of the nil-web-view unit test and keep app-export/standalone-render ID assertions in Unit 3a.
**Output**: Failing same-document anchor tests and `./2026-08-21-1214-doing-reference-links-and-anchors/unit2b-i/red.log`.
**Acceptance**: Tests fail on the current `.inDocumentAnchor` no-op, mode-specific generated heading IDs, and WebKit default hash navigation while unrelated link routing stays green.

### ⬜ Unit 2b-ii: Same-document anchors — Implementation
**What**: Make `bridge.js` the sole owner of same-document fragment activation: it resolves and scrolls locally, calls `preventDefault`/`stopImmediatePropagation`, and never posts `#fragment` to Swift. The existing `.inDocumentAnchor` branch remains a defensive no-op for direct native calls. Add a bridge-owned scroller that tries `getElementById` before the contract heading-slug map, decode fragments safely, and keep `EditorWebView.Coordinator.anchorScript(fragment:)` only for native cross-document handoff through `Coordinator.jsString`.
**Output**: Same-document anchor navigation in `Sources/OuroMD/web/bridge.js` and `Sources/OuroMD/EditorWebView.swift`.
**Acceptance**: Unit 2b-i is green; missing anchors are harmless no-ops; exact-ID footnotes still work; no document-controlled fragment is interpolated as JavaScript source.

### ⬜ Unit 2b-iii: Same-document anchors — Coverage and refactor
**What**: Centralize JavaScript heading occurrence counting separately from base slug normalization, expose a deterministic test hook, inject all conformance cases from the bundled shared fixture through `LinkTest.swift`, and cover empty-slug and fallback paths without runtime fetch/XHR.
**Output**: Complete same-document JavaScript branch coverage and isolated anchor helpers.
**Acceptance**: Headless coverage exercises every lookup branch; footnote/back-reference IDs remain unchanged; the editor page URL remains stable after every fragment activation.

### ⬜ Unit 2c-i: Cross-document fragments — Tests
**What**: Extend `Tests/OuroMDAppSupportTests/DocumentLinkTests.swift`, `Tests/OuroMDTests/EditorWebViewTests.swift`, and `Tests/OuroMDTests/AppDelegateWindowRoutingTests.swift` for the fragment-carrying Markdown-file target, relative/absolute/file URLs, encoded fragments, existing-window reuse, new-window creation, sandbox-granted targets, readiness ordering, recovery, missing headings, and one-shot pending-fragment consumption.
**Output**: Failing cross-document fragment tests and `./2026-08-21-1214-doing-reference-links-and-anchors/unit2c-i/red.log`.
**Acceptance**: Tests fail because the current public target enum drops file fragments and window routing has no readiness-safe scroll handoff.

### ⬜ Unit 2c-ii: Cross-document fragments — Implementation
**What**: Change `DocumentLinkTarget`, `DocumentLinkResolver`, `EditorWebView.Coordinator`, `AppModel`, and `AppDelegate` to preserve an optional fragment beside the standardized Markdown file URL and pass it through sandbox/existing/new-window paths. `AppModel.editorDidBecomeReady()` is the readiness signal: after it applies `pendingMarkdown`, it consumes one pending fragment through the bridge's two-animation-frame anchor script; already-ready existing windows schedule the same script immediately.
**Output**: Readiness-safe native fragment propagation across document windows.
**Acceptance**: Unit 2c-i is green; unsupported schemes remain blocked; existing and new target windows consume the requested fragment exactly once.

### ⬜ Unit 2c-iii: Cross-document fragments — Coverage and refactor
**What**: Cover fragment consumption after open, reuse, web-content recovery, missing target, cancelled sandbox grant, and subsequent unrelated document loads; remove duplicate pending-state paths.
**Output**: Complete cross-document Swift branch coverage and one pending-fragment mechanism.
**Acceptance**: 100% coverage on new Swift routing; no stale fragment contaminates later opens; all same-document tests remain green.

### ⬜ Unit 2d: Anchor routing — Visual QA dogfood
**What**: Run `visual-qa-dogfood` with the authoritative fixture's distant headings, duplicate headings, encoded fragments, and exact-ID footnotes in each rendered editor mode, including a cross-document jump.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/visual/anchor-ir-before.png`, `anchor-ir-after.png`, `anchor-wysiwyg-after.png`, `anchor-split-after.png`, `anchor-cross-document-after.png`, and `anchors-visual-absurdity-ledger.md`.
**Acceptance**: Each jump lands with the intended heading visibly at the top of the reading region, no double-scroll or URL mutation occurs, the absurdity ledger is closed, and `OURO_VISUAL_ARTIFACT_DIR=worker/tasks/2026-08-21-1214-doing-reference-links-and-anchors/visual ./scripts/run-visual-qa.sh` remains green.

### ⬜ Unit 3a: Export anchor parity — Tests
**What**: Extend `Sources/OuroMD/MarkdownParityTest.swift`, `Sources/OuroMD/EditorSurfaceTest.swift`, `Tests/OuroMDTests/MarkdownRendererTests.swift`, and the live link harness to load `heading-anchor-contract.json` and compare heading/reference output from `window.ouro.getHTML()` and `MarkdownRenderer.renderHTMLBody`. Assert shared heading IDs and duplicate suffixes while snapshotting non-heading Vditor/Lute footnote and back-reference IDs before reconciliation.
**Output**: Failing app-export and standalone-render parity tests that distinguish the two production paths.
**Acceptance**: Current app-export input fails the shared heading-ID contract; reference links already resolved by Lute remain resolved; tests prove a broad ID rewrite would regress footnotes.

### ⬜ Unit 3b: Export anchor parity — Implementation
**What**: Reconcile heading IDs only in the HTML returned by `window.ouro.getHTML()` using the same JavaScript heading contract as live navigation, without touching other `id`/`href` attributes. Update `MarkdownRenderer` to apply duplicate suffixes at heading-render time while leaving the generic base slug used by footnotes unchanged.
**Output**: Matching heading/reference contracts in app HTML/PDF input and standalone HTML/PDF rendering.
**Acceptance**: Unit 3a is green; only heading IDs change; footnote/back-reference IDs are byte-identical; app and standalone exports emit identical IDs for every shared contract case.

### ⬜ Unit 3c: Export anchor parity — Coverage and refactor
**What**: Add parity fixtures for inline formatting in headings, Unicode, punctuation-only headings, duplicates, exact-ID footnotes, and reference links targeting external/local/fragment destinations.
**Output**: Complete export-path edge coverage without broad HTML rewriting.
**Acceptance**: 100% coverage on new Swift renderer state; live scenario assertions cover JavaScript export reconciliation; HTML and PDF generation remain green.

### ⬜ Unit 4a: Shared scenario gate — Tests
**What**: Add a top-level `fixtures` entry to `docs/shipped-cli-and-harness-policy.json` with `path: "Tests/Fixtures/reference-links-and-anchors.md"` and `requiredInvocations` containing the exact `scripts/run-native-scenarios.sh` substrings `--linktest --linktest-file Tests/Fixtures/reference-links-and-anchors.md`, `--roundtrip Tests/Fixtures/reference-links-and-anchors.md`, and the matching `cmp` command. Extend `scripts/check-shipped-harness-policy.sh` to require the fixture file to exist and every declared substring to occur in its declared script, then run the policy check before editing the scenario script.
**Output**: Failing harness-policy assertion and `./2026-08-21-1214-doing-reference-links-and-anchors/unit4a/red.log`.
**Acceptance**: The policy check fails only because the shared native scenario gate does not yet own the new byte-preservation fixture.

### ⬜ Unit 4b: Shared scenario gate — Implementation
**What**: Wire the authoritative fixture into `scripts/run-native-scenarios.sh` through `--linktest --linktest-file Tests/Fixtures/reference-links-and-anchors.md`, then add the required `--roundtrip`/`cmp` invocation without duplicating fixture content in shell.
**Output**: Green shared harness policy and native scenario gate.
**Acceptance**: Unit 4a is green; the same gate runs in local preflight, CI, and packaged-app verification; fixture source remains byte-identical.

### ⬜ Unit 4c: Integrated regression and preflight
**What**: Run targeted Swift tests, `swift build`, the complete shared native scenarios and visual QA, `./scripts/check-shell-boundary.sh --selftest`, `./scripts/check-shell-boundary.sh`, `./scripts/check-vditor-vendor.sh`, coverage, and `./scripts/pr-preflight.sh`. Inspect the full branch diff for vendor-file changes, unrelated files, and source-format churn.
**Output**: Green local CI-parity evidence under `./2026-08-21-1214-doing-reference-links-and-anchors/final/`, with final screenshots and command logs.
**Acceptance**: All completion criteria are evidenced; vendor integrity confirms no files under `Sources/OuroMD/web/vditor/` changed; the full preflight passes with no warnings; the diff contains only the planned integration, tests, harness updates, shared fixtures, and task artifacts.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor.
- Commit after Unit 0 and every lettered or roman-numeral phase in Units 1-4; each red test phase, implementation phase, coverage/refactor phase, visual QA phase, gate-wiring phase, and terminal preflight has its own commit.
- Push after each unit complete.
- Run full test suite before marking a unit done.
- Run `visual-qa-dogfood` for Units 1d and 2d before declaring either behavior complete.
- Save every baseline, DOM/HTML snapshot, screenshot, test log, and final evidence file under `./2026-08-21-1214-doing-reference-links-and-anchors/`.
- Spawn a focused reviewer only if a unit uncovers a distinct blocker; keep the continuous link trace in direct mode.
- Update this doing doc and the planning doc immediately when evidence changes a decision.

## Progress Log
- 2026-08-21 12:30 Created from the approved planning doc.
- 2026-08-21 12:36 Granularity pass split same-document and cross-document anchors, added the shared heading contract fixture, named exact artifacts, separated gate wiring from terminal preflight, and clarified red/green and commit boundaries.
- 2026-08-21 12:42 Source-validation pass made reference round-trip a measured in-scope gate, defined non-fetch contract injection, corrected unit/live test seams, constrained marker hiding to CSS, and routed harness ownership through the policy JSON.
- 2026-08-21 12:47 Ambiguity pass fixed parser-to-DOM correlation, unresolved-reference preconditions, single-owner same-document routing, authoritative fixture loading, readiness signaling, policy schema, and exact visual artifacts.
