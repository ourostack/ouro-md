# Planning: Reference-style link rendering and anchor navigation

**Status**: approved
**Created**: 2026-08-21 12:16

## Goal
Make valid CommonMark reference-style links read and behave like links in every Ouro MD editor mode, and make heading-fragment links navigate reliably within the current document or a linked Markdown document without rewriting the author's source.

## Scope

### In Scope
- Treat full, collapsed, and shortcut reference-style links as rendered links in instant-rendering mode without exposing their inline reference identifiers, including while the link label has focus.
- Cover the two shipping editor states explicitly: IR, and Source Code (`sv`) with its literal source pane plus rendered preview pane; keep the SV source pane inert and preserve its authored syntax.
- Resolve reference-style link destinations from Vditor/Lute parser output rather than a partial handwritten Markdown parser.
- Preserve the established gesture contract: external web/mail links open on Command-click, while local Markdown and heading-fragment links navigate on a normal rendered-link click.
- Support same-document heading fragments such as `#target-heading` in IR and the SV rendered preview pane.
- Resolve shared-contract headings first, then preserve exact-ID navigation as a fallback for non-heading rendered elements such as SV-preview/export footnote references and back-references; IR has no footnote IDs to navigate.
- Preserve and honor fragments on local Markdown targets such as `other.md#target-heading`, including when the target document is already open and when a new window must wait for editor readiness.
- Preserve the fragment explicitly in the native link-target model instead of encoding it into or discarding it from the file URL.
- Use one documented heading-slug and duplicate-heading contract across live-editor navigation, `window.ouro.getHTML()` app exports, and the standalone `MarkdownRenderer` used by `--render` and parity harnesses.
- Keep Source Code mode and save/round-trip behavior byte-preserving; do not normalize reference links into inline links.
- Use a dedicated strict round-trip fixture for the canonical full-reference syntax in the report, separate from the richer rendering/navigation fixture that exercises known Lute-normalized variants.
- Extend unit and headless live-editor coverage for reference-style rendering, destination routing, anchor scrolling, duplicate headings, encoded fragments, and regressions in existing inline links.
- Keep unresolved or malformed reference syntax visibly editable and non-clickable instead of inventing a destination.
- Capture live visual evidence for the IR reference-link appearance and anchor-scroll result.
- Advance the app to the next patch release (currently `0.9.85` after published `v0.9.84`), amend release highlights, and update App Store request-plan expectations derived from the distribution manifest because PR freshness classifies these source changes as release-relevant.

### Out of Scope
- Replacing Vditor/Lute or modifying vendored Vditor source directly.
- Reverting the already-valid inline-link workaround in the platform-workflows document.
- Changing external links from Command-click to plain-click.
- Adding non-CommonMark heading attribute syntax such as `{#custom-id}` or guaranteeing navigation to arbitrary raw-HTML `id` attributes.
- Redesigning the outline, editor modes, or general link styling beyond the reference-marker defect.
- Correcting pre-existing vendored Lute source normalizations for collapsed references, definition titles/angle brackets, or definition-block spacing during edited serialization.
- Adding shared heading-anchor IDs to the rendered-HTML clipboard flavor; this task covers live navigation and app/standalone HTML/PDF export.
- Adding or exposing Vditor's internal WYSIWYG mode; Ouro MD ships IR and Source Code (`sv`) only.

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

## Open Questions
- None. The plan adopts parser-owned reference resolution, a cross-language Unicode-scalar heading contract with deterministic duplicate suffixes, and byte-preserving display-only handling.

## Decisions Made
- Treat the reported reference-style rendering defect and the source-verified anchor-navigation defect as one link-boundary fix spanning Vditor DOM rendering, editor gesture routing, native target resolution, and post-open scrolling.
- Keep reference syntax untouched in the Markdown buffer; the IR appearance fix is render-only, and Source Code mode remains the place to edit reference identifiers.
- Separate the rich navigation/rendering fixture from a strict raw round-trip fixture because the checked-in Lute normalizes collapsed references, definition titles/angle brackets, and some definition-block spacing; this fix must not hide those pre-existing behaviors behind `MarkdownTidy`.
- Resolve reference destinations through the vendored parser's structured output so escaped labels, normalized labels, titles, collapsed references, and shortcut references follow CommonMark semantics.
- Treat IR and SV as the only shipping modes: parser-derived reference resolution is needed for IR, while SV preview uses rendered anchors and SV source remains inert.
- Make fragments a first-class internal target rather than allowing WebKit to navigate against Vditor's mode-specific generated heading IDs; resolve the shared heading contract first, then fall back to an exact rendered DOM ID for non-heading elements only.
- Preserve local-document fragments through native routing instead of silently discarding them as the current resolver does.
- Change the public Markdown-file target shape to carry an optional fragment alongside the standardized file URL, then thread that value through existing-window and new-window open paths.
- Use `getElementById` for exact-ID lookup and escaped data handoff rather than constructing document-controlled CSS selectors or JavaScript source.
- Intercept fragment gestures before WebKit navigation so only Ouro MD's exact-ID/heading-slug routing runs and the editor page URL never changes.
- Define duplicate heading IDs with stable numeric suffixes at heading-collection/render time, not inside the generic slug normalizer used by footnote IDs, and use the same heading contract in the live editor and both export paths.
- Define the heading base contract independently from the generic footnote slug: NFC-normalize, lowercase, NFC-normalize again, iterate Unicode scalars, retain alphabetic/numeric scalars, map space/hyphen/underscore to `-`, drop other scalars (including combining marks that remain after normalization), collapse/trim hyphens, then apply heading-only empty fallback and duplicate suffixes. Implement the same scalar predicate as Swift `Unicode.Scalar.Properties` and JavaScript Unicode-property escapes, and pin `İstanbul`, `a̱bc`, and `Mā́n` in the shared fixture.
- Restrict app-export ID reconciliation to heading elements so existing Vditor/Lute footnote and back-reference IDs remain untouched.
- Treat the version bump, `README.md`, `distribution/apple-distribution.json`, release-highlight change, and `OuroMDAppStoreRequestPlanTests` expectation updates as required release-policy consequences, not unrelated diff.
- Prefer adding a fourth `OuroMDRelease.releaseHighlights` entry rather than rewriting existing copy: preserve every `OuroMDPositioningTests` token, the `local Markdown files` substring consumed by App Store `whatsNew`, and the `Markdown editor` prohibition; keep `]` and `"` out of highlight strings because the request-plan parser reads this Swift array textually.

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
The current bridge recognizes inline IR links (`data-type="a"`) but not reference links (`data-type="link-ref"`). It classifies `#fragment` separately in Swift and then drops it, and local Markdown resolution strips fragments before opening a file. Vditor also gives headings mode-specific generated IDs, so browser-default hash navigation cannot satisfy authored shared-contract fragments. Ouro MD exposes IR and Source Code (`sv`); SV contains a literal source pane and a rendered preview pane, while Vditor's WYSIWYG mode is not reachable from app UI. IR footnote spans have no IDs; SV preview/export owns exact-ID footnote navigation. App HTML/PDF export uses `bridge.getHTML()`/`vditor.getHTML()`, while `MarkdownRenderer` covers `--render` and separate parity harnesses; both export paths need explicit anchor parity coverage. The copy-as-rendered-HTML path calls Lute directly and is intentionally outside this task.

## Progress Log
- 2026-08-21 12:16 Created.
- 2026-08-21 12:18 Tinfoil-hat pass added unresolved-reference and exact-ID/footnote anchor protections.
- 2026-08-21 12:22 Addressed cold-review findings for the actual app export path, safe fragment lookup, all editor modes, vendor provenance, heading-only deduplication, and native fragment propagation.
- 2026-08-21 12:27 Addressed second-round findings for export footnote-ID safety, shared scenario-gate wiring, single-handled WebKit fragment navigation, and anchor-finding provenance.
- 2026-08-21 12:28 Approved after two cold-review rounds converged with no blocking or major findings.
- 2026-08-21 13:36 Updated after implementation scrutiny: split rich versus strict round-trip fixtures, documented pre-existing Lute normalizations, and bounded clipboard HTML out of scope.
- 2026-08-21 13:57 Updated after mode scrutiny: scoped behavior to shipping IR and Source Code (`sv`) source/preview panes, made WYSIWYG out of scope, and limited exact-ID footnote navigation to rendered preview/export surfaces.
- 2026-08-21 14:18 Updated after convergence review: added the required `0.9.85` release-policy work and fixed the heading contract to an explicit Ouro mapping with heading-only NFC normalization.
- 2026-08-21 14:33 Updated after final deception review: made heading slugs scalar-based across Swift/JavaScript and protected the App Store positioning contract while amending `0.9.85` release highlights.
- 2026-08-21 14:42 Updated after release-gate review: added App Store request-plan expectation updates required by the `0.9.85` manifest bump.
- 2026-08-21 14:51 Updated after App Store copy review: preserved `whatsNew` parser tokens and constrained release-highlight syntax.
- 2026-08-21 15:08 Updated after cross-doc review: aligned planning with contract-first heading lookup and non-heading-only exact-ID fallback.
