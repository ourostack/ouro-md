# Doing: Resolve App Store 4.3(a) Spam Rejection

**Status**: in-progress
**Execution Mode**: direct
**Created**: 2026-07-09
**Planning**: ./2026-07-08-1918-planning-app-store-spam-rejection.md
**Artifacts**: /Users/arimendelow/Projects/ouro-md-app-store-spam-rejection/worker/tasks/2026-07-08-1918-doing-app-store-spam-rejection/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts only when the user explicitly requested interactive per-unit approval; otherwise convert this to `spawn` or `direct` unless a hard exception is present
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Resolve the App Store Connect rejection for Ouro MD macOS by making a new submission clearly distinguish Ouro MD from generic or repackaged Markdown apps across binary-visible product copy, source-owned metadata, screenshots, review notes, and programmatic review-status checks.

## Upstream Work Items
- `/Users/arimendelow/desk/ouro-md/app-store-connect-submission/task.md`

## Completion Criteria
- [ ] App Review evidence is captured in docs or artifacts with no secrets and with concrete dates, app IDs, submission IDs, and version IDs.
- [ ] Source-owned App Store metadata/review-note guidance no longer describes Ouro MD generically as only "The Markdown App" or a quiet Markdown editor.
- [ ] Source-owned metadata recommends or encodes subtitle `Local Markdown Workspace`, Developer Tools category, a specific promotional text, specific keywords, and a review note that lists concrete reviewer steps.
- [ ] A local screenshot set exists with at least four review-facing screenshots and the first screenshots show differentiated app surfaces, not only a single rendered document.
- [ ] `scripts/check-apple-distribution-kit.sh` no longer reports screenshot proof as missing, or an explicit live-status path documents why remote proof is checked separately from CI.
- [x] A redacted programmatic App Store review-status command can read app `6787262892`, version `7309944f-cbe8-4518-960c-444e6116ab46`, submission `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c`, rejected item state, and remote screenshot count from the local config.
- [ ] A new build/version carries visible in-app copy changes that align with the App Store positioning and can be cited in review notes.
- [ ] Any final App Review reply/review-note text passes a harsh voice/posture reviewer gate and exact-state preflight before posting or submission.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No unresolved/actionable warnings in final green logs; any benign Apple/Xcode/altool warning is recorded with reviewer-approved rationale.
- [ ] If UI/rendering/layout changed: `visual-qa-dogfood` evidence captured, absurdity ledger closed, and automated visual metrics still pass

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch, try/catch)
- All error paths tested
- Edge cases: null, empty, boundary values

## TDD Requirements
**Strict TDD — no exceptions:**
1. **Tests first**: Write failing tests BEFORE any implementation
2. **Verify failure**: Run tests, confirm they FAIL (red)
3. **Minimal implementation**: Write just enough code to pass
4. **Verify pass**: Run tests, confirm they PASS (green)
5. **Refactor**: Clean up, keep tests green
6. **No skipping**: Never write implementation without failing test first

## Work Units

### Legend
⬜ Not started · 🔄 In progress · ✅ Done · ❌ Blocked

**CRITICAL: Every unit header MUST start with status emoji (⬜ for new units).**

### ✅ Unit 0: Setup And Live State Baseline
**What**: Capture current repo/tooling/App Store Connect state into `/Users/arimendelow/Projects/ouro-md-app-store-spam-rejection/worker/tasks/2026-07-08-1918-doing-app-store-spam-rejection/`, including `git status`, Xcode/Swift versions, current ASC app/version/submission/screenshot summaries via the local Apple Distribution Kit config, and a secrets scan of committed planning artifacts.
**Output**: Redacted baseline logs and JSON summaries in the artifacts directory.
**Acceptance**: Logs prove the worktree is on `worker/app-store-spam-rejection`, local API config works without printing secrets, the rejected submission state is still readable, and no private key/JWT/cookie/asset token appears in artifacts.

### ✅ Unit 1a: Store Metadata Contract — Tests
**What**: Add failing tests or selftests that require source-owned App Store metadata to include subtitle `Local Markdown Workspace`, Developer Tools category, promotional text, description, keywords within Apple limits, review notes with concrete reviewer steps, non-empty screenshot assets, privacy/export compliance, and no generic `The Markdown App`/quiet-editor wording.
**Output**: Failing test/script diff plus red log saved under the artifacts directory.
**Acceptance**: Focused tests fail red against the current manifest/docs/check script.

### ✅ Unit 1b: Store Metadata Contract — Implementation
**What**: Update `distribution/apple-distribution.json`, `docs/APP_STORE.md`, and `scripts/check-apple-distribution-kit.sh` so the app-local desired state is non-generic, length-checked, screenshot-aware, and review-note-aware. Keep Ouro MD-specific metadata in this repo; do not move reusable behavior into the shared shell.
**Output**: Updated manifest/docs/check script and green focused validation log.
**Acceptance**: Unit 1a tests pass green, `./scripts/check-apple-distribution-kit.sh` no longer reports missing screenshot proof for declared local or remote screenshot assets, and docs name the source-owned metadata as canonical.

### ✅ Unit 1c: Store Metadata Contract — Coverage And Review
**What**: Run coverage/validation for new contract code and a harsh sub-agent review of metadata posture, Apple guideline fit, category choice, and source-owned drift checks.
**Output**: Coverage/validation logs plus reviewer transcript or summary in the artifacts directory.
**Acceptance**: 100% coverage on new script/test branches, no warnings, reviewer returns `CONVERGED` or findings are fixed and re-reviewed.

### ✅ Unit 2a: App-Visible Positioning — Tests
**What**: Add failing Swift tests or source-contract assertions for the About/shell subtitle, welcome copy, first-launch content, release highlights, and any App Store channel behavior needed to show `Local Markdown Workspace` and concrete folder/search/command/export/no-account value.
**Output**: Failing Swift test diff plus red focused test log.
**Acceptance**: Focused tests fail red against the current generic welcome/about copy.

### ✅ Unit 2b: App-Visible Positioning — Implementation
**What**: Update `Sources/OuroMD/Welcome.swift`, `Sources/OuroMD/AppInfoView.swift`, `Sources/OuroMD/OuroMDShellContract.swift`, `Sources/OuroMDCore/OuroMDRelease.swift`, and tests so visible app copy aligns with the App Store metadata and review path. Target source/manifest version is `0.9.80`; bump with `scripts/bump-version.sh` to the next unused patch version if App Store Connect proves `0.9.80` has an unusable non-editable/non-creatable App Store version state, an already-uploaded/consumed processed build collision, or any other Apple-side version/build uniqueness blocker.
**Output**: Updated Swift source/tests/version files plus green focused test log.
**Acceptance**: Unit 2a tests pass green, release version and manifest version match, and app-owned copy no longer presents Ouro MD as merely a generic Markdown editor.

### ✅ Unit 2c: App-Visible Positioning — Build, Coverage, And Visual QA
**What**: Run focused Swift tests, `swift test`, `./make-app.sh`, `./scripts/run-visual-qa.sh`, `.build/debug/ouro-md --firstlaunchtest`, `.build/debug/ouro-md --uisurfacetest`, and `.build/debug/ouro-md --accessibilityaudit`; capture screenshots/logs and maintain an absurdity ledger.
**Output**: Build/test/visual logs, any captured screenshots, and `visual-absurdity-ledger.md`.
**Acceptance**: Tests/build/visual QA pass, ledger has no `ready` or `needs reviewer gate` items, and a harsh UI/native reviewer gate converges.

### ✅ Unit 3a: App Store Connect Status Reader — Tests
**What**: Add failing tests/selftests for a source-owned status command that reads app `6787262892`, bundle `bot.ouro.md`, current version/localization/review-detail/screenshot/submission state via the local Apple Distribution Kit config and redacts secrets.
**Output**: Failing test/selftest diff plus red log.
**Acceptance**: Tests fail red because the status command does not yet exist or does not assert redaction/required fields.

### ✅ Unit 3b: App Store Connect Status Reader — Implementation
**What**: Implement the Ouro MD wrapper/status command using `scripts/apple-distribution-kit.sh asc get` where sufficient, producing normalized redacted JSON and a compact text summary.
**Output**: New or updated script/test files plus green focused logs and a sample redacted status artifact.
**Acceptance**: Unit 3a tests pass green, status artifacts include app id, bundle id, version id, review detail id, screenshot count/state, and current rejection/submission state without secrets.

### ✅ Unit 3c: App Store Connect Status Reader — Coverage And Review
**What**: Run coverage/validation and a harsh reviewer gate focused on redaction, stale-state handling, and exact App Store Connect identifiers.
**Output**: Coverage/validation logs and reviewer transcript or summary.
**Acceptance**: 100% coverage on new status code, no secret-bearing artifacts, and reviewer converges.

### ⬜ Unit 4a: App Store Connect Request Planner — Tests
**What**: Add failing adapter-pattern tests for dry-run request planning. Tests must capture and assert outgoing request method/path/query/body for app version create/fetch, version localization, app info localization subtitle/category, review detail notes, screenshot set discovery/creation under the new version localization and display type `APP_DESKTOP`, screenshot reservations/uploads/commits, build association, review submission record creation, review submission item creation linking the new `appStoreVersion`, optional existing rejection-thread reply plan, and final submit.
**Output**: Failing request-shape tests plus red log naming the first missing planner behavior.
**Acceptance**: Tests fail red for missing request planner or incomplete outgoing-request assertions.

### ⬜ Unit 4b: App Store Connect Request Planner — Implementation
**What**: Implement the Ouro MD request planner and dry-run artifact generator. Authorized target scope is only app `6787262892`, bundle `bot.ouro.md`, team `743GT2AJ24`, target App Store version `0.9.80` unless Unit 2b recorded a required next-patch bump, the processed build for that version, app info category, app/version localizations, app review detail notes, screenshot assets for the new version localization, review submission record/items, optional existing rejection-thread reply, and final submit. The planner must create or fetch the target App Store version, localization, review detail, screenshot set, review submission, and review submission items before later units apply mutations. Patch `/Users/arimendelow/Projects/apple-distribution-kit` only if the wrapper cannot safely sign/request/capture required ASC calls; if patched, use branch `worker/ouro-md-app-store-submit`, run that repo's tests, commit, and push.
**Output**: Request planner implementation, dry-run JSON artifact, green tests, and either a wrapper-suffices note or shared-kit patch evidence.
**Acceptance**: Unit 4a tests pass green, dry-run artifacts show exact requests without secrets, and guards reject stale rejected-version IDs `7309944f-cbe8-4518-960c-444e6116ab46`, `5dca4b0b-3e0d-4913-acbd-b172f6c1bacb`, `3bc7284e-27d5-4dd3-a049-b9e859289bd1`, `f37ecb51-c96e-451d-9b29-20d86d7f118e`, and `80a8620a-643a-46bd-9e39-ab19f26ba424` for new-version localization/review-detail/screenshot/build/submission operations unless an artifact proves Apple reused the object under the target version. Any shared-kit patch has its own green `npm test`/equivalent log.

### ⬜ Unit 4c: App Store Connect Request Planner — Coverage And API Review
**What**: Run full coverage for new automation code and a harsh API/adaptor reviewer gate focused on outgoing request shapes, idempotency, redaction, Apple upload-operation handling, and exact-state preflight.
**Output**: Coverage logs, API reviewer transcript or summary, and final dry-run request artifact.
**Acceptance**: 100% coverage on new code, no secret-bearing artifacts, and reviewer converges.

### ⬜ Unit 4d: App Store Connect Mutation Executor — Tests
**What**: Add failing adapter-pattern tests for apply-mode execution. Tests must prove explicit mode gates, response capture, redaction, idempotent fetch-or-create behavior, retryable error classification, screenshot upload-operation execution with checksum/file-size/body upload assertions, asset-token redaction, and final-submit request execution.
**Output**: Failing executor tests plus red log.
**Acceptance**: Tests fail red until a mutation executor captures/asserts the actual outgoing HTTP requests and upload operations rather than only canned responses.

### ⬜ Unit 4e: App Store Connect Mutation Executor — Implementation
**What**: Implement apply-mode execution behind explicit `--mode apply` and exact-state preflight. Support JSON API requests, screenshot binary upload operations returned by Apple, response redaction, idempotent fetch-or-create for version/localization/review-detail/screenshot-set/review-submission objects, and artifact writing for every live request/response.
**Output**: Executor implementation, green executor tests, and dry-run/apply-preflight sample artifacts from a non-mutating fake transport.
**Acceptance**: Unit 4d tests pass green, mutation executor cannot run without reviewed dry-run/preflight artifacts, and no secret/asset token/private key is emitted in logs.

### ⬜ Unit 4f: App Store Connect Mutation Executor — Coverage And Review
**What**: Run coverage and a harsh API/executor reviewer gate focused on mode gating, idempotency, upload-operation correctness, redaction, and stale-object guards.
**Output**: Coverage logs and reviewer transcript or summary.
**Acceptance**: 100% coverage on new executor code and reviewer converges.

### ⬜ Unit 5a: Screenshot Asset Set — Tests
**What**: Add failing checks for at least four App Store screenshot assets generated from non-private fixtures and declared in the manifest in the intended order: folder workspace, command palette, search/outline, and themed export/readability.
**Output**: Failing asset/manifest check plus red log.
**Acceptance**: The check fails red until assets and manifest entries exist.

### ⬜ Unit 5b: Screenshot Asset Set — Implementation
**What**: Add store screenshot fixtures and a deterministic screenshot generation/copy script that produces PNGs under a source-owned store asset path. Prefer real app/editor rendering and synthetic checked-in Markdown content. Do not commit private user documents or App Store asset tokens.
**Output**: Screenshot fixtures, generation script, at least four PNG assets, manifest entries, and green asset-check log.
**Acceptance**: At least four valid PNG assets exist locally, manifest order matches the intended review story, file sizes/dimensions are accepted by the checker, and the first asset visibly shows a differentiated workspace rather than a single rendered document only.

### ⬜ Unit 5c: Screenshot Asset Set — Visual QA And Review
**What**: Run visual QA on generated screenshots, inspect them directly, write an absurdity ledger, and run a harsh visual reviewer gate.
**Output**: Final screenshots, screenshot inspection notes, `screenshot-absurdity-ledger.md`, and reviewer transcript or summary.
**Acceptance**: Ledger closed, reviewer converges, and final screenshots are ready for App Store Connect upload.

### ⬜ Unit 6a: Package Readiness Contract — Tests
**What**: Add or update checks that package/readiness commands prove App Store distribution channel, telemetry disabled by default, direct updates disabled, version coherence, and no signing secret leakage.
**Output**: Failing readiness test/check plus red log.
**Acceptance**: Focused checks fail red for any missing new preflight evidence or stale metadata assumptions.

### ⬜ Unit 6b: Package Readiness Contract — Implementation
**What**: Make package/readiness scripts produce artifacts sufficient for final submission: manifest validation, package readiness, signing identity check, target version/build uniqueness preflight, app-store channel proof, telemetry-disabled proof, and no-secret scan.
**Output**: Updated scripts/checks and green `./scripts/check-apple-distribution-kit.sh` plus `./scripts/package-app-store.sh --readiness` logs.
**Acceptance**: Focused checks pass, readiness logs do not print secrets, and any missing signing/cert/profile/API capability or target-version/build collision is recorded as a hard blocker or next-patch bump artifact with exact command output.

### ⬜ Unit 6c: Package Build, Validate, And Upload
**What**: Run native validation matrix rows relevant to macOS App Store: `xcodebuild -version`, `swift --version`, Swift tests, `./make-app.sh`, `./scripts/package-app-store.sh --validate`, and `./scripts/package-app-store.sh --upload` with existing local signing/API credentials. If upload or ASC processing proves the chosen version/build is already consumed or otherwise collides, bump to the next unused patch version, rerun source/version checks, rebuild, validate, and upload before continuing.
**Output**: Package path, signed-app verification logs, altool validation/upload logs, and upload/build-processing status artifacts.
**Acceptance**: No unresolved/actionable warnings in final green logs, package upload succeeds and the uploaded build can be discovered in App Store Connect for the final target version, or a real Apple-side credential/capability/processing blocker artifact is recorded.

### ⬜ Unit 6d: Package And Upload — Release Review
**What**: Run a harsh build/release reviewer gate on package, validation, upload, signing, version, and artifact evidence.
**Output**: Reviewer transcript or summary plus any fix commits/logs.
**Acceptance**: Reviewer converges and no unresolved local packaging/upload blockers remain.

### ⬜ Unit 7a: App Store Connect Apply — Exact-State Dry Run
**What**: Generate exact-state dry-run artifacts for target version create/fetch, localization/review-detail/screenshot-set discovery or creation, app category verification/update, metadata update, screenshot upload/update, build association, review submission record and item creation, App Review thread reply if available, review notes, and final submit.
**Output**: Dry-run request artifact that names app id, bundle id, team id, target version string, new or reused version id, processed build id, localization ids, screenshot set ids, screenshot display type, review detail id, review submission id/item ids, existing unresolved submission `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c`, planned reply/note handling, and expected final state.
**Acceptance**: Dry-run artifacts identify exact app/version/build/submission IDs, request bodies, screenshot count, review notes, review submission graph, and final submit action without secrets; the artifact explicitly states whether the old rejection thread will receive a reply through API/UI fallback or why review notes on the new submission are the only supported surface.

### ⬜ Unit 7b: App Store Connect Apply — Voice And API Reviewer Gates
**What**: Run harsh voice/posture and API mutation safety reviewers against the dry-run artifacts and final App Review note. The note must not overclaim "not a repackaged template"; it should make verifiable claims about Ouro MD's native macOS windowing, local folder workflow, command palette, outline/search sidebars, export, no-account behavior, and third-party renderer attribution/provenance if mentioned.
**Output**: Reviewer transcripts or summaries and fixed dry-run artifacts if findings require changes.
**Acceptance**: Reviewers converge. BLOCKER/MAJOR findings are fixed and re-reviewed before any live mutation.

### ⬜ Unit 7c: App Store Connect Apply — Version Graph
**What**: Create or fetch the target App Store version graph: target version string `0.9.80` unless Unit 2b required `0.9.81`, app store version, version localization, app info localization, review detail, macOS screenshot set, and review submission record/item skeletons. Resolve the existing unresolved rejected submission by posting a reviewed reply when API/UI supports it, or record an artifact proving the only supported path is the new submission's review notes.
**Output**: Version-graph apply logs, created/fetched object IDs, rejection-thread reply evidence or unsupported-surface artifact, and post-apply status JSON.
**Acceptance**: Target version graph IDs are captured and are not the stale rejected-version IDs unless Apple explicitly returns the same objects for the target version; existing unresolved submission lifecycle handling is recorded before metadata/screenshot/build/final-submit units proceed.

### ⬜ Unit 7d: App Store Connect Apply — Metadata, Category, And Review Detail
**What**: Apply only metadata, category, and review-detail updates that passed Unit 7b against the target version graph from Unit 7c. Exact-state preflight must match app id `6787262892`, bundle id `bot.ouro.md`, team id `743GT2AJ24`, target version string, and captured target localization/review-detail IDs before sending.
**Output**: Apply logs and post-apply status JSON for app info localization/category, app store version localization, and app review detail notes.
**Acceptance**: App Store Connect returns Developer Tools category if category is API-visible, updated subtitle/description/keywords/promotional text/review notes matching the manifest, and proof that localization/review-detail IDs belong to the target version; otherwise a precise hard blocker or fixable API error is recorded and handled.

### ⬜ Unit 7e: App Store Connect Apply — Screenshots
**What**: Upload or replace the approved screenshot assets for the target macOS screenshot set using Apple upload operations. Use source checksum and file size, execute binary upload operations exactly as returned, commit/complete the screenshot resource when required, poll `assetDeliveryState`, preserve intended order, and redact asset tokens.
**Output**: Screenshot create/upload/commit logs, delivery-state JSON, checksum/file-size summaries, screenshot set relationship/display-type proof, and screenshot count/order summary.
**Acceptance**: App Store Connect reports screenshot count >= 4 with complete asset delivery state, first screenshots match approved local asset names/order, screenshot set relationship points to the target app store version localization and `screenshotDisplayType` is `APP_DESKTOP`, no stale rejected-version screenshot set/screenshot IDs are used without proof of target-version ownership, and no asset token is committed.

### ⬜ Unit 7f: App Store Connect Apply — Build Association And Review Items
**What**: Associate the processed uploaded build with the target App Store version and create/update review submission item records linking the review submission record to the target `appStoreVersion`.
**Output**: Build association logs, review-submission-record/item logs, and post-apply status JSON.
**Acceptance**: The target version has the uploaded build selected, review submission items reference that target app store version/build, the review submission graph includes a create/fetch record plus item relationship, and exact-state artifacts contain no secrets.

### ⬜ Unit 7g: App Store Connect Apply — Final Submit
**What**: Submit the target App Store review submission only after Units 7a-7f pass, `./scripts/check-apple-distribution-kit.sh --final-submission` passes, and the final preflight artifact shows all intended state fields already match except submission state. Use Chrome UI automation only as a fallback for ASC surfaces not exposed by the available API, and capture evidence.
**Output**: Final submit log, submitted review submission id, and immediate post-submit status JSON.
**Acceptance**: App Store Connect reports the new version/build submitted for review, or a precise hard blocker is documented after all safe fallback paths.

### ⬜ Unit 7h: App Store Connect Apply — Post-Submit Verification
**What**: Poll App Store Connect status programmatically after submission and capture redacted final state.
**Output**: Redacted final App Store Connect state artifact and compact text summary.
**Acceptance**: Artifact shows submitted/in-review equivalent state for the new submission, selected build/version, updated localization/review detail data, and screenshot assets complete; or a precise hard blocker is documented after all safe fallback paths.

### ⬜ Unit 8a: Final Evidence And Docs
**What**: Update completion criteria, doing progress log, planning/doc references, and `/Users/arimendelow/Projects/ouro-md-app-store-spam-rejection/worker/tasks/AUTOPILOT-STATE.md` with terminal evidence.
**Output**: Updated docs/state and final artifact index.
**Acceptance**: Docs point to the submitted App Store evidence, all satisfied checkboxes are backed by artifacts, and no stale `drafting`/human-gate language remains.

### ⬜ Unit 8b: Final Branch Review And Push
**What**: Run final harsh branch review over all diffs, validation artifacts, and App Store submission evidence; fix/re-review BLOCKER/MAJOR findings; push all commits.
**Output**: Reviewer transcript or summary, final commits, and pushed branch state.
**Acceptance**: Reviewer converges, branch is pushed, and `git status --short` is clean.

### ⬜ Unit 8c: PR/Merge Or Repo Terminal Path
**What**: Follow the repo terminal path: open/merge a PR if branch protection requires it, or otherwise land the branch according to repository practice after reviewer convergence and green checks.
**Output**: PR/merge/check evidence, or documented non-PR terminal path evidence.
**Acceptance**: Source changes are landed or a true branch-protection/account blocker is recorded with exact evidence.

### ⬜ Unit 8d: Cleanup And Continuation Scan
**What**: Remove only task-created disposable artifacts that are untracked and outside committed evidence; do not delete shared worktrees/branches unless they are task-created, fully pushed/merged, clean, and not the current worktree. Run continuation scan.
**Output**: Cleanup log and continuation scan in `/Users/arimendelow/Projects/ouro-md-app-store-spam-rejection/worker/tasks/AUTOPILOT-STATE.md`.
**Acceptance**: No ready in-scope continuation work remains except true hard exceptions, no dirty state remains, and no task-created stale worktree/branch remains when safe to clean.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- For UI/rendering/layout units, run `visual-qa-dogfood` before declaring the unit or task complete
- **All artifacts**: Save outputs, logs, data to `/Users/arimendelow/Projects/ouro-md-app-store-spam-rejection/worker/tasks/2026-07-08-1918-doing-app-store-spam-rejection/`
- **Fixes/blockers**: Spawn sub-agent immediately — don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away
- **Target version**: use `0.9.80` unless App Store Connect proves it already exists in a state that cannot be reused/edited for this resubmission, or upload/processing proves the build/version is already consumed/colliding; in that case bump source/manifest/docs to the next unused patch version before packaging and record the evidence.
- **Authorized live Apple mutations**: only mutate app `6787262892`, bundle `bot.ouro.md`, team `743GT2AJ24`, target version `0.9.80` or recorded next-patch fallback, app info category, that version's processed build, localizations, review detail notes, screenshot assets, review submission record/items, optional existing rejection-thread reply, and final review submission state.
- **Hard stops**: stop only for missing/expired Apple credentials, missing signing identities/certificates/provisioning profiles, Apple account/legal/capability blockers, or unrecoverable destructive shared-production actions with no safe staged path. Do not create/delete/rotate Apple keys, certificates, provisioning profiles, bundle IDs, app records, or unrelated submissions.
- **Exact-state preflight before live apply**: app id, bundle id, team id, target version, app store version id, processed build id, localization ids, review detail id, screenshot set id, screenshot set `appStoreVersionLocalization` relationship, screenshot display type `APP_DESKTOP`, review submission id/item ids, metadata fields, app category, review note, screenshot asset paths/checksums/file sizes/count/order, `./scripts/check-apple-distribution-kit.sh --final-submission`, and final request plan must match the reviewed dry-run artifacts before any live apply or submit request.

## Progress Log
- 2026-07-09 Created from approved planning doc.
- 2026-07-09 Addressed doing-doc reviewer findings: explicit outputs, smaller ASC mutation units, absolute artifact path, exact live-mutation boundary, and continuity path.
- 2026-07-09 Addressed scrutiny findings: explicit target version, version/submission graph creation, existing rejection-thread handling, apply-mode executor tests, Apple screenshot upload choreography, stale-ID guards, category assertion, softened review-note posture, and actionable-warning acceptance.
- 2026-07-09 Removed remaining overbroad review-note provenance wording and aligned warning acceptance across docs.
- 2026-07-09 Addressed second scrutiny findings: added stale localization/review-detail guards, explicit `APP_DESKTOP` screenshot-set proof, app category mutation authority, and next-unused-patch fallback for build/version collisions.
- 2026-07-09 Doing-doc reviewer chain converged; started Unit 0.
- 2026-07-09 Unit 0 complete: captured redacted repo/tooling/App Store Connect baseline and artifact secret scan.
- 2026-07-09 Unit 1a complete: added metadata contract test and captured expected red failure for missing App Store metadata fields.
- 2026-07-09 Unit 1b complete: added source-owned App Store metadata, docs, and distribution preflight checks; focused metadata test and Apple distribution check pass.
- 2026-07-09 Unit 1c complete: extracted App Store metadata validator, added selftests for draft/final screenshot gates, wired `./scripts/check-apple-distribution-kit.sh --final-submission`, captured normal-pass and strict-red proof logs, and harsh reviewer gate converged.
- 2026-07-09 Unit 2a complete: added app-visible positioning tests for shell/About subtitle, welcome copy, and release highlights; focused suite fails red against generic current copy.
- 2026-07-09 Unit 2b complete: updated About/shell subtitle, first-launch welcome copy, release highlights, and CLI help to local-workspace positioning; focused positioning, shell, release, distribution metadata, and Apple distribution checks pass.
- 2026-07-09 Unit 2c complete: full Swift tests, app build, visual QA, first-launch, UI-surface, accessibility, exact welcome snapshot, absurdity ledger, and harsh UI/native reviewer gate passed after review fixes for user-facing release highlights and tracked fixture drift.
- 2026-07-09 Unit 3a complete: added failing App Store Connect status-reader tests requiring normalized app/version/submission/screenshot fields and redaction; focused suite fails red because `scripts/app-store-status.mjs` is not implemented.
- 2026-07-09 Unit 3b complete: implemented `scripts/app-store-status.mjs` with JSON and compact text modes over shared-kit `asc get`, added redaction/missing-field selftests, captured live redacted status for rejected version `0.9.79`, and kept Apple distribution checks green.
- 2026-07-09 Unit 3c complete: expanded status-reader tests to cover redaction, stale-id guards, explicit rejected-audit mode, review-item version relationships, `APP_DESKTOP` screenshot proof, and `COMPLETE` screenshot delivery state; live rejected-audit artifacts and harsh reviewer re-review passed.
