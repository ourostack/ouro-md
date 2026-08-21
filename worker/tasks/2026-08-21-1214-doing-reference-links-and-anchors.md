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
- [ ] Source Code mode shows the original reference syntax, and the report's canonical full-reference form passes a strict raw no-edit round trip byte-for-byte.
- [ ] Editing nearby prose does not convert unrelated reference-style links to inline syntax or change their destinations; known Lute normalization of noncanonical reference variants is documented rather than silently attributed to this fix.
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
**What**: Land rich `Tests/Fixtures/reference-links-and-anchors.md` for full/collapsed/shortcut/unresolved/navigation/heading/footnote behavior and strict `Tests/Fixtures/reference-links-roundtrip.md` for canonical full/shortcut references with bare destinations and no Lute-normalized constructs. Add `argValue("--linktest-file")` and `argValue("--linktest-artifact-dir")` seams in `Sources/OuroMD/main.swift`; keep both out of policy `modes`; update `--linktest` privacy for caller input/artifacts; and refactor `LinkTest.swift` into a rebuild-safe phase queue that loads the rich fixture and preserves the legacy scenario. Add an explicit `captureSnapshot(named:)` helper using `WKWebView.takeSnapshot` plus PNG data writing, alongside DOM/HTML artifact writers, so requested diagnostics are unconditional. Export `OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS` with a default before any use, align inner/outer deadlines, reproduce both defects, capture raw Vditor values, and record the verified normalization matrix.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/unit0/baseline.md`, `ir-dom.json`, `app-export.html`, `standalone-export.html`, `reference-focused.png`, and `anchor-before.png`.
**Acceptance**: Optional arguments use `argValue`; privacy text covers caller input/artifacts; legacy and rich-fixture baseline phases complete within one declared timeout budget; diagnostics are produced on green exit. The reference/anchor defects are recorded per mode; rich-fixture normalizations are documented, not treated as this fix's regressions; raw Vditor and bridge values both match the dedicated strict round-trip fixture before any `MarkdownTidy` normalization. If the strict canonical fixture fails, stop before implementation and redesign source preservation; do not echo cached source, narrow that strict fixture, edit vendored Vditor, or land a partial fix.

### ⬜ Unit 1a: Reference-style links — Tests
**What**: Extend the Unit 0 phase queue with expected-red full/collapsed/shortcut presentation/routing assertions and expected-green standalone-render characterization. Pin parser encoding with a known `LinkRefLabel` base64-bytes → UTF-8 label → destination assertion, and pin the raw/normalized IR-marker label forms for full/collapsed/shortcut references before implementation. Add `argValue("--roundtrip-strict")` to `main.swift`, keep it out of policy `modes`, and in strict mode make `RoundTrip.swift` fail before `MarkdownTidy` unless raw Vditor and bridge values equal the strict fixture input. Keep ordinary round-trip behavior unchanged; unit-test the strict helper with normalization-maskable mismatches; add keyboard-caret, mouse-focus, and label-edit phases.
**Output**: Failing live reference-link regression coverage, green standalone-render characterization, the source-preservation fixture, and `./2026-08-21-1214-doing-reference-links-and-anchors/unit1a/red.log`.
**Acceptance**: The named expected-red LinkTest assertions fail for missing marker hiding and destination routing; expected-green renderer/round-trip assertions pass; existing inline links remain green.

### ⬜ Unit 1b: Reference-style links — Implementation
**What**: Extend the existing `resolveEditorLinkURL()` path used by both capture-phase `mousedown` and `click`; do not add a click-only handler. In `index.html`, keep reference markers hidden under expanded IR nodes with CSS-only display/size/overflow overrides and add explicit link-label color, underline, and pointer affordances for IR/WYSIWYG `data-type="link-ref"` nodes. In `bridge.js`, decode each base64 `RenderJSON.LinkRefLabel` through `atob` → byte array → `TextDecoder("utf-8")`, then apply one tested CommonMark trim/whitespace-collapse/case-fold normalizer to both AST labels and DOM-derived labels before building the destination map. WYSIWYG reads `data-link-label`; full IR strips brackets from `.vditor-ir__marker--link`; collapsed/shortcut IR derives the visible label. Missing/ambiguous/mismatched labels fail closed. Cache by exact Markdown/mode and invalidate on input/set/reload/rebuild without substituting cached source for Vditor serialization.
**Output**: Render-only reference-marker handling and parser-owned destination routing.
**Acceptance**: Unit 1a is green; reference labels retain a visible link affordance while syntax markers stay hidden; external references open from Command-mousedown; plain clicks do not open/expose identifiers; unresolved references remain source text; absent/ambiguous/mismatched keys are no-ops; label editing preserves syntax/destination; strict raw round-trip stays byte-identical.

### ⬜ Unit 1c: Reference-style links — Coverage and refactor
**What**: Add edge coverage for repeated labels, whitespace/case normalization, escaped labels, optional titles, missing definitions, malformed destinations, definition blocks far from their uses, ambiguous normalized labels, and a synthetic DOM label that does not exist in the AST map. Cache parser-derived reference targets only against the exact current Markdown value and mode, and invalidate on every edit/reload/mode rebuild.
**Output**: Complete branch coverage and a single narrow reference-target helper in `bridge.js`.
**Acceptance**: 100% coverage on new Swift seams and explicit headless assertions for each JavaScript branch; no handwritten reference-definition parser; all link and round-trip tests remain green.

### ⬜ Unit 1d: Reference-style links — Visual QA dogfood
**What**: Run the extended `--linktest` with the rich fixture and artifact directory so `WKWebView.takeSnapshot` captures focused/unfocused IR, WYSIWYG, Split, and Source Code states unconditionally. Add the rich fixture as a static metrics case in `scripts/run-visual-qa.sh` and run `visual-qa-dogfood`.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/visual/reference-ir-focused.png`, `reference-ir-unfocused.png`, `reference-wysiwyg.png`, `reference-split.png`, `reference-source.png`, and `reference-links-visual-absurdity-ledger.md`.
**Acceptance**: The rendered label is visibly link-styled in IR/WYSIWYG; no reference identifier appears in IR even under keyboard/mouse focus; Source Code retains original syntax; the absurdity ledger closes; the visual QA command is green.

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
**What**: Add two top-level `fixtures` entries to `docs/shipped-cli-and-harness-policy.json`, leaving all three argument-only flags out of `modes`. The rich fixture entry requires `export OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS="${OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS:-90}"` and `run_with_timeout "$OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS" --linktest --linktest-file "$link_fixture"`. The strict fixture entry requires `run --roundtrip "$roundtrip_fixture" --roundtrip-strict raw --out "$reference_roundtrip_out"` and `cmp "$roundtrip_fixture" "$reference_roundtrip_out"`. Extend the policy checker to validate each fixture path and exact declared line, then run it before editing the scenario script.
**Output**: Failing harness-policy assertion and `./2026-08-21-1214-doing-reference-links-and-anchors/unit4a/red.log`.
**Acceptance**: The policy check fails only because the shared native scenario gate does not yet own the new byte-preservation fixture.

### ⬜ Unit 4b: Shared scenario gate — Implementation
**What**: Near the top of `scripts/run-native-scenarios.sh`, add the exact exported default line before either link invocation so `set -u` cannot see an unbound timeout. After temp initialization/trap, define `link_fixture`, `roundtrip_fixture`, and `reference_roundtrip_out`; add the exact rich-link and strict-round-trip/cmp policy lines; keep legacy link testing on the same exported budget; do not duplicate fixture content in shell.
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
- 2026-08-21 13:36 Third tinfoil-hat scrutiny split rich and strict fixtures around verified Lute normalizations, scoped strict raw checks without breaking ordinary round-trip, added reference-link affordances, and kept copy-as-rendered-HTML anchor IDs out of scope.
- 2026-08-21 13:46 Third stranger-with-candy scrutiny pinned base64/UTF-8 label decoding and bilateral normalization, kept argument flags out of policy modes, made timeout defaulting `set -u` safe, and assigned snapshot/DOM artifact helpers explicitly.
