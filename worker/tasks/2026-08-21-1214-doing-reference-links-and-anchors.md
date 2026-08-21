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
- All reference-link variants, label-normalization cases, resolved titles, and destination categories are covered.
- All anchor-routing branches are covered: same document, new document, existing document, missing heading, malformed/encoded fragment, digit-leading fragment, punctuation-bearing fragment, and duplicate heading.
- Error and unsupported-target paths remain fail-closed and are covered.
- The real WebKit/Vditor surface is exercised by the headless harness in addition to pure Swift tests.

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
**What**: Land the authoritative `Tests/Fixtures/reference-links-and-anchors.md`, with reference definitions at document end, containing full, collapsed, shortcut, unresolved, external, local Markdown, same-document fragment, duplicate-heading, encoded-fragment, footnote, and back-reference cases. Add `argValue("--linktest-file")` and `argValue("--linktest-artifact-dir")` seams in `Sources/OuroMD/main.swift`; update the `--linktest` privacy text in `docs/shipped-cli-and-harness-policy.json` for both caller-provided input and caller-directed screenshots/DOM/HTML output; and refactor `LinkTest.swift` from one `didStart`/hardcoded scenario into an explicit phase queue that can survive Vditor mode rebuilds, load an optional fixture, preserve the legacy no-argument scenario, and unconditionally capture diagnostics when an artifact directory is provided. Export `OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS` near the top of `scripts/run-native-scenarios.sh`, run both legacy and fixture-driven link tests through `run_with_timeout "$OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS"`, and derive LinkTest's internal phase deadline as a bounded fraction of that same environment value with last-phase diagnostics. Reproduce both defects without adding pass/fail assertions yet, then capture the raw Vditor Markdown value directly for byte comparison.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/unit0/baseline.md`, `ir-dom.json`, `app-export.html`, `standalone-export.html`, `reference-focused.png`, and `anchor-before.png`.
**Acceptance**: The two optional file arguments use `argValue`, not `hasFlag`, so they do not become new policy modes; policy privacy text covers caller input and artifacts; legacy `--linktest` still passes; fixture-driven baseline phases complete across rebuilds without the old one-ready gate swallowing them; inner/outer timeouts share one declared budget and cannot race silently; diagnostic artifacts are produced on a green process exit. The reference identifier is exposed when its resolved IR node is active; resolved nodes use `data-type="link-ref"` without a direct `href`; unresolved references remain plain source text; fragment clicks fail to land; `window.ouro.getHTML()` is recorded separately in IR/WYSIWYG/Split so existing heading-ID behavior is evidence, not assumption; raw Vditor and bridge `getValue()` values are compared directly with the input bytes before any `MarkdownTidy` normalization. If clean-buffer raw round-trip fails, stop before implementation and redesign source preservation; do not echo `state.value`, narrow the fixture, modify vendored Vditor, or land a partial fix.

### ⬜ Unit 1a: Reference-style links — Tests
**What**: Extend the Unit 0 `LinkTest.swift` phase queue with expected-red assertions for full/collapsed/shortcut IR presentation and destination routing across live modes, while retaining the legacy inline-link phase; add expected-green characterization tests in `Tests/OuroMDTests/MarkdownRendererTests.swift` for swift-markdown's already-correct standalone reference resolution; and run the authoritative fixture through `--roundtrip` without wiring the shared gate yet. Make `RoundTrip.swift` fail before `MarkdownTidy.roundTripProbeOutput` unless raw `window.__ouroEditor.getValue()` and `window.ouro.getValue()` both equal the original input; extract the byte-comparison helper and unit-test that a normalization-maskable blank-line/table-separator mismatch is rejected. Add keyboard-caret and mouse-focus phases plus an edit-fidelity phase that types inside a marker-hidden label and verifies both raw/bridge values preserve reference syntax, definition, and destination.
**Output**: Failing live reference-link regression coverage, green standalone-render characterization, the source-preservation fixture, and `./2026-08-21-1214-doing-reference-links-and-anchors/unit1a/red.log`.
**Acceptance**: The named expected-red LinkTest assertions fail for missing marker hiding and destination routing; expected-green renderer/round-trip assertions pass; existing inline links remain green.

### ⬜ Unit 1b: Reference-style links — Implementation
**What**: Extend the existing `resolveEditorLinkURL()` path used by both capture-phase `mousedown` and `click`; do not add a click-only reference handler. Update `Sources/OuroMD/web/index.html` and `Sources/OuroMD/web/bridge.js` so resolved `data-type="link-ref"` nodes keep reference syntax markers hidden in IR with explicit `display`, `height`, `width`, and `overflow` overrides under `.vditor-ir__node--expand`, while marker nodes remain in the DOM for serialization/editing. CSS is the load-bearing protection for mouse, keyboard-caret, and programmatic focus; capture-phase propagation control is only a WYSIWYG behavior guard. Call `vditor.vditor.lute.RenderJSON(currentMarkdown())`, walk `NodeLink` entries with `LinkType == 3`, decode each parser-normalized `LinkRefLabel`, and map it to the child `NodeLinkDest` plus recursively flattened `NodeLinkText`. Resolve WYSIWYG nodes by `data-link-label`; resolve full IR references from `.vditor-ir__marker--link`; resolve collapsed/shortcut IR references from their visible label, applying only CommonMark label trim/whitespace-collapse/case-fold normalization before lookup. If a label is absent, ambiguous, or disagrees with the AST link text, fail closed without opening. Cache only the exact `{markdown, mode, normalizedReferenceMap}` triple and invalidate it on input, `setValue`, `reloadValue`, and `rebuild`; never substitute cached source for current Vditor serialization.
**Output**: Render-only reference-marker handling and parser-owned destination routing.
**Acceptance**: Unit 1a is green; external reference links still open from the existing Command-mousedown path; plain external-reference clicks do not open or expose a raw reference identifier; unresolved references remain visibly editable and non-clickable; every destination is selected by a parser-normalized label key; absent/ambiguous/mismatched keys are no-ops; label editing preserves reference syntax and destination; `window.ouro.getValue()` remains byte-identical before/after clicks and focus changes.

### ⬜ Unit 1c: Reference-style links — Coverage and refactor
**What**: Add edge coverage for repeated labels, whitespace/case normalization, escaped labels, optional titles, missing definitions, malformed destinations, definition blocks far from their uses, ambiguous normalized labels, and a synthetic DOM label that does not exist in the AST map. Cache parser-derived reference targets only against the exact current Markdown value and mode, and invalidate on every edit/reload/mode rebuild.
**Output**: Complete branch coverage and a single narrow reference-target helper in `bridge.js`.
**Acceptance**: 100% coverage on new Swift seams and explicit headless assertions for each JavaScript branch; no handwritten reference-definition parser; all link and round-trip tests remain green.

### ⬜ Unit 1d: Reference-style links — Visual QA dogfood
**What**: Run the extended `--linktest` with `--linktest-file Tests/Fixtures/reference-links-and-anchors.md --linktest-artifact-dir worker/tasks/2026-08-21-1214-doing-reference-links-and-anchors/visual` so `WKWebView.takeSnapshot` captures focused/unfocused IR, WYSIWYG, Split, and Source Code states unconditionally. Also add the authoritative fixture as a static metrics case in `scripts/run-visual-qa.sh` and run `visual-qa-dogfood`.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/visual/reference-ir-focused.png`, `reference-ir-unfocused.png`, `reference-wysiwyg.png`, `reference-split.png`, `reference-source.png`, and `reference-links-visual-absurdity-ledger.md`.
**Acceptance**: Only the rendered label is visible in IR even while focused; Source Code retains the original syntax; the absurdity ledger has no open ready or reviewer-gated items; `OURO_VISUAL_ARTIFACT_DIR=worker/tasks/2026-08-21-1214-doing-reference-links-and-anchors/visual ./scripts/run-visual-qa.sh` is green.

### ⬜ Unit 2a: Heading-anchor contract fixture
**What**: Write the language-neutral heading contract before either implementation: base normalization, empty-slug fallback, duplicate suffix numbering, Unicode, inline formatting, punctuation-only, and digit-leading cases. Record the rationale and add machine-readable cases at `Sources/OuroMD/web/heading-anchor-contract.json`. Swift unit tests read the source fixture by a `#filePath`-relative repository path, avoiding a `Bundle.module` fatal path; `LinkTest.swift` separately loads the same file through `OuroResources.web("heading-anchor-contract", "json")`, proving packaged resource inclusion, and injects cases into JavaScript with JSON string escaping. Runtime `bridge.js` implements the algorithm and never fetches JSON from a `file://` page.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/anchor-contract.md` and `Sources/OuroMD/web/heading-anchor-contract.json`.
**Acceptance**: Every heading case has one expected ID; duplicate numbering is explicit; footnote ID behavior is explicitly excluded from heading deduplication; both later test suites can load the same fixture.

### ⬜ Unit 2b-i: Same-document anchors — Tests
**What**: Extend `Tests/OuroMDTests/EditorWebViewTests.swift` with a pure `EditorWebView.Coordinator.anchorScript(fragment:)` escaping seam, and extend `Sources/OuroMD/LinkTest.swift` for inline and reference-style destinations targeting IR/WYSIWYG/Split same-document fragments, exact DOM IDs, footnotes/back-references, injected contract-fixture heading cases, encoded/digit-leading/punctuation fragments, duplicates, missing headings, one-shot gesture handling, and unchanged editor page URL. Keep live URL stability out of the nil-web-view unit test and keep app-export/standalone-render ID assertions in Unit 3a.
**Output**: Failing same-document anchor tests and `./2026-08-21-1214-doing-reference-links-and-anchors/unit2b-i/red.log`.
**Acceptance**: Tests fail on the current `.inDocumentAnchor` no-op, mode-specific generated heading IDs, and WebKit default hash navigation while unrelated link routing stays green.

### ⬜ Unit 2b-ii: Same-document anchors — Implementation
**What**: Make `bridge.js` the sole owner of same-document fragment activation: branch on `#fragment` immediately after target resolution and before the external/local `metaKey` gate or shared `lastLinkOpenAt` dedupe; act only on the `click` event; call `preventDefault`/`stopImmediatePropagation`; scroll once; and never post the fragment to Swift. The existing `.inDocumentAnchor` branch remains a defensive no-op. Scope lookup and scrolling to the clicked link's nearest `.vditor-reset` root so Split targets its preview container; use `activeEditorRoot()` only for native cross-document handoff. Resolve authored heading fragments through the contract heading map first; only if no contract heading matches, use `getElementById` for a non-heading exact-ID element such as a footnote/back-reference, never for Vditor's mode-specific generated heading IDs. Decode fragments safely, use the target element's `scrollIntoView` so Vditor owns Split synchronization, and keep `EditorWebView.Coordinator.anchorScript(fragment:)` only for native handoff through `Coordinator.jsString`.
**Output**: Same-document anchor navigation in `Sources/OuroMD/web/bridge.js` and `Sources/OuroMD/EditorWebView.swift`.
**Acceptance**: Unit 2b-i is green; the same fragment lands on the same logical heading in IR/WYSIWYG/Split despite any Lute-generated preview IDs; missing anchors are harmless no-ops; exact-ID non-heading footnotes still work; Split scrolls the preview root once and lets Vditor synchronize; no document-controlled fragment is interpolated as JavaScript source.

### ⬜ Unit 2b-iii: Same-document anchors — Coverage and refactor
**What**: Centralize JavaScript heading occurrence counting separately from base slug normalization, expose a deterministic test hook, inject all conformance cases from the bundled shared fixture through `LinkTest.swift`, and cover empty-slug and fallback paths without runtime fetch/XHR.
**Output**: Complete same-document JavaScript branch coverage and isolated anchor helpers.
**Acceptance**: Headless coverage exercises every lookup branch; footnote/back-reference IDs remain unchanged; the editor page URL remains stable after every fragment activation.

### ⬜ Unit 2c-i: Cross-document fragments — Tests
**What**: Extend `Tests/OuroMDAppSupportTests/DocumentLinkTests.swift`, `Tests/OuroMDTests/EditorWebViewTests.swift`, and `Tests/OuroMDTests/AppDelegateWindowRoutingTests.swift` for the fragment-carrying Markdown-file target, relative/absolute/file URLs, encoded fragments, existing-window reuse, new-window creation, sandbox-granted targets, readiness ordering, recovery, missing headings, and one-shot pending-fragment consumption.
**Output**: Failing cross-document fragment tests and `./2026-08-21-1214-doing-reference-links-and-anchors/unit2c-i/red.log`.
**Acceptance**: Tests fail because the current public target enum drops file fragments and window routing has no readiness-safe scroll handoff.

### ⬜ Unit 2c-ii: Cross-document fragments — Implementation
**What**: Change `DocumentLinkTarget`, `DocumentLinkResolver`, `EditorWebView.Coordinator`, `AppModel`, and `AppDelegate` to preserve an optional fragment beside the standardized Markdown file URL and pass it through sandbox/existing/new-window paths. `AppModel.editorDidBecomeReady()` starts one pending request after applying `pendingMarkdown`; the bridge retries `scrollToAnchor(fragment)` across render frames until it succeeds or reaches a deterministic maximum-attempt constant covered by tests, following the existing `revealSearchMatch` rAF-plus-timeout fallback pattern. Already-ready existing windows start the same bounded retry immediately.
**Output**: Readiness-safe native fragment propagation across document windows.
**Acceptance**: Unit 2c-i is green; unsupported schemes remain blocked; cold-window rendering cannot silently outrun a fixed two-frame scroll; existing and new target windows consume the requested fragment exactly once.

### ⬜ Unit 2c-iii: Cross-document fragments — Coverage and refactor
**What**: Cover fragment consumption after open, reuse, web-content recovery, missing target, cancelled sandbox grant, and subsequent unrelated document loads; remove duplicate pending-state paths.
**Output**: Complete cross-document Swift branch coverage and one pending-fragment mechanism.
**Acceptance**: 100% coverage on new Swift routing; no stale fragment contaminates later opens; all same-document tests remain green.

### ⬜ Unit 2d: Anchor routing — Visual QA dogfood
**What**: Use the extended `--linktest-artifact-dir` capture points immediately before and after activating the authoritative fixture's distant headings, duplicate headings, encoded fragments, exact-ID footnotes, and cross-document jump in each rendered editor mode, then run `visual-qa-dogfood` for static metrics.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/visual/anchor-ir-before.png`, `anchor-ir-after.png`, `anchor-wysiwyg-after.png`, `anchor-split-after.png`, `anchors-visual-absurdity-ledger.md`, plus cross-document routing evidence from `AppDelegateWindowRoutingTests`/`EditorWebViewTests` under `./2026-08-21-1214-doing-reference-links-and-anchors/unit2c-i/`.
**Acceptance**: Each same-document jump lands with the intended heading visibly at the top of the reading region, no double-scroll or URL mutation occurs, cross-document handoff is evidenced by the window-owning Swift tests rather than a one-WebView screenshot, the absurdity ledger is closed, and `OURO_VISUAL_ARTIFACT_DIR=worker/tasks/2026-08-21-1214-doing-reference-links-and-anchors/visual ./scripts/run-visual-qa.sh` remains green.

### ⬜ Unit 3a: Export anchor parity — Tests
**What**: Keep `Sources/OuroMD/MarkdownParityTest.swift` and `Tests/OuroMDTests/MarkdownRendererTests.swift` on the standalone `MarkdownRenderer.renderHTMLBody` half of the contract. Put all `window.ouro.getHTML()` app-export assertions in the real-WKWebView `Sources/OuroMD/EditorSurfaceTest.swift` and `Sources/OuroMD/LinkTest.swift` paths. Record `getHTML()` separately in IR/WYSIWYG/Split before asserting, because Split preview may already carry Lute-generated heading IDs. Load `heading-anchor-contract.json` in both halves; require absent or mismatched heading IDs to fail; compare heading/reference output and duplicate suffixes; and snapshot non-heading footnote/back-reference IDs before heading-ID normalization.
**Output**: Failing app-export and standalone-render parity tests that distinguish the two production paths.
**Acceptance**: WKWebView tests fail wherever app-export heading IDs are absent or disagree with the shared contract in any mode, while pure renderer tests characterize the standalone half; reference links already resolved by Lute remain resolved; tests prove a broad ID rewrite would regress footnotes.

### ⬜ Unit 3b: Export anchor parity — Implementation
**What**: Run a narrow quote-aware scanner over the original `vditor.getHTML()` string and insert or replace only the `id` attribute inside generated `<h1>`-`<h6>` opening tags, using the same JavaScript heading contract as live navigation; do not parse/re-serialize the full document and never rewrite non-heading `id`/`href` attributes. Update `MarkdownRenderer` to apply duplicate suffixes at heading-render time while leaving the generic base slug used by footnotes unchanged.
**Output**: Matching heading/reference contracts in app HTML/PDF input and standalone HTML/PDF rendering.
**Acceptance**: Unit 3a is green; restoring each original heading opening tag in normalized app-export HTML yields the exact pre-change `vditor.getHTML()` bytes whether the tag originally lacked or carried a Lute ID; entities, void tags, quoting, whitespace, reference links, footnote IDs, and back-reference IDs are otherwise byte-identical; app and standalone exports emit identical heading IDs for every shared contract case.

### ⬜ Unit 3c: Export anchor parity — Coverage and refactor
**What**: Add parity fixtures for inline formatting in headings, Unicode, punctuation-only headings, duplicates, exact-ID footnotes, and reference links targeting external/local/fragment destinations.
**Output**: Complete export-path edge coverage without broad HTML rewriting.
**Acceptance**: 100% coverage on new Swift renderer state; live scenario assertions cover JavaScript export reconciliation; HTML and PDF generation remain green.

### ⬜ Unit 4a: Shared scenario gate — Tests
**What**: Add a top-level `fixtures` entry to `docs/shipped-cli-and-harness-policy.json` with `path: "Tests/Fixtures/reference-links-and-anchors.md"`, `script: "scripts/run-native-scenarios.sh"`, and `requiredLines` containing these exact shell lines: `run_with_timeout "$OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS" --linktest --linktest-file "$reference_fixture"`, `run --roundtrip "$reference_fixture" --out "$reference_roundtrip_out"`, and `cmp "$reference_fixture" "$reference_roundtrip_out"`. Extend `scripts/check-shipped-harness-policy.sh` to require the fixture file to exist and every declared line to occur in the declared script, then run the policy check before editing the scenario script.
**Output**: Failing harness-policy assertion and `./2026-08-21-1214-doing-reference-links-and-anchors/unit4a/red.log`.
**Acceptance**: The policy check fails only because the shared native scenario gate does not yet own the new byte-preservation fixture.

### ⬜ Unit 4b: Shared scenario gate — Implementation
**What**: After the existing `tmp="$(mktemp -d /tmp/ouro-md-native-scenarios.XXXXXX)"` and cleanup trap, define `reference_fixture="Tests/Fixtures/reference-links-and-anchors.md"` and `reference_roundtrip_out="$tmp/reference-links-and-anchors-roundtrip.md"`; then add the three exact policy-declared lines using `run_with_timeout "$OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS"` for the fixture-driven link test and `run`/`cmp` for round-trip. Keep the earlier legacy link invocation on the same exported timeout budget; do not duplicate fixture content in shell.
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
- 2026-08-21 12:53 Quality pass made baseline capture executable, added unconditional WebKit artifacts, fail-closed AST/DOM integrity checks, explicit `argValue` seams, literal policy lines, and exact planning coverage text.
- 2026-08-21 13:00 Tinfoil-hat scrutiny added the clean-buffer round-trip fallback, preserved Command-mousedown routing, suppressed the IR reference popover, covered focused-label edits, restructured LinkTest phases/timeouts, verified resource loading, and scoped Split scrolling.
- 2026-08-21 13:09 Stranger-with-candy scrutiny corrected app-export test ownership, replaced an unshipped Vditor-symbol assumption with behavior-level interception, made heading IDs insertion-only, moved fixture commands after temp setup, and switched reference resolution to parser-normalized label keys.
- 2026-08-21 13:16 Second tinfoil-hat scrutiny removed the vacuous clean-buffer echo, added raw-vs-bridge round-trip proof, bounded cold-window scroll retries, aligned LinkTest with the outer alarm, preserved app-export bytes with a narrow scanner, positioned fragment interception before gesture gates, and covered reference-style fragment destinations.
- 2026-08-21 13:26 Second stranger-with-candy scrutiny made heading lookup contract-first across modes, made raw round-trip validation non-normalizing, aligned timeout policy literals, moved cross-document visual evidence to window-owning tests, made CSS the sole IR protection, and handled pre-existing Split/export heading IDs.
