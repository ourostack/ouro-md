# App Store 4.3(a) Rejection Research And Plan

Date: 2026-07-08 19:40 PT

## Executive Finding

Apple rejected Ouro MD `0.9.79 (0.9.79)` under Guideline `4.3(a) - Design - Spam`. The strongest evidence points to a product-presentation and proof problem more than a single code defect: the submitted metadata was generic, the subtitle was `The Markdown App`, the review notes did not explain the app's distinct functionality, and the only submitted screenshot showed a quiet single-document Markdown surface with none of the app's more differentiated features visible.

Recommended response: do not appeal first. Prepare a fresh build/version, update the source-owned App Store metadata and screenshots, include a concise App Review note that explains the distinct functionality and app ownership, then resubmit. Use appeal only if Apple rejects the revised submission while ignoring the new evidence.

## Source Threads Pulled

### Apple Policy

Official sources reviewed:
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Review support page: https://developer.apple.com/distribute/app-review/
- App Store Connect submission overview: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review/
- Product page guidance: https://developer.apple.com/app-store/product-page/
- Apple Staff forum post, "Preventing Copycat and Impersonation Rejections": https://developer.apple.com/forums/thread/782175
- App Store Connect API Review Submissions docs: https://developer.apple.com/documentation/appstoreconnectapi/review-submissions
- App Store Connect API localization docs: https://developer.apple.com/documentation/appstoreconnectapi/app-store-version-localizations and https://developer.apple.com/documentation/appstoreconnectapi/app-info-localizations

Policy implications:
- Guideline 4.3(a) focuses on multiple bundle IDs of the same app; current 4.3(b) also targets apps that are indistinguishable from what is already widely available.
- Guideline 2.3 requires accurate metadata, screenshots, and review notes; Apple explicitly says new features and product changes must be described with specificity in Notes for Review.
- Apple's product-page guidance says subtitle, description, keywords, and screenshots should emphasize specific features, functionality, and app value. The first one to three screenshots matter when no preview video is present.
- Apple says rejected submissions can be discussed in App Store Connect before resubmission, and appeals are appropriate when the developer believes Apple misunderstood the app concept or functionality.
- Apple Staff guidance for copycat/impersonation prevention recommends unique content/features, original representative screenshots, and authentic/verifiable developer and app information.

### Live App Store Connect State

Artifacts captured under this directory:
- `asc-review-submissions.json`
- `asc-review-submission-items.json`
- `asc-version-localizations.json`
- `asc-app-info-localizations.json`
- `asc-screenshots.json`
- `ouro-md-app-store-screenshot-1440x900.png`

Verified facts:
- App Store app id: `6787262892`
- Bundle id: `bot.ouro.md`
- App Store version id: `7309944f-cbe8-4518-960c-444e6116ab46`
- Review submission id: `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c`
- Review submission state: `UNRESOLVED_ISSUES`
- Review submission item state: `REJECTED`
- Version reviewed: `0.9.79 (0.9.79)`
- Live subtitle: `The Markdown App`
- Live review note: local Markdown editor, no account required
- One remote desktop screenshot exists and is complete.

API access is durable:
- Config: `/Users/arimendelow/Library/Application Support/AppleDistributionKit/app-store-connect/config.json`
- Key: referenced by the local Apple Distribution Kit config; do not commit the key filename or contents.
- `node /Users/arimendelow/Projects/apple-distribution-kit/dist/cli.js asc smoke --config ... --json` succeeds.

### Market Landscape

Public Mac App Store search artifacts:
- `itunes-markdown-editor-search.json`
- `itunes-markdown-preview-search.json`
- `itunes-markdown-notes-search.json`

Findings:
- The Mac App Store is crowded with apps using nearly identical positioning: simple/fast/focused Markdown editor, live preview, side-by-side layout, export to HTML/PDF, distraction-free writing, local files.
- The term "Markdown editor" alone is not differentiating. There are apps literally named "Markdown Editor", "MarkdownEdit", "Markdown.md", "Clearly Markdown", "FlowMD", "One Markdown", and several viewers/readers/Quick Look extensions.
- Distinctiveness for Ouro MD has to come from a narrower promise: a native local Markdown workspace for real files and folders, with command-palette operation, outline/file/search sidebars, themed rendering, wide-table handling, export, privacy/no-account posture, direct-download/App Store channel separation, and command-line render.

### Code And Binary Signals

Source evidence:
- `README.md` documents sidebar outline, file tree, folder search, command palette, multiple modes, themes, PDF/HTML export, pasted/dropped images, and `ouro-md --render`.
- `Sources/OuroMDAppSupport/CommandPaletteCatalog.swift` has a broad command catalog and searchable command palette.
- `Sources/OuroMD/Sidebar.swift` implements Outline, Files, and Search segmented sidebar modes.
- `Sources/OuroMD/ContentSearcher.swift` implements cancellable whole-folder text search with snippets.
- `Sources/OuroMD/Welcome.swift` already introduces folder opening and command palette, but its first paragraph still calls Ouro MD a minimalist Markdown editor.
- `Sources/OuroMD/AppInfoView.swift` and `Sources/OuroMD/OuroMDShellContract.swift` still use the generic subtitle `Markdown editor for fast local writing.`
- `docs/vditor-vendor-manifest.json` records a 529-file vendored Vditor distribution with an `unknown-pre-existing-vendored-dist` upstream version.

Risk interpretation:
- High confidence: generic metadata and a single generic screenshot created a weak 4.3(a) story.
- High confidence: live assets do not show the features most likely to distinguish Ouro MD.
- Medium confidence: the bundled Vditor distribution plus generic app presentation may contribute to a "repackaged editor template" signal.
- Low confidence: App Store category alone caused the rejection. Category should still be reviewed because Apple says category relevance matters.
- No evidence: Apple objected to privacy, encryption, crash, signing, or account/demo access.

## Recommended Positioning

This is a:
- local Markdown workspace for macOS files and folders.

It is for:
- technical writers, developers, agent operators, and Markdown-heavy users who keep work in plain files instead of a hosted notes account.

Instead of:
- a generic split-view Markdown editor or hosted notes/vault app.

It is different because:
- it treats local folders as the workspace, exposes outline/files/search as native sidebars, supports command-palette operation, keeps direct and App Store distribution channels separate, can export themed HTML/PDF, and can render from the command line.

That matters because:
- reviewers and users can see a specific workflow rather than "another Markdown editor": open a folder, navigate files, search content, command the editor, render/export without accounts or uploads.

Recommended subtitle:
- `Local Markdown Workspace`

Recommended promotional text:
- `A native Mac workspace for local Markdown files: outline, folder search, command palette, themes, PDF/HTML export, no account.`

Recommended keywords:
- `markdown,local files,folder search,outline,command palette,html export,pdf,commonmark,gfm,mac`

Recommended first description sentence:
- `Ouro MD is a local Markdown workspace for people who keep real files, not a hosted notes account.`

## Full Remediation Plan

### Phase 0: Preserve Evidence And Guardrails

Goal: make the rejection and future status reads reproducible without browser login.

Work:
- Keep the captured App Store Connect evidence in `worker/tasks/.../research/`.
- Add a source-owned status command or doc recipe that reads app/version/submission/item/screenshot state using the Apple Distribution Kit config.
- Ensure outputs are redacted and never include private keys, JWTs, cookies, Apple asset tokens, or raw contact/private account fields.

Acceptance:
- A local command can produce a summary with app id, version id, submission id, review state, rejected item state, live subtitle, localization id, review detail id, and screenshot count.

### Phase 1: Source-Owned Store Metadata

Goal: stop treating App Store metadata as loose text in docs.

Work:
- Extend `distribution/apple-distribution.json` or an adjacent source-owned metadata file to include subtitle, promotional text, description, keywords, support/marketing URLs, review notes, and screenshot proofs.
- Update `docs/APP_STORE.md` to make this source-owned metadata canonical.
- Update `scripts/check-apple-distribution-kit.sh` so review-prep checks fail when the manifest drifts back to generic or missing metadata.

Acceptance:
- The manifest/docs include non-generic metadata aligned to the recommended positioning.
- A focused validation test or script asserts subtitle length <= 30, promotional text <= 170, keywords <= 100, non-empty review notes, and screenshot proof.

### Phase 2: Screenshot And Optional Preview Set

Goal: make the first App Store visual impression show the real app, not a commodity editor.

Work:
- Replace the single generic screenshot with at least four desktop screenshots:
  1. Folder workspace: file tree sidebar plus rendered document.
  2. Command workflow: command palette visible with command results relevant to Markdown.
  3. Search and outline: search sidebar with snippets or outline sidebar with heading navigation.
  4. Themed export/readability: dark Graphite or Newsprint theme plus export-ready content.
- Use real checked-in fixtures, not private user content.
- Add local screenshot asset paths to the source-owned metadata and upload/verify them in App Store Connect.
- Optional: add one short app preview later, but do not block the first fix on video unless screenshot-only resubmission fails.

Acceptance:
- Local screenshot files exist and are listed in the manifest.
- App Store Connect reports the expected screenshot count and complete asset delivery state.
- The first screenshot no longer hides sidebar/search/command-palette value.

### Phase 3: Fresh Build With Visible Differentiation

Goal: answer Apple's "binary" wording with a new version that visibly carries the product distinction.

Work:
- Bump to a new patch version before resubmission.
- Change visible app copy in `Welcome.swift`, `AppInfoView.swift`, and `OuroMDShellContract.swift` from generic "Markdown editor" language to "local Markdown workspace" language.
- Add a small "Review path" note in the welcome/sample content or What's New that points reviewers to folder, outline, search, command palette, export, and no-account behavior.
- Consider reducing future template signals by pinning the Vditor upstream version in the vendor manifest during a later cleanup; do not refresh the vendor asset in the emergency fix unless necessary.

Acceptance:
- Tests pin the new About/shell subtitle and welcome language.
- Release highlights mention the App Store review-facing positioning and source-owned metadata checks.
- Build/package validation still passes.

### Phase 4: App Review Notes And Reply

Goal: give App Review a concise, verifiable reason to reconsider.

Work:
- Draft a reply in App Store Connect before resubmission:
  - Thank them for the review.
  - State that Ouro MD is not a repackaged third-party template or duplicate bundle.
  - Explain that it is a local macOS Markdown workspace for files and folders.
  - List 5-7 concrete review steps: open folder, use File Tree, Outline, Search, Command Palette, switch themes, export PDF/HTML, confirm no sign-in/account/server content.
  - Mention that metadata and screenshots were updated to reflect those features.
  - Avoid arguing that other apps exist or that Apple is wrong.
- Add the same reviewer-facing note to App Store Review Information for the new version.
- Under the 2026-07-09 autopilot mandate, require a harsh voice/posture reviewer gate and exact-state preflight before posting this reply or submitting; do not wait for another human approval unless a true Apple credential/capability blocker or unrecoverable destructive shared-production action is reached.

Draft:

```
Hello App Review,

Thank you for reviewing Ouro MD. We updated the submission to make the app's distinct functionality clearer in the metadata, screenshots, and review notes.

Ouro MD is not a repackaged template or duplicate bundle. It is a native macOS workspace for local Markdown files and folders. No account, sample login, subscription, or server-side content is required.

Suggested review path:
1. Open or create a Markdown file.
2. Open a folder with Shift-Command-O and use the File Tree sidebar.
3. Use the Outline sidebar to navigate headings.
4. Use folder Search to find text across Markdown files.
5. Open the Command Palette with Shift-Command-P.
6. Switch themes and export the document as PDF or self-contained HTML.
7. Confirm the App Store build has direct-download updates and telemetry disabled.

The app also includes a command-line render path for local Markdown documents, but the core user experience is fully available in the macOS app.
```

### Phase 5: Package, Upload, And Resubmit

Goal: submit the revised package without mutating Apple state blindly.

Work:
- Run local preflight and Apple distribution checks.
- Build and validate the App Store package using the existing signing/API credentials.
- Upload the new version.
- Verify App Store Connect processing state, version localization, review notes, screenshot assets, and review submission items programmatically.
- Submit only after source validation, packaging/upload verification, harsh reviewer-gate convergence, and exact-state preflight under the 2026-07-09 autopilot mandate.

Acceptance:
- API status summary shows the new processed build/version selected, updated metadata, screenshot count >= 4, and a new or updated review submission ready.

### Phase 6: If Rejected Again

Goal: avoid repeated same-guideline churn.

Work:
- If Apple repeats 4.3(a), reply asking for concrete clarification on whether the issue is binary similarity, metadata similarity, app concept, or account/developer identity.
- Request an App Review appointment if available.
- If the revised submission clearly addresses the concern and Apple gives no actionable detail, submit one appeal with specific reasons and evidence.
- Do not keep resubmitting minor metadata changes indefinitely; repeated same-guideline rejection can slow review.

Acceptance:
- A single evidence-backed escalation packet exists with sources, screenshots, binary/source differentiators, and the App Review correspondence timeline.

## Resolved Decisions

1. Use positioning phrase `Local Markdown Workspace`.
2. Submit a fresh build/version instead of editing only the rejected version metadata.
3. Use Ouro MD wrapper/check automation first; patch `apple-distribution-kit` only if the wrapper path proves insufficient.
4. Human gates are waived; final App Review reply, upload, and submission proceed after source validation, harsh sub-agent reviewer gates, and exact-state preflight.

## Threads Closed

- Rejection text: pulled from App Store Connect UI.
- API access: verified through local Apple Distribution Kit config.
- App Store live state: captured in artifacts.
- Public market saturation: captured through iTunes Search API artifacts.
- Submitted screenshot: downloaded and inspected.
- Source differentiators: verified from README and source files.

## Remaining Hard Exceptions

- Creating or rotating Apple credentials/certificates/provisioning profiles.
- Paid-account, signing, App Store Connect, or Apple-side capability blockers that cannot be worked around with the existing local config and account session.
- Unrecoverable destructive shared-production actions with no safe staged path.
