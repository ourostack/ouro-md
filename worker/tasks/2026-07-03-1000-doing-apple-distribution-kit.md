# Doing: Apple Distribution Kit Program

**Status**: drafting
**Execution Mode**: direct
**Created**: 2026-07-03 11:50
**Planning**: ./2026-07-03-1000-planning-apple-distribution-kit.md
**Artifacts**: ./2026-07-03-1000-doing-apple-distribution-kit/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts (non-autopilot interactive mode only; autopilot must convert this to `spawn` or `direct` unless a hard exception is present)
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Create a reusable, app-neutral Apple distribution system that can drive signing, notarization, Mac App Store packaging, upload, metadata, processing checks, and review submission for Ouro MD first and later Ouro Workbench, Spoonjoy, and non-Ouro native apps. The system must replace brittle browser driving with a deterministic reconciler plus local Xcode/Apple CLI runner, while naming the few Apple-account actions that truly require a human.

## Upstream Work Items
- `/Users/arimendelow/desk/ouro-md/app-store-connect-submission/task.md`

## Completion Criteria
- [ ] A neutral shared kit exists with executable CLI, schema, templates, and tests; it is not only a skill or markdown playbook.
- [ ] App manifests are canonical for desired release state, while credentials remain in Keychain/secret stores and Apple remains canonical for remote cert/profile/app/build/review state.
- [ ] The kit has dry-run and apply modes with machine-readable plans, redacted logs, and explicit `requiresHuman` outputs for the known Apple-only human gates.
- [ ] Certificate creation/import supports at least `MAC_APP_DISTRIBUTION`, `MAC_INSTALLER_DISTRIBUTION`, and Developer ID lanes where Apple API/tooling permits; unsupported portal-only steps produce exact handoffs.
- [ ] Bundle ID/profile reconciliation supports macOS `MAC_OS` bundle IDs and `MAC_APP_STORE` provisioning profiles, with reusable extension points for iOS/TestFlight.
- [ ] Developer ID direct-download validation has explicit proof: app signed with Developer ID Application, notarization submitted and accepted through `notarytool`, ticket stapled, `stapler validate` passes, `spctl --assess --type execute` passes, and release manifest records `signingMode: developer-id` plus `notarized: true`.
- [ ] Binary validation/upload uses `altool`/Transporter semantics rather than falsely modeling upload as a plain App Store Connect REST call.
- [ ] App metadata/version/build/review submission automation covers the path after an app record exists: app lookup, version creation/update, localization metadata, build processing lookup, build association, review submission/item creation, and status polling.
- [ ] Ouro MD consumes the shared kit for App Store readiness/validation/upload/review-prep, with existing local scripts either delegated to the kit or reduced to thin app-local wrappers.
- [ ] CI has no-secret gates for manifest validation, API payload generation, redaction, command generation, and selftests; secret-backed workflows import Mac App Store certs/profile/API key only when configured. When secrets or Apple state are absent, the kit produces canonical blocker artifacts instead of ambiguous failures.
- [ ] Live Apple gates have named pass/blocker artifacts for App Store API auth, provider resolution, app-record discovery, certificate presence/import, profile creation/download, package validation, upload id, processed-build discovery, build association, and review-submission readiness.
- [ ] Workbench and Spoonjoy have manifest/adoption PRs or generated adoption fixtures proving the kit is app-neutral and not overfit to Ouro MD; Spoonjoy coverage is dry-run/schema/manifest only unless the lane is explicitly promoted.
- [ ] The `sign-apple-apps` skill and relevant app docs tell future agents to use the shared kit and explain the human/account boundary plainly.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No warnings

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

### ✅ Unit 0: Setup/Research
**What**: Create or verify public repo `ourostack/apple-distribution-kit` with default branch `main`, MIT license, secret-scanning-friendly `.gitignore`, Node/TypeScript runtime, CLI command `apple-distribution-kit`, package name `apple-distribution-kit`, and local checkout `/Users/arimendelow/Projects/apple-distribution-kit` on branch `worker/foundation`. Treat `/Users/arimendelow/Projects/ouro-md-apple-release-kit-program` as the coordinator/doc worktree only. Verify candidate local credentials at `~/Library/Application Support/AppleDistributionKit/app-store-connect/config.json`.
**Output**: `setup-repo.json`, `asc-smoke.json`, `repo-map.json`, and `secret-scan-preflight.txt` in the artifacts directory; new repo initialized and pushed if missing.
**Acceptance**: `gh repo view ourostack/apple-distribution-kit --json nameWithOwner,visibility,defaultBranchRef,url` reports public/main; `curl https://api.appstoreconnect.apple.com/v1/apps?limit=1` through a custom ES256 JWT returns HTTP 200 in `asc-smoke.json`; `xcrun altool --generate-jwt` REST smoke behavior is recorded without token output; `find ~/Downloads -name 'AuthKey_*.p8'` is empty; `git status --short` in touched repos shows no secret files.

### ✅ Unit 1a: Shared Kit Scaffold — Tests
**What**: Write failing tests for CLI help/version, config discovery, manifest path resolution, JSON output mode, failure exit codes, and package exports.
**Output**: Test files under `/Users/arimendelow/Projects/apple-distribution-kit/test/` and red-run log `unit-1a-red.log`.
**Acceptance**: Tests fail because implementation/exported modules are missing, not because the test runner is misconfigured.

### ✅ Unit 1b: Shared Kit Scaffold — Implementation
**What**: Implement TypeScript package scaffold, CLI entry point, config discovery, manifest path resolution, JSON/text output switch, and package exports.
**Output**: `src/cli.ts`, `src/config.ts`, package metadata, TypeScript config, and green-run log `unit-1b-green.log`.
**Acceptance**: Unit 1a tests PASS, `npm run build` passes, `node dist/cli.js --help` exits 0, and no warnings appear.

### ✅ Unit 1c: Shared Kit Scaffold — Coverage & Refactor
**What**: Add coverage enforcement and CI for no-secret package tests; refactor scaffold code only if behavior remains green.
**Output**: Coverage config, `.github/workflows/ci.yml`, coverage report, and `unit-1c-coverage.log`.
**Acceptance**: Coverage is 100% for scaffold code, `npm test`, `npm run build`, and CI workflow syntax checks pass.

### ✅ Unit 2a: Manifest/Redaction/Plan Core — Tests
**What**: Write failing tests for canonical app manifest `distribution/apple-distribution.json`, schema validation, manifest examples, redaction helpers, machine-readable plan shape, `requiresHuman` entries, and no-secret log serialization.
**Output**: Schema/fixture tests, snapshot fixtures, and red-run log `unit-2a-red.log`.
**Acceptance**: Tests fail on missing schema/plan/redaction behavior with clear assertions.

### ✅ Unit 2b: Manifest/Redaction/Plan Core — Implementation
**What**: Implement manifest schema, loader, validator, examples, redaction helper, plan model, `requiresHuman` model, and stable JSON serialization.
**Output**: `src/manifest/`, `src/plan/`, example manifests, and green-run log `unit-2b-green.log`.
**Acceptance**: Unit 2a tests PASS; invalid manifests produce precise JSON-pointer-like diagnostics; logs redact tokens, private keys, `.p8`, `.p12`, profile content, and app-specific passwords.

### ✅ Unit 2c: Manifest/Redaction/Plan Core — Coverage & Refactor
**What**: Cover null/empty/boundary manifest fields, redaction false positives/negatives, and all plan branch variants.
**Output**: Coverage report and `unit-2c-coverage.log`.
**Acceptance**: Coverage is 100% for manifest/plan/redaction code and tests/build stay green.

### ✅ Unit 3a: App Store Connect Auth/Client — Tests
**What**: Write failing tests for ES256 JWT generation using P-1363 signatures, REST request construction, auth config discovery, token redaction, provider/team lookup from App Store Connect API/manifest hints, app lookup, retry behavior, and error classification.
**Output**: Auth/client tests with captured outbound request assertions and red-run log `unit-3a-red.log`.
**Acceptance**: Tests fail on missing auth/client behavior; outbound URL, headers, body, and redaction assertions are present.

### ✅ Unit 3b: App Store Connect Auth/Client — Implementation
**What**: Implement the JWT signer, REST client, local config loader, provider/team/app lookup commands from App Store Connect API/manifest hints, retry/error classification, and `asc smoke` command using `GET /v1/apps?limit=1`.
**Output**: `src/asc/`, CLI commands, and green-run log `unit-3b-green.log`.
**Acceptance**: Unit 3a tests PASS; local `apple-distribution-kit asc smoke --json` succeeds with HTTP 200 and prints no token/private-key material.

### ✅ Unit 3c: App Store Connect Auth/Client — Coverage & Refactor
**What**: Cover expired/missing key, malformed config, 401/403/404/409/429/5xx responses, provider ambiguity, and missing `providerPublicId` when a Transporter/altool upload command requires one.
**Output**: Coverage report, live smoke artifact `asc-live-smoke.json`, and `unit-3c-coverage.log`.
**Acceptance**: Coverage is 100% for auth/client code; live artifact contains endpoint/status/count only, not JWT or private key content.

### ✅ Unit 4a: Apple State Reconciler — Tests
**What**: Write failing tests for bundle ID, certificate, provisioning profile, app-record discovery, first-app-record `requiresHuman`, destructive delete planning, manual delete flag behavior, macOS App Store lane, Developer ID lane, and iOS dry-run lane.
**Output**: Reconciler tests, remote Apple response fixtures, snapshot plans, and red-run log `unit-4a-red.log`.
**Acceptance**: Tests fail on missing reconciliation decisions and include unsupported `/v1/apps` creation behavior.

### ✅ Unit 4b: Apple State Reconciler — Implementation
**What**: Implement desired-vs-remote reconcilers for bundle IDs, certificates, provisioning profiles, app record discovery, and safe/destructive plan classification.
**Output**: `src/reconcile/`, fixture plan outputs, and green-run log `unit-4b-green.log`.
**Acceptance**: Unit 4a tests PASS; destructive Apple deletes are refused unless `--allow-destructive-apple-delete` is present; missing first app record produces canonical `requiresHuman`.

### ✅ Unit 4c: Apple State Reconciler — Coverage & Refactor
**What**: Cover empty remote state, duplicate remote resources, conflicting teams/providers, unsupported certificate/profile types, and stable blocker artifacts.
**Output**: Coverage report and `unit-4c-coverage.log`.
**Acceptance**: Coverage is 100% for reconciler code and snapshot plans stay stable.

### ⬜ Unit 5a: Local Xcode Runner — Tests
**What**: Write failing tests for exact argv generation and result parsing for `codesign`, `productbuild`, `xcrun notarytool`, `xcrun stapler`, `spctl --assess --type execute`, `xcrun altool --validate-app`, and `xcrun altool --upload-package`.
**Output**: Runner tests with argv/log redaction assertions and red-run log `unit-5a-red.log`.
**Acceptance**: Tests fail on missing runner behavior; every generated command is asserted without invoking live upload/notarization.

### ⬜ Unit 5b: Local Xcode Runner — Implementation
**What**: Implement command builder, dry-run/apply separation, missing-tool detection, result parser, App Store package validation/upload wrappers, Developer ID sign/notarize/staple/spctl proof model, and channel invariant checks.
**Output**: `src/xcode/`, generated command fixtures, and green-run log `unit-5b-green.log`.
**Acceptance**: Unit 5a tests PASS; dry-run emits exact commands; apply refuses live upload/notarization unless explicit apply intent and required credentials are present.

### ⬜ Unit 5c: Local Xcode Runner — Coverage & Refactor
**What**: Cover success/failure parsing, timeout/interruption, missing `xcrun`, missing identities, notarization failure states, stapler failure, and redaction edge cases.
**Output**: Coverage report and `unit-5c-coverage.log`.
**Acceptance**: Coverage is 100% for runner code and tests/build stay green.

### ⬜ Unit 6a: Store Metadata/Review Automation — Tests
**What**: Write failing tests for app store version create/update payloads, localization metadata, screenshots/app-preview manifest validation, local/remote asset proof blockers, build processing lookup, build association, review submission/item creation, review status polling, privacy/export-compliance blockers, and screenshot/app-preview missing blockers.
**Output**: Metadata/review tests with captured outgoing REST request assertions and red-run log `unit-6a-red.log`.
**Acceptance**: Tests fail on missing metadata/review behavior with outbound request assertions present.

### ⬜ Unit 6b: Store Metadata/Review Automation — Implementation
**What**: Implement metadata/version/build/review planner and apply commands for the post-app-record path. v1 validates screenshot/app-preview requirements and emits blockers; it does not upload or reconcile screenshot/app-preview binaries.
**Output**: `src/store/`, example metadata artifacts, and green-run log `unit-6b-green.log`.
**Acceptance**: Unit 6a tests PASS; missing screenshots/app previews/privacy/export-compliance values produce canonical blockers instead of partial submissions; no code path claims screenshot/app-preview upload support.

### ⬜ Unit 6c: Store Metadata/Review Automation — Coverage & Refactor
**What**: Cover optional metadata, polling timeout, build not processed, build version mismatch, review rejection status, and update-vs-create branches.
**Output**: Coverage report and `unit-6c-coverage.log`.
**Acceptance**: Coverage is 100% for metadata/review code and tests/build stay green.

### ⬜ Unit 7a: Ouro MD Consumer — Tests
**What**: Add failing Ouro MD checks proving `distribution/apple-distribution.json` validates through the shared kit, wrapper scripts delegate to the shared kit, shell-boundary checks still pass, and no secret material is committed.
**Output**: Ouro MD tests/check scripts and red-run log `unit-7a-red.log`.
**Acceptance**: Tests/checks fail because the manifest/wrappers are not implemented yet.

### ⬜ Unit 7b: Ouro MD Consumer — Implementation
**What**: Add Ouro MD manifest at `/Users/arimendelow/Projects/ouro-md/distribution/apple-distribution.json`, thin wrapper scripts, generated app-store docs, no-secret CI gates, and App Store readiness artifact wiring to the shared kit.
**Output**: Ouro MD branch `worker/apple-distribution-kit-adoption`, manifest/wrappers/docs/CI changes, and green-run log `unit-7b-green.log`.
**Acceptance**: Unit 7a tests PASS; dry-run readiness writes named pass/blocker artifacts; existing package scripts either delegate to the kit or remain narrow app-local build hooks.

### ⬜ Unit 7c: Ouro MD Consumer — Coverage & Refactor
**What**: Refactor Ouro MD release docs/scripts for clarity, run current app checks, and verify shell-boundary and release policy still pass.
**Output**: Ouro MD coverage/check logs and `unit-7c-coverage.log`.
**Acceptance**: Ouro MD tests/checks/builds selected for release readiness pass with no warnings and no shell-boundary regressions.

### ⬜ Unit 8a: Workbench/Spoonjoy/Skills Adoption — Tests
**What**: Add failing checks proving Workbench manifest, Spoonjoy manifest, and `sign-apple-apps` skill references validate against the shared kit.
**Output**: Workbench/Spoonjoy/skills check additions and red-run log `unit-8a-red.log`.
**Acceptance**: Tests/checks fail until actual manifests/docs are present.

### ⬜ Unit 8b: Workbench/Spoonjoy/Skills Adoption — Implementation
**What**: Add Workbench manifest at `/Users/arimendelow/Projects/ouro-workbench/distribution/apple-distribution.json`, Spoonjoy manifest at `/Users/arimendelow/Projects/spoonjoy/distribution/apple-distribution.json`, update `ouroboros-skills/skills/sign-apple-apps/SKILL.md`, and document canonical app identities: `bot.ouro.md`, `bot.ouro.workbench`, and `app.spoonjoy`.
**Output**: Branches `worker/apple-distribution-kit-adoption` in Workbench, Spoonjoy, and skills; manifests/docs; and green-run log `unit-8b-green.log`.
**Acceptance**: Unit 8a tests PASS; Workbench and Spoonjoy dry-run/schema checks prove app neutrality and do not attempt submission.

### ⬜ Unit 8c: Workbench/Spoonjoy/Skills Adoption — Coverage & Refactor
**What**: Run cross-repo dry-run validation and refine docs/templates so future apps can follow the kit without reading this task.
**Output**: `cross-repo-dry-run.json`, per-repo check logs, and `unit-8c-coverage.log`.
**Acceptance**: Cross-repo validation artifacts exist and all involved docs/checks pass.

### ⬜ Unit 9: Live Developer ID Direct-Download Proof
**What**: Use the shared kit against Ouro MD's direct-download lane to run or classify each Developer ID gate: identity discovery, signing, notarization submit/wait, stapling, `stapler validate`, `spctl --assess --type execute`, and release manifest proof.
**Output**: `developer-id-auth.json`, `developer-id-identity.json`, `developer-id-signing.json`, `developer-id-notarization.json`, `developer-id-stapler.json`, `developer-id-spctl.json`, and `developer-id-release-proof.json`.
**Acceptance**: Each artifact is `passed` with command/status evidence, or `blocked` only for one of these named hard blockers: missing Developer ID Application identity, missing notarization credential, Apple notary service unavailable, or no release package built. Ordinary implementation gaps are not allowed blockers.

### ⬜ Unit 10: Live Ouro MD Mac App Store Path
**What**: Use the shared kit against Ouro MD's Mac App Store lane to run or classify each live gate: App Store Connect auth, provider resolution/apply upload provider hint, app-record discovery for `bot.ouro.md`, certificate presence/import, profile creation/download, package validation, upload, processed-build discovery, build association, store-asset proof, and review-submission preparation.
**Output**: `app-store-auth.json`, `app-store-provider.json`, `app-store-app-record.json`, `app-store-certificates.json`, `app-store-profile.json`, `app-store-package-validation.json`, `app-store-upload.json`, `app-store-processed-build.json`, `app-store-build-association.json`, `app-store-assets.json`, and `app-store-review-prep.json`.
**Acceptance**: Each artifact is `passed` with endpoint/command/status evidence, or `blocked` only for one of these named hard blockers: first app record must be created in App Store Connect UI, Apple legal/agreement gate, 2FA/CAPTCHA/passkey prompt, managed capability approval, missing `providerPublicId` required by Transporter/altool and not inferable from App Store Connect API, missing local signing identity/profile that cannot be created via API, package build unavailable, missing screenshot/app-preview assets or remote proof, or Apple service outage. Ordinary implementation gaps are not allowed blockers.

### ⬜ Unit 11a: Cold Review and Fixes
**What**: Run fresh sub-agent reviews for the shared kit and every consumer repo diff, then address all BLOCKER/MAJOR findings.
**Output**: `review-shared-kit.md`, `review-ouro-md.md`, `review-workbench.md`, `review-spoonjoy.md`, `review-skills.md`, fix commits, and rerun logs.
**Acceptance**: Reviewers converge or any residual issue is classified as a true hard exception with evidence.

### ⬜ Unit 11b: Merge/PR Terminal State
**What**: Push and merge ready branches where permissions/branch protection allow. If branch protection or external checks prevent merge, leave a PR with green local evidence and explicit blocker artifact. Do not direct-push to protected app repo main branches; use PR/merge flow for existing repos. New repo may merge its bootstrap PR into main after review/CI.
**Output**: PR/merge URLs, CI status artifacts, and `merge-state.json`.
**Acceptance**: Each touched repo is either merged to main/default with CI evidence, or has a ready PR blocked only by external branch protection/checks.

### ⬜ Unit 11c: Publish/Install/Runtime Refresh
**What**: Verify the shared kit can be installed/used from app repos, refresh local skill/docs references, and prove the consuming commands work from a clean shell.
**Output**: `install-smoke.json`, local command logs, refreshed skill evidence, and `runtime-refresh.json`.
**Acceptance**: `apple-distribution-kit --help`, manifest validation, and dry-run commands work from the app repos without relying on unpublished local hacks.

### ⬜ Unit 11d: Desk/Backlog/Cleanup
**What**: Update Desk task state, record residual Apple/human blockers, add backlog items for App Store first-record/manual gates and future Workbench/Spoonjoy submissions, clean stale worktrees/branches from this run, and run the autopilot continuation scan.
**Output**: Desk commit, cleanup log, `continuation-scan.md`, and clean git status summaries.
**Acceptance**: No ready work remains except true hard exceptions or explicitly out-of-scope future submissions; no stale secret files, temp downloads, abandoned worktrees, or dirty task branches from this run remain.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- **All artifacts**: Save outputs, logs, data to `./2026-07-03-1000-doing-apple-distribution-kit/`
- **Fixes/blockers**: Spawn sub-agent for non-trivial fix/review work; direct mode remains the main orchestrator. A blocker becomes terminal only if it matches a named human-only Apple/capability gate or destructive shared-state exception.
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- 2026-07-03 11:50 Created from planning doc
- 2026-07-03 11:58 Reworked after reviewer findings: added explicit outputs to every unit, fixed repo/worktree ownership, split finalization, added live Developer ID proof, and enumerated allowed Apple blockers/artifacts.
- 2026-07-03 12:03 Encoded providerPublicId and screenshot/app-preview v1 policy after Round 2 adversarial review.
- 2026-07-03 12:14 Unit 0 complete: created public `ourostack/apple-distribution-kit`, cloned `/Users/arimendelow/Projects/apple-distribution-kit` on `worker/foundation`, validated App Store Connect API key via redacted smoke, and recorded repo/secret preflight artifacts.
- 2026-07-03 12:18 Unit 1a complete: added failing scaffold tests for CLI/config/manifest path behavior and recorded red-run evidence.
- 2026-07-03 12:22 Unit 1b complete: implemented minimal CLI/config/manifest path foundation and recorded green test/build evidence.
- 2026-07-03 12:27 Unit 1c complete: added CI and enforced 100% scaffold coverage with built CLI smoke evidence.
- 2026-07-03 12:29 Unit 2a complete: added failing manifest/redaction/plan tests and recorded red-run evidence.
- 2026-07-03 12:33 Unit 2b complete: implemented manifest validation, redaction, plan shape, and manifest validation CLI behavior.
- 2026-07-03 12:37 Unit 2c complete: covered manifest/plan/redaction branches to 100% and kept tests/build green.
- 2026-07-03 12:40 Unit 3a complete: added failing App Store Connect JWT/client/provider tests and recorded red-run evidence.
- 2026-07-03 12:43 Unit 3b complete: implemented ES256 JWT signing, ASC REST client, providerPublicId resolution, and CLI smoke path.
- 2026-07-03 12:51 Unit 3c complete: covered ASC auth/client branches to 100%, ran live redacted `asc smoke`, and recorded `asc-live-smoke.json`.
- 2026-07-03 12:54 Unit 4a complete: added failing Apple state reconciliation tests for missing resources, human gates, iOS dry-run blockers, and destructive-delete policy.
- 2026-07-03 12:56 Unit 4b complete: implemented bundle/certificate/profile/app-record reconciliation and safe destructive-delete classification.
- 2026-07-03 12:57 Unit 4c complete: verified reconciler coverage remains 100% with tests/build green.
