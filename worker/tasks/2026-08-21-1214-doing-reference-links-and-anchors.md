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
- [ ] Full, collapsed, and shortcut reference-style links resolve consistently in IR, SV rendered preview, `window.ouro.getHTML()` HTML/PDF export input, and standalone `--render` output, while the SV source pane stays literal and inert.
- [ ] Same-document inline and reference-style fragment links scroll to the intended heading in IR and SV rendered preview.
- [ ] Existing exact-ID anchors, including SV-preview/export footnote references and back-references, continue to navigate; IR's source-like footnote spans remain unchanged.
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
- [ ] `scripts/bump-version.sh 0.9.85` updates release metadata and highlights, `scripts/verify-release-version.sh` passes, and PR freshness accepts the release-relevant diff.
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
**What**: Land rich `Tests/Fixtures/reference-links-and-anchors.md` for rendering/navigation and strict `Tests/Fixtures/reference-links-roundtrip.md` whose link-reference definition block is the final block with one trailing newline, canonical full/shortcut refs, bare destinations, no titles/angle brackets, no collapsed refs, and no adjacent footnote definition. Add argument-only fixture/artifact seams, keep them out of policy modes, update privacy, and refactor LinkTest into a rebuild-safe IR/SV phase queue with legacy coverage and unconditional snapshot/DOM/HTML artifacts. Align timeout budgets, reproduce both defects, capture raw values, and record the verified normalization matrix for rich-only variants.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/unit0/baseline.md`, `ir-dom.json`, `app-export.html`, `standalone-export.html`, `reference-focused.png`, and `anchor-before.png`.
**Acceptance**: Optional arguments use `argValue`; privacy text covers caller input/artifacts; legacy and rich-fixture IR/SV phases complete within one timeout budget; diagnostics are produced on green exit. Rich-fixture normalizations are documented, not treated as regressions; raw Vditor and bridge values both match the dedicated final-def-block strict fixture before `MarkdownTidy`. If that strict fixture fails, stop and redesign source preservation; do not echo cached source, narrow the strict fixture, edit vendored Vditor, or land a partial fix.

### ⬜ Unit 1a: Reference-style links — Tests
**What**: Extend the Unit 0 queue with expected-red full/collapsed/shortcut presentation/routing assertions in IR and SV preview, plus an assertion that SV source stays literal/inert, while retaining expected-green standalone rendering. Pin parser label encoding/normalization. Add argument-only strict round-trip mode comparing raw/bridge values with the strict final-def-block fixture before tidy, keep ordinary round-trip unchanged, unit-test normalization-maskable mismatches, and add IR keyboard/mouse/edit fidelity phases.
**Output**: Failing live reference-link regression coverage, green standalone-render characterization, the source-preservation fixture, and `./2026-08-21-1214-doing-reference-links-and-anchors/unit1a/red.log`.
**Acceptance**: The named expected-red LinkTest assertions fail for missing marker hiding and destination routing; expected-green renderer/round-trip assertions pass; existing inline links remain green.

### ⬜ Unit 1b: Reference-style links — Implementation
**What**: Extend the existing capture-phase `resolveEditorLinkURL()` path. In `index.html`, keep reference markers hidden under expanded IR nodes and add explicit link-label affordances for IR `data-type="link-ref"` nodes. In `bridge.js`, decode/normalize base64 AST labels and IR-derived full/collapsed/shortcut labels, build the destination map, and fail closed on missing/ambiguous/mismatched keys. Cache by exact Markdown/mode and invalidate on input/set/reload/rebuild. Do not add WYSIWYG-specific code: SV source stays inert, and SV preview uses rendered `a[href]`.
**Output**: Render-only reference-marker handling and parser-owned destination routing.
**Acceptance**: Unit 1a is green; IR labels retain a visible link affordance while markers stay hidden; external references open from Command-mousedown; plain clicks do not expose identifiers; unresolved refs remain source text; bad keys are no-ops; label editing preserves syntax/destination; SV source is inert and SV preview anchors work; strict raw round-trip is byte-identical.

### ⬜ Unit 1c: Reference-style links — Coverage and refactor
**What**: Add edge coverage for repeated labels, whitespace/case normalization, escaped labels, optional titles, missing definitions, malformed destinations, definition blocks far from their uses, ambiguous normalized labels, and a synthetic DOM label that does not exist in the AST map. Cache parser-derived reference targets only against the exact current Markdown value and mode, and invalidate on every edit/reload/mode rebuild.
**Output**: Complete branch coverage and a single narrow reference-target helper in `bridge.js`.
**Acceptance**: 100% coverage on new Swift seams and explicit headless assertions for each JavaScript branch; no handwritten reference-definition parser; all link and round-trip tests remain green.

### ⬜ Unit 1d: Reference-style links — Visual QA dogfood
**What**: Run the extended link harness with the rich fixture and artifact directory so purpose-built snapshots capture focused/unfocused IR plus SV source and SV preview states. Run the existing `scripts/run-visual-qa.sh` suite unchanged as a global visual-regression gate; do not add the link fixture as a `VisualQATester` metrics case because that harness requires unrelated dogfood images, nested lists, callouts, and tables.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/visual/reference-ir-focused.png`, `reference-ir-unfocused.png`, `reference-sv-source.png`, `reference-sv-preview.png`, and `reference-links-visual-absurdity-ledger.md`.
**Acceptance**: IR labels are visibly link-styled with no identifier under keyboard/mouse focus; SV source stays literal/inert; SV preview renders links; the purpose-built absurdity ledger closes; the unchanged visual QA suite remains green.

### ⬜ Unit 2a: Heading-anchor contract fixture
**What**: Write the language-neutral heading contract before either implementation: NFC-normalize, lowercase, NFC-normalize again, iterate Unicode scalars, retain alphabetic/numeric scalars, map space/hyphen/underscore to `-`, drop other scalars including remaining combining marks, collapse/trim hyphens, then apply heading-only empty fallback and duplicate suffixes. Swift uses `Unicode.Scalar.Properties`; JavaScript uses matching Unicode-property escapes. Include precomposed/decomposed pairs plus `İstanbul`, `a̱bc`, `Mā́n`, inline formatting, punctuation-only, digit-leading, underscore, and duplicates in `Sources/OuroMD/web/heading-anchor-contract.json`; Swift tests read the source path and LinkTest loads the bundled copy.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/anchor-contract.md` and `Sources/OuroMD/web/heading-anchor-contract.json`.
**Acceptance**: Every heading case has one expected ID; NFC/lowercase/NFC ordering and scalar predicates are explicit; composable equivalents converge; `İstanbul`, `a̱bc`, and `Mā́n` prove remaining marks are handled identically; underscore/deduplication are pinned; the generic footnote slug path stays unchanged; both test suites load the same fixture.

### ⬜ Unit 2b-i: Same-document anchors — Tests
**What**: Extend `EditorWebViewTests` with the pure escaped anchor-script seam, and extend `LinkTest` for inline/reference fragment destinations in IR and SV preview while asserting SV source links stay inert. Cover contract headings, encoded/digit-leading/punctuation fragments, duplicates, missing headings, one-shot handling, unchanged editor URL, and SV-preview footnote/back-reference exact IDs; do not expect IR footnote IDs that Vditor does not emit.
**Output**: Failing same-document anchor tests and `./2026-08-21-1214-doing-reference-links-and-anchors/unit2b-i/red.log`.
**Acceptance**: Tests fail on the current `.inDocumentAnchor` no-op, mode-specific generated heading IDs, and WebKit default hash navigation while unrelated link routing stays green.

### ⬜ Unit 2b-ii: Same-document anchors — Implementation
**What**: Make `bridge.js` own same-document activation before external/local gesture gates. Act only on click, suppress default navigation, scroll once, and never post `#fragment` to Swift. Scope IR lookup to its root and SV activation to the rendered preview root; keep SV source inert. Resolve contract headings first, then allow exact-ID fallback only for non-heading rendered elements such as SV-preview footnotes/back-references; IR has no such IDs. Keep the escaped native anchor script only for cross-document handoff.
**Output**: Same-document anchor navigation in `Sources/OuroMD/web/bridge.js` and `Sources/OuroMD/EditorWebView.swift`.
**Acceptance**: Unit 2b-i is green; the same fragment lands on the same logical heading in IR and SV preview despite Lute-generated IDs; SV source is inert; missing anchors are harmless; SV-preview footnote exact IDs work; preview scrolls once; no fragment is interpolated as JavaScript source.

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
**What**: Capture immediately before/after IR heading activation and SV-preview heading/footnote activation, with SV source remaining inert, then run the existing visual QA suite unchanged as a regression gate rather than forcing the link fixture through its dogfood-specific metrics floor.
**Output**: `./2026-08-21-1214-doing-reference-links-and-anchors/visual/anchor-ir-before.png`, `anchor-ir-after.png`, `anchor-sv-preview-after.png`, `anchors-visual-absurdity-ledger.md`, plus cross-document routing evidence from window-owning Swift tests under `./2026-08-21-1214-doing-reference-links-and-anchors/unit2c-i/`.
**Acceptance**: Each same-document jump lands with the intended heading visibly at the top of the reading region, no double-scroll or URL mutation occurs, cross-document handoff is evidenced by the window-owning Swift tests rather than a one-WebView screenshot, the absurdity ledger is closed, and `OURO_VISUAL_ARTIFACT_DIR=worker/tasks/2026-08-21-1214-doing-reference-links-and-anchors/visual ./scripts/run-visual-qa.sh` remains green.

### ⬜ Unit 3a: Export anchor parity — Tests
**What**: Keep MarkdownParity/MarkdownRendererTests on the standalone renderer half. Put `window.ouro.getHTML()` assertions in real-WKWebView EditorSurface/LinkTest paths, recording output separately in IR and SV because SV preview may carry Lute-generated IDs. Load the shared heading contract in both halves; fail absent/mismatched heading IDs; compare reference output/duplicates; snapshot non-heading footnote/back-reference IDs before heading normalization.
**Output**: Failing app-export and standalone-render parity tests that distinguish the two production paths.
**Acceptance**: WKWebView tests fail wherever app-export heading IDs are absent or disagree with the shared contract in any mode, while pure renderer tests characterize the standalone half; reference links already resolved by Lute remain resolved; tests prove a broad ID rewrite would regress footnotes.

### ⬜ Unit 3b: Export anchor parity — Implementation
**What**: Run a narrow quote-aware scanner over the original `vditor.getHTML()` string and insert or replace only heading `id` attributes using the JavaScript contract. In `MarkdownRenderer`, add a heading-only NFC-normalizing slug wrapper around the existing character mapping and apply duplicate suffixes at heading-render time; leave the generic footnote slug path byte-for-byte unchanged.
**Output**: Matching heading/reference contracts in app HTML/PDF input and standalone HTML/PDF rendering.
**Acceptance**: Unit 3a is green; restoring each original heading opening tag in normalized app-export HTML yields the exact pre-change `vditor.getHTML()` bytes whether the tag originally lacked or carried a Lute ID; entities, void tags, quoting, whitespace, reference links, footnote IDs, and back-reference IDs are otherwise byte-identical; app and standalone exports emit identical heading IDs for every shared contract case.

### ⬜ Unit 3c: Export anchor parity — Coverage and refactor
**What**: Add parity fixtures for inline formatting in headings, Unicode, punctuation-only headings, duplicates, exact-ID footnotes, and reference links targeting external/local/fragment destinations.
**Output**: Complete export-path edge coverage without broad HTML rewriting.
**Acceptance**: 100% coverage on new Swift renderer state; live scenario assertions cover JavaScript export reconciliation; HTML and PDF generation remain green.

### ⬜ Unit 4a: Shared scenario gate — Tests
**What**: Add two top-level `fixtures` entries to `docs/shipped-cli-and-harness-policy.json`, leaving all three argument-only flags out of `modes`. Update the existing `--linktest` mode's privacy text to cover synthetic/checked-in/caller-provided Markdown input plus caller-specified artifact output. Declare the exported timeout and rich-link line for the rich fixture, the strict round-trip/cmp lines for the strict fixture, extend the checker to validate each path/line, then run it before editing the scenario script.
**Output**: Failing harness-policy assertion and `./2026-08-21-1214-doing-reference-links-and-anchors/unit4a/red.log`.
**Acceptance**: The policy check fails only because the shared native scenario gate does not yet own the new byte-preservation fixture.

### ⬜ Unit 4b: Shared scenario gate — Implementation
**What**: Near the top of `scripts/run-native-scenarios.sh`, add the exact exported default line before either link invocation so `set -u` cannot see an unbound timeout. After temp initialization/trap, define `link_fixture`, `roundtrip_fixture`, and `reference_roundtrip_out`; add the exact rich-link and strict-round-trip/cmp policy lines; keep legacy link testing on the same exported budget; do not duplicate fixture content in shell.
**Output**: Green shared harness policy and native scenario gate.
**Acceptance**: Unit 4a is green; the same gate runs in local preflight, CI, and packaged-app verification; fixture source remains byte-identical.

### ⬜ Unit 4c: Release freshness metadata
**What**: Run `scripts/bump-version.sh 0.9.85`, which updates `OuroMDRelease.swift`, `README.md`, and `distribution/apple-distribution.json` while leaving highlights untouched. Prefer adding a fourth highlight; preserve every positioning token, the `local Markdown files` substring used by App Store `whatsNew`, and the `Markdown editor` prohibition; keep `]` and `"` out of highlight strings. Update every live-`--selftest`-manifest-derived `0.9.84` expectation in `OuroMDAppStoreRequestPlanTests` (currently four: target version, filter, create-version payload, and dry-run text summary) while leaving test-local synthetic manifest expectations and `OuroMDAppStoreApplyPlanTests` unchanged. Run positioning, request-plan, package-readiness, release-version, and freshness checks.
**Output**: Version `0.9.85` release metadata and `./2026-08-21-1214-doing-reference-links-and-anchors/unit4c/release-version.log`.
**Acceptance**: All three version surfaces agree on `0.9.85`; `OuroMDPositioningTests`, `OuroMDAppStoreRequestPlanTests`, and `OuroMDAppStorePackageReadinessTests` are green; highlights describe both fixes without overclaiming; release verification and freshness pass against `v0.9.84`.

### ⬜ Unit 4d: Integrated regression and preflight
**What**: Run targeted Swift tests, `swift build`, the complete shared native scenarios and visual QA, `./scripts/check-shell-boundary.sh --selftest`, `./scripts/check-shell-boundary.sh`, `./scripts/check-vditor-vendor.sh`, coverage, and `./scripts/pr-preflight.sh`. Inspect the full branch diff for vendor-file changes, unrelated files, and source-format churn.
**Output**: Green local CI-parity evidence under `./2026-08-21-1214-doing-reference-links-and-anchors/final/`, with final screenshots and command logs.
**Acceptance**: All completion criteria are evidenced; vendor integrity confirms no files under `Sources/OuroMD/web/vditor/` changed; the full preflight passes with no warnings; the diff contains only the planned integration, tests, harness updates, shared fixtures, task artifacts, and required `0.9.85` changes in `Sources/OuroMDCore/OuroMDRelease.swift`, `README.md`, `distribution/apple-distribution.json`, and `Tests/OuroMDTests/OuroMDAppStoreRequestPlanTests.swift`.

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
- 2026-08-21 13:57 Fourth tinfoil-hat scrutiny aligned all units with shipping IR and Source Code (`sv`) source/preview surfaces, made WYSIWYG out of scope, pinned strict definition placement, and scoped exact-ID footnotes to rendered preview/export.
- 2026-08-21 14:08 Fourth stranger-with-candy scrutiny kept link/anchor visuals in the purpose-built LinkTest artifact path and left the dogfood-shaped `VisualQATester` fixture set unchanged.
- 2026-08-21 14:18 Fifth tinfoil-hat scrutiny added the mandatory `0.9.85` release-freshness unit and made the heading contract explicit for underscore mapping, heading-only NFC normalization, and decomposed Unicode parity.
- 2026-08-21 14:33 Fifth stranger-with-candy scrutiny preserved App Store positioning highlights during the version bump and finalized a scalar-based Swift/JavaScript Unicode contract with adversarial combining-mark cases.
- 2026-08-21 14:42 Sixth tinfoil-hat scrutiny added App Store request-plan/package-readiness updates required by the manifest bump and made the shipped link-harness privacy contract explicit.
- 2026-08-21 14:51 Sixth stranger-with-candy scrutiny covered all four live-manifest request-plan expectations and preserved the App Store `whatsNew` parser contract while adding release highlights.
- 2026-08-21 15:01 Seventh tinfoil-hat scrutiny converged with no issues.
- 2026-08-21 15:08 Seventh stranger-with-candy scrutiny aligned the approved planning contract with heading-first lookup and non-heading-only exact-ID fallback.
