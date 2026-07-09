# Doing: Resolve App Store 4.3(a) Spam Rejection

**Status**: drafting
**Execution Mode**: direct
**Created**: 2026-07-09
**Planning**: ./2026-07-08-1918-planning-app-store-spam-rejection.md
**Artifacts**: ./2026-07-08-1918-doing-app-store-spam-rejection/

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
- [ ] Source-owned metadata recommends or encodes subtitle `Local Markdown Workspace`, a specific promotional text, specific keywords, and a review note that lists concrete reviewer steps.
- [ ] A local screenshot set exists with at least four review-facing screenshots and the first screenshots show differentiated app surfaces, not only a single rendered document.
- [ ] `scripts/check-apple-distribution-kit.sh` no longer reports screenshot proof as missing, or an explicit live-status path documents why remote proof is checked separately from CI.
- [ ] A redacted programmatic App Store review-status command can read app `6787262892`, version `7309944f-cbe8-4518-960c-444e6116ab46`, submission `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c`, rejected item state, and remote screenshot count from the local config.
- [ ] A new build/version carries visible in-app copy changes that align with the App Store positioning and can be cited in review notes.
- [ ] Any final App Review reply/review-note text passes a harsh voice/posture reviewer gate and exact-state preflight before posting or submission.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No warnings
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

### ⬜ Unit 0: Setup And Live State Baseline
**What**: Capture current repo/tooling/App Store Connect state into `./2026-07-08-1918-doing-app-store-spam-rejection/`, including `git status`, Xcode/Swift versions, current ASC app/version/submission/screenshot summaries via the local Apple Distribution Kit config, and a secrets scan of committed planning artifacts.
**Output**: Redacted baseline logs and JSON summaries in the artifacts directory.
**Acceptance**: Logs prove the worktree is on `worker/app-store-spam-rejection`, local API config works without printing secrets, the rejected submission state is still readable, and no private key/JWT/cookie/asset token appears in artifacts.

### ⬜ Unit 1a: Store Metadata Contract — Tests
**What**: Add failing tests or selftests that require source-owned App Store metadata to include subtitle `Local Markdown Workspace`, promotional text, description, keywords within Apple limits, review notes with concrete reviewer steps, non-empty screenshot assets, privacy/export compliance, and no generic `The Markdown App`/quiet-editor wording.
**Acceptance**: Focused tests fail red against the current manifest/docs/check script.

### ⬜ Unit 1b: Store Metadata Contract — Implementation
**What**: Update `distribution/apple-distribution.json`, `docs/APP_STORE.md`, and `scripts/check-apple-distribution-kit.sh` so the app-local desired state is non-generic, length-checked, screenshot-aware, and review-note-aware. Keep Ouro MD-specific metadata in this repo; do not move reusable behavior into the shared shell.
**Acceptance**: Unit 1a tests pass green, `./scripts/check-apple-distribution-kit.sh` no longer reports missing screenshot proof for declared local or remote screenshot assets, and docs name the source-owned metadata as canonical.

### ⬜ Unit 1c: Store Metadata Contract — Coverage And Review
**What**: Run coverage/validation for new contract code and a harsh sub-agent review of metadata posture, Apple guideline fit, and source-owned drift checks.
**Acceptance**: 100% coverage on new script/test branches, no warnings, reviewer returns `CONVERGED` or findings are fixed and re-reviewed.

### ⬜ Unit 2a: App-Visible Positioning — Tests
**What**: Add failing Swift tests or source-contract assertions for the About/shell subtitle, welcome copy, first-launch content, release highlights, and any App Store channel behavior needed to show `Local Markdown Workspace` and concrete folder/search/command/export/no-account value.
**Acceptance**: Focused tests fail red against the current generic welcome/about copy.

### ⬜ Unit 2b: App-Visible Positioning — Implementation
**What**: Update `Sources/OuroMD/Welcome.swift`, `Sources/OuroMD/AppInfoView.swift`, `Sources/OuroMD/OuroMDShellContract.swift`, `Sources/OuroMDCore/OuroMDRelease.swift`, and tests so visible app copy aligns with the App Store metadata and review path. Bump to the next patch version with `scripts/bump-version.sh` before packaging.
**Acceptance**: Unit 2a tests pass green, release version and manifest version match, and app-owned copy no longer presents Ouro MD as merely a generic Markdown editor.

### ⬜ Unit 2c: App-Visible Positioning — Build, Coverage, And Visual QA
**What**: Run focused Swift tests, `swift test`, `./make-app.sh`, `./scripts/run-visual-qa.sh`, `--firstlaunchtest`, `--uisurfacetest`, and `--accessibilityaudit`; capture screenshots/logs and maintain an absurdity ledger.
**Acceptance**: Tests/build/visual QA pass, ledger has no `ready` or `needs reviewer gate` items, and a harsh UI/native reviewer gate converges.

### ⬜ Unit 3a: App Store Connect Status And Mutation Automation — Tests
**What**: Add failing tests/selftests for a source-owned App Store Connect wrapper that can summarize live state and build exact outgoing request plans for metadata/review-detail/screenshot/submission operations without sending them in dry-run mode. Adapter tests must assert outgoing request method, path, query/body, and redaction.
**Acceptance**: Tests fail red because the wrapper/plan command does not yet exist or lacks the required request-shape assertions.

### ⬜ Unit 3b: App Store Connect Status And Mutation Automation — Implementation
**What**: Implement the wrapper/check path in Ouro MD first, using the local Apple Distribution Kit config and shared kit where possible. The command must support redacted status, dry-run request plan, apply mode with explicit exact-state preflight, and artifacts for metadata, review notes, screenshots, build selection, review-submission items, and final submit. Patch `apple-distribution-kit` only if the wrapper cannot safely perform the required App Store Connect calls.
**Acceptance**: Unit 3a tests pass green, `scripts/check-apple-distribution-kit.sh` invokes or references the new status path, and dry-run artifacts show the exact requests without secrets.

### ⬜ Unit 3c: App Store Connect Status And Mutation Automation — Coverage And API Review
**What**: Run full coverage for new automation code and a harsh API/adaptor reviewer gate focused on outgoing request shapes, idempotency, redaction, and safe exact-state preflight.
**Acceptance**: 100% coverage on new code, no secret-bearing artifacts, and reviewer converges.

### ⬜ Unit 4a: Screenshot Asset Set — Tests
**What**: Add failing checks for at least four App Store screenshot assets generated from non-private fixtures and declared in the manifest in the intended order: folder workspace, command palette, search/outline, and themed export/readability.
**Acceptance**: The check fails red until assets and manifest entries exist.

### ⬜ Unit 4b: Screenshot Asset Set — Implementation
**What**: Add store screenshot fixtures and a deterministic screenshot generation/copy script that produces PNGs under a source-owned store asset path. Prefer real app/editor rendering and synthetic checked-in Markdown content. Do not commit private user documents or App Store asset tokens.
**Acceptance**: At least four valid PNG assets exist locally, manifest order matches the intended review story, file sizes/dimensions are accepted by the checker, and the first asset visibly shows a differentiated workspace rather than a single rendered document only.

### ⬜ Unit 4c: Screenshot Asset Set — Visual QA And Review
**What**: Run visual QA on generated screenshots, inspect them directly, write an absurdity ledger, and run a harsh visual reviewer gate.
**Acceptance**: Ledger closed, reviewer converges, and final screenshots are ready for App Store Connect upload.

### ⬜ Unit 5a: Package And Upload Preflight — Tests
**What**: Add or update checks that package/readiness commands prove App Store distribution channel, telemetry disabled by default, direct updates disabled, version coherence, and no signing secret leakage.
**Acceptance**: Focused checks fail red for any missing new preflight evidence or stale metadata assumptions.

### ⬜ Unit 5b: Package And Upload Preflight — Implementation
**What**: Make package/readiness scripts produce artifacts sufficient for final submission: manifest validation, package readiness, signed package path, altool validation, and upload logs. Use existing local signing/API credentials; stop only for true missing Apple credential/capability blockers.
**Acceptance**: Focused checks pass, `./scripts/package-app-store.sh --readiness` passes, App Store package builds and validates, and upload succeeds or a precise Apple capability blocker artifact is produced.

### ⬜ Unit 5c: Package And Upload Preflight — Build/Validation Review
**What**: Run native validation matrix rows relevant to macOS App Store: `xcodebuild -version`, `swift --version`, Swift tests, macOS build/package, package validation, and a harsh build/release reviewer gate.
**Acceptance**: No warnings in final green logs, reviewer converges, and uploaded build can be discovered or a real Apple-side processing blocker is recorded.

### ⬜ Unit 6a: App Store Connect Apply — Dry Run And Reviewer Gates
**What**: Generate exact-state dry-run artifacts for metadata update, screenshot upload/update, review details, build association, review-submission item creation, App Review reply/note, and final submit. Run harsh reviewers for voice/posture and API mutation safety.
**Acceptance**: Dry-run artifacts identify exact app/version/build/submission IDs, request bodies, screenshot count, review notes, and final submit action; reviewers converge.

### ⬜ Unit 6b: App Store Connect Apply — Metadata, Screenshots, Build, And Submit
**What**: Apply the verified App Store Connect operations: update metadata, upload/verify screenshots, attach processed build/version, create/update review submission items, post the reviewer-facing note if supported by API/UI, and submit the new version for review. Use Chrome UI automation only as a fallback for ASC surfaces not exposed by the available API, and capture evidence.
**Acceptance**: App Store Connect reports the new version/build submitted for review with updated metadata/review notes, screenshot count >= 4, and no unresolved local automation blockers.

### ⬜ Unit 6c: App Store Connect Apply — Post-Submit Verification
**What**: Poll App Store Connect status programmatically after submission and capture redacted final state.
**Acceptance**: Artifact shows submitted/in-review equivalent state for the new submission, selected build/version, updated localization/review detail data, and screenshot assets complete; or a precise hard blocker is documented after all safe fallback paths.

### ⬜ Unit 7: Final Cleanup, Merge Path, And Continuation Scan
**What**: Update completion criteria, doing progress log, `AUTOPILOT-STATE.md`, run final harsh branch review, push all commits, open/merge PR or follow repo terminal path, clean stale worktree/branches if safe, and run continuation scan.
**Output**: Final verification artifacts and clean repo state.
**Acceptance**: Branch has no dirty state, submission terminal evidence is captured, reviewer gate converges, and no ready in-scope continuation work remains except true hard exceptions.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- For UI/rendering/layout units, run `visual-qa-dogfood` before declaring the unit or task complete
- **All artifacts**: Save outputs, logs, data to `./2026-07-08-1918-doing-app-store-spam-rejection/` directory
- **Fixes/blockers**: Spawn sub-agent immediately — don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- 2026-07-09 Created from approved planning doc.
