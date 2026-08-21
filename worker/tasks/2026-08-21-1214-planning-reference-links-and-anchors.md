# Planning: Reference-style link rendering and anchor navigation

**Status**: drafting
**Created**: 2026-08-21 12:16

## Goal
Make valid CommonMark reference-style links read and behave like links in every Ouro MD editor mode, and make heading-fragment links navigate reliably within the current document or a linked Markdown document without rewriting the author's source.

## Scope

### In Scope
- Treat full, collapsed, and shortcut reference-style links as rendered links in instant-rendering mode without exposing their inline reference identifiers, including while the link label has focus.
- Resolve reference-style link destinations from Vditor/Lute parser output rather than a partial handwritten Markdown parser.
- Preserve the established gesture contract: external web/mail links open on Command-click, while local Markdown and heading-fragment links navigate on a normal rendered-link click.
- Support same-document heading fragments such as `#target-heading` in IR, WYSIWYG, and Split/preview surfaces.
- Preserve exact-ID in-document navigation used by rendered footnotes and other app-owned anchors before falling back to heading-slug matching.
- Preserve and honor fragments on local Markdown targets such as `other.md#target-heading`, including when the target document is already open and when a new window must wait for editor readiness.
- Preserve the fragment explicitly in the native link-target model instead of encoding it into or discarding it from the file URL.
- Use one documented heading-slug and duplicate-heading contract across live-editor navigation, `window.ouro.getHTML()` app exports, and the standalone `MarkdownRenderer` used by `--render` and parity harnesses.
- Keep Source Code mode and save/round-trip behavior byte-preserving; do not normalize reference links into inline links.
- Extend unit and headless live-editor coverage for reference-style rendering, destination routing, anchor scrolling, duplicate headings, encoded fragments, and regressions in existing inline links.
- Keep unresolved or malformed reference syntax visibly editable and non-clickable instead of inventing a destination.
- Capture live visual evidence for the IR reference-link appearance and anchor-scroll result.

### Out of Scope
- Replacing Vditor/Lute or modifying vendored Vditor source directly.
- Reverting the already-valid inline-link workaround in the platform-workflows document.
- Changing external links from Command-click to plain-click.
- Adding non-CommonMark heading attribute syntax such as `{#custom-id}` or guaranteeing navigation to arbitrary raw-HTML `id` attributes.
- Redesigning the outline, editor modes, or general link styling beyond the reference-marker defect.

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

## Open Questions
- None. The plan adopts parser-owned reference resolution, GitHub-style heading fragments with deterministic duplicate suffixes, and byte-preserving display-only handling.

## Decisions Made
- Treat the reported reference-style rendering defect and the source-verified anchor-navigation defect as one link-boundary fix spanning Vditor DOM rendering, editor gesture routing, native target resolution, and post-open scrolling.
- Keep reference syntax untouched in the Markdown buffer; the IR appearance fix is render-only, and Source Code mode remains the place to edit reference identifiers.
- Resolve reference destinations through the vendored parser's structured output so escaped labels, normalized labels, titles, collapsed references, and shortcut references follow CommonMark semantics.
- Make fragments a first-class internal target rather than allowing WebKit to navigate against Vditor's mode-specific generated element IDs; try an exact rendered DOM ID first, then the shared heading-slug contract.
- Preserve local-document fragments through native routing instead of silently discarding them as the current resolver does.
- Change the public Markdown-file target shape to carry an optional fragment alongside the standardized file URL, then thread that value through existing-window and new-window open paths.
- Use `getElementById` for exact-ID lookup and escaped data handoff rather than constructing document-controlled CSS selectors or JavaScript source.
- Intercept fragment gestures before WebKit navigation so only Ouro MD's exact-ID/heading-slug routing runs and the editor page URL never changes.
- Define duplicate heading IDs with stable numeric suffixes at heading-collection/render time, not inside the generic slug normalizer used by footnote IDs, and use the same heading contract in the live editor and both export paths.
- Restrict app-export ID reconciliation to heading elements so existing Vditor/Lute footnote and back-reference IDs remain untouched.

## Context / References
- `/Users/microsoft/personal-desk/ouro-md/_planning/reference-style-links/report.md`
- `/Users/microsoft/personal-desk/ouro-md/_planning/reference-style-links/reference-id-visible-in-ir.png`
- `Sources/OuroMD/web/bridge.js`
- `Sources/OuroMD/web/index.html`
- `Sources/OuroMD/EditorWebView.swift`
- `Sources/OuroMDAppSupport/DocumentLink.swift`
- `Sources/OuroMD/AppModel.swift`
- `Sources/OuroMD/AppDelegate.swift`
- `Sources/OuroMD/LinkTest.swift`
- `Sources/OuroMD/MarkdownRenderer.swift`
- `Sources/OuroMD/RoundTrip.swift`
- `Sources/OuroMD/MarkdownParityTest.swift`
- `Sources/OuroMD/EditorSurfaceTest.swift`
- `Tests/OuroMDAppSupportTests/DocumentLinkTests.swift`
- `Tests/OuroMDTests/EditorWebViewTests.swift`
- `Tests/OuroMDTests/MarkdownRendererTests.swift`
- `scripts/run-native-scenarios.sh`
- `docs/vditor-vendor-manifest.json`
- Bundled Vditor/Lute `RenderJSON` output: reference links are `NodeLink` entries with resolved `NodeLinkDest`, while editor DOM nodes use `data-type="link-ref"` and expose no `href`. The vendor manifest records the pre-existing upstream version as unknown, so the plan relies on the checked-in bundle's behavior rather than a guessed release number.

## Notes
The current bridge recognizes inline IR links (`data-type="a"`) but not reference links (`data-type="link-ref"`). It classifies `#fragment` separately in Swift and then drops it, and local Markdown resolution strips fragments before opening a file. Vditor also gives headings mode-specific generated IDs, so browser-default hash navigation cannot satisfy authored GitHub-style fragments. The implementation must distinguish resolved reference nodes from unresolved source-like text and must not regress Vditor's separate exact-ID footnote anchors. App HTML/PDF export currently uses `bridge.getHTML()`/`vditor.getHTML()`, while `MarkdownRenderer` covers `--render` and separate parity harnesses; both paths need explicit anchor parity coverage.

## Progress Log
- 2026-08-21 12:16 Created.
- 2026-08-21 12:18 Tinfoil-hat pass added unresolved-reference and exact-ID/footnote anchor protections.
- 2026-08-21 12:22 Addressed cold-review findings for the actual app export path, safe fragment lookup, all editor modes, vendor provenance, heading-only deduplication, and native fragment propagation.
- 2026-08-21 12:27 Addressed second-round findings for export footnote-ID safety, shared scenario-gate wiring, single-handled WebKit fragment navigation, and anchor-finding provenance.
