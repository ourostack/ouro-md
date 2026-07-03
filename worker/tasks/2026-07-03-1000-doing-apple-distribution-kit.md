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

### ⬜ Unit 0: Setup/Research
**What**: Create or verify the public neutral `ourostack/apple-distribution-kit` repository, create a local worktree/clone on a worker branch, preserve the validated App Store Connect API key in the locked local credentials directory, and save non-secret setup evidence under the artifacts directory.
**Output**: Repository URL/local path, credential smoke evidence without secrets, and a current repo map for Ouro MD, Workbench, Spoonjoy, app shell, and skills.
**Acceptance**: `gh repo view ourostack/apple-distribution-kit` succeeds or the repo is created; the App Store Connect REST smoke returns HTTP 200 through the local key; no `.p8`, `.p12`, `.cer`, provisioning profile, app-specific password, or generated token appears in git status or artifacts.

### ⬜ Unit 1a: Shared Kit Foundation — Tests
**What**: Write failing tests for manifest loading/validation, redaction, plan shape, `requiresHuman` shape, command-result serialization, and CLI exit behavior in `apple-distribution-kit`.
**Acceptance**: Tests exist and FAIL (red), with failures about missing foundation behavior rather than broken test setup.

### ⬜ Unit 1b: Shared Kit Foundation — Implementation
**What**: Implement the package scaffold, executable CLI, manifest schema, redaction helpers, dry-run planner primitives, machine-readable plan output, and no-secret logging.
**Acceptance**: Unit 1a tests PASS (green), CLI help works, manifest validation errors are precise, and no warnings are emitted.

### ⬜ Unit 1c: Shared Kit Foundation — Coverage & Refactor
**What**: Add coverage enforcement, CI, README quickstart, examples, and refactor foundation code without changing behavior.
**Acceptance**: Coverage is 100% for new foundation code, CI runs no-secret tests, and local build/test/coverage pass.

### ⬜ Unit 2a: App Store Connect Auth/Client — Tests
**What**: Write failing tests for ES256 JWT generation, REST request construction, auth config discovery, redaction of credentials, provider/team ambiguity, app lookup, and retry/error classification.
**Acceptance**: Tests exist and FAIL (red), including assertions on outgoing REST URL, headers, body, and redacted logs.

### ⬜ Unit 2b: App Store Connect Auth/Client — Implementation
**What**: Implement the App Store Connect JWT signer, REST client, local config loader, provider/team/app lookup commands, and live smoke command that reads the locked credential directory.
**Acceptance**: Unit 2a tests PASS (green); `apple-distribution-kit asc smoke` succeeds locally with HTTP 200 while printing no token/private-key material.

### ⬜ Unit 2c: App Store Connect Auth/Client — Coverage & Refactor
**What**: Enforce branch/error-path coverage for auth/client code and write artifact evidence for the live smoke.
**Acceptance**: Coverage is 100% on auth/client code, live smoke artifact records status and endpoint only, and tests/build stay green.

### ⬜ Unit 3a: Apple State Reconciler — Tests
**What**: Write failing tests for bundle ID, certificate, profile, destructive-plan, and `requiresHuman` reconciliation decisions for macOS App Store, Developer ID, and iOS dry-run lanes.
**Acceptance**: Tests exist and FAIL (red), including unsupported first-app-record creation and destructive-delete manual-flag behavior.

### ⬜ Unit 3b: Apple State Reconciler — Implementation
**What**: Implement desired-vs-remote reconcilers for bundle IDs, certificates, provisioning profiles, app record discovery, and safe/destructive plan classification.
**Acceptance**: Unit 3a tests PASS (green); apply mode refuses destructive deletes unless the explicit flag is present; missing first app record produces a canonical `requiresHuman` action.

### ⬜ Unit 3c: Apple State Reconciler — Coverage & Refactor
**What**: Add fixtures for remote Apple responses, edge cases, and generated blocker artifacts; refactor reconciler boundaries for app neutrality.
**Acceptance**: Coverage is 100% on reconciler code, fixture plans are stable snapshots, and tests/build stay green.

### ⬜ Unit 4a: Local Xcode Runner — Tests
**What**: Write failing tests for command generation and result parsing for `codesign`, `productbuild`, `notarytool`, `stapler`, `spctl`, `xcrun altool --validate-app`, and `xcrun altool --upload-package`.
**Acceptance**: Tests exist and FAIL (red), asserting exact argv and redacted logs for all generated commands.

### ⬜ Unit 4b: Local Xcode Runner — Implementation
**What**: Implement the command runner, dry-run/apply separation, package validation/upload wrappers, notarization/stapling proof model, and app-store/developer-id channel invariants.
**Acceptance**: Unit 4a tests PASS (green); no live upload/notarization occurs without explicit apply intent; dry-run emits exact commands.

### ⬜ Unit 4c: Local Xcode Runner — Coverage & Refactor
**What**: Cover success/failure parsing, missing-tool detection, and redaction edge cases; refactor runner for reusable app hooks.
**Acceptance**: Coverage is 100% on runner code and tests/build stay green.

### ⬜ Unit 5a: Store Metadata/Review Automation — Tests
**What**: Write failing tests for version creation/update payloads, localization metadata, screenshots/assets manifest validation, build processing lookup, build association, review submission/item creation, and status polling.
**Acceptance**: Tests exist and FAIL (red), with outgoing REST requests captured and asserted.

### ⬜ Unit 5b: Store Metadata/Review Automation — Implementation
**What**: Implement metadata/version/build/review planner and apply commands for the post-app-record path.
**Acceptance**: Unit 5a tests PASS (green); missing screenshots/assets/privacy/export-compliance values produce canonical blockers instead of partial submissions.

### ⬜ Unit 5c: Store Metadata/Review Automation — Coverage & Refactor
**What**: Cover failure states, optional metadata, and polling timeouts; refactor output artifacts for app teams.
**Acceptance**: Coverage is 100% on metadata/review code and tests/build stay green.

### ⬜ Unit 6a: Ouro MD Consumer — Tests
**What**: Add failing Ouro MD tests/CI checks proving its manifest validates, scripts delegate to the shared kit, shell-boundary checks still pass, and no secret material is committed.
**Acceptance**: Tests/checks exist and FAIL (red) because the manifest/wrappers are not implemented yet.

### ⬜ Unit 6b: Ouro MD Consumer — Implementation
**What**: Add Ouro MD release manifest, thin wrapper scripts, generated app-store docs, CI no-secret gates, and App Store readiness artifacts wired to the shared kit.
**Acceptance**: Unit 6a tests PASS (green); Ouro MD dry-run readiness produces pass/blocker artifacts; existing package scripts either delegate or remain as narrow app-local build hooks.

### ⬜ Unit 6c: Ouro MD Consumer — Coverage & Refactor
**What**: Refactor Ouro MD release docs/scripts for clarity, ensure CI contracts are complete, and run current app test/build/smoke commands that apply to release readiness.
**Acceptance**: Ouro MD checks pass with no warnings and no shell-boundary regressions.

### ⬜ Unit 7a: Workbench/Spoonjoy/Skills Adoption — Tests
**What**: Add failing checks or fixture tests proving Workbench and Spoonjoy manifests validate and `sign-apple-apps` points agents at the executable kit.
**Acceptance**: Tests/checks exist and FAIL (red) until fixtures/docs are added.

### ⬜ Unit 7b: Workbench/Spoonjoy/Skills Adoption — Implementation
**What**: Add Workbench and Spoonjoy adoption fixtures or PR-ready manifests, update the signing skill, and document canonical app identities: `bot.ouro.md`, `bot.ouro.workbench`, and `app.spoonjoy`.
**Acceptance**: Unit 7a tests PASS (green); adoption is clearly app-neutral and does not overfit Ouro MD.

### ⬜ Unit 7c: Workbench/Spoonjoy/Skills Adoption — Coverage & Refactor
**What**: Run cross-repo dry-run validation and refine docs/templates so future apps can follow the kit without reading this task.
**Acceptance**: Cross-repo validation artifacts exist and all involved docs/checks pass.

### ⬜ Unit 8: Live Ouro MD Apple Path
**What**: Using the shared kit, run the live Ouro MD App Store path as far as Apple state allows: auth smoke, provider resolution, app-record discovery, certificate/profile reconciliation, package validation, upload or explicit upload blocker, processed-build lookup, build association, and review-submission preparation.
**Output**: Named pass/blocker artifacts for every live gate, with secrets redacted.
**Acceptance**: Every gate is either passed with evidence or blocked only by a true Apple/human requirement; no brittle browser driving remains in the canonical path.

### ⬜ Unit 9: Review, Merge, Publish/Install, Cleanup
**What**: Run cold sub-agent reviews, address BLOCKER/MAJOR findings, merge/push/PR each repo according to its policy, verify CI/deploy/install surfaces, refresh any local skill/runtime consumers, update Desk state, and remove stale worktrees/branches from this run.
**Output**: Merged repos or PRs where branch protection requires external checks, verified CI/output evidence, refreshed local skill reference, and clean worktrees.
**Acceptance**: No ready work remains in the continuation scan except true hard exceptions or out-of-scope future submissions.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- **All artifacts**: Save outputs, logs, data to `./2026-07-03-1000-doing-apple-distribution-kit/`
- **Fixes/blockers**: Spawn sub-agent immediately — don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- 2026-07-03 11:50 Created from planning doc
