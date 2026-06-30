# Doing: Harness, Vendor, And Editor Extraction Guardrails

**Status**: drafting
**Execution Mode**: direct
**Created**: 2026-06-29 22:08
**Planning**: ./2026-06-29-2201-planning-harness-vendor-editor-extraction.md
**Artifacts**: ./2026-06-29-2201-doing-harness-vendor-editor-extraction/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts (non-autopilot interactive mode only; autopilot must convert this to `spawn` or `direct` unless a hard exception is present)
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Formalize Ouro MD's shipped CLI and diagnostic harness boundary, add durable provenance policy for vendored Vditor assets, and define a testable AppKit/WebKit extraction plan so future editor decomposition work starts from evidence instead of file size alone.

## Upstream Work Items
- A-017: Formalize Ouro MD's Shipped Harness/Probe Boundary
- A-018: Add A Vendor Provenance Policy For Ouro MD's Web Editor Assets
- A-036: Give Ouro MD AppKit/WebKit Code A Gradual Library-Extraction Plan
- A-013: Keep Ouro MD Core Editor Decomposition On The Radar

## Completion Criteria
- [ ] A-017 has a documented and machine-checked shipped diagnostic harness contract.
- [ ] A-018 has a documented and machine-checked Vditor vendor provenance policy.
- [ ] A-036 has a concrete extraction plan with candidates, ordering, tests, and A-013 disposition.
- [ ] New checks are part of PR preflight or release-policy selftests so CI/local validation can catch drift.
- [ ] Existing release freshness behavior remains intentional for harness-only edits and Vditor/resource edits.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No warnings

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch/case, try/catch)
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
**What**: Create the artifacts directory, capture current harness flags and Vditor digest inputs, and verify the existing preflight/release-policy hooks that need to call new checks.
**Output**: Notes/logs under `./2026-06-29-2201-doing-harness-vendor-editor-extraction/`.
**Acceptance**: Evidence includes current `main.swift` flags, native scenario flags, Vditor tracked-file count/digest, and release-policy command locations.

### ⬜ Unit 1a: Shipped CLI/Harness Policy — Tests
**What**: Add failing script selftests for a missing `docs/shipped-cli-and-harness-policy.json`, drift between policy and `Sources/OuroMD/main.swift`, native scenario coverage drift, and release classifier drift for harness-only files.
**Output**: A new check path, likely `scripts/check-shipped-harness-policy.sh`, plus a release-policy/preflight assertion that calls it.
**Acceptance**: The new test/check fails before the policy manifest and implementation are added.

### ⬜ Unit 1b: Shipped CLI/Harness Policy — Implementation
**What**: Add `docs/shipped-cli-and-harness-policy.json`, implement the policy checker, and wire it into `scripts/pr-preflight.sh` and `scripts/release-policy.sh selftest-package-guards` or a dedicated selftest command.
**Output**: Manifest and executable script with deterministic validation.
**Acceptance**: Harness policy check passes; release-policy selftests pass; hidden diagnostic modes remain explicit and public CLI modes are classified separately.

### ⬜ Unit 1c: Shipped CLI/Harness Policy — Coverage & Refactor
**What**: Run shell syntax checks and focused policy selftests; refactor the checker only if readability or failure output is weak.
**Output**: Validation logs in the artifacts directory.
**Acceptance**: `bash -n` and focused selftests pass with clear output and no warnings.

### ⬜ Unit 2a: Vditor Vendor Provenance — Tests
**What**: Add failing validation for missing `docs/vditor-vendor-manifest.json`, stale digest, missing license path, missing refresh validation commands, and accidental edits under `Sources/OuroMD/web/vditor`.
**Output**: A new check path, likely `scripts/check-vditor-vendor.sh`, and preflight/release-policy call assertions.
**Acceptance**: The check fails before the manifest is added.

### ⬜ Unit 2b: Vditor Vendor Provenance — Implementation
**What**: Add the Vditor manifest with upstream/package/license/provenance/update policy/digest, implement the checker, and wire it into PR preflight and release-policy selftests.
**Output**: Manifest and deterministic vendor provenance check.
**Acceptance**: Vditor vendor check passes against the current vendored tree and fails on digest/provenance drift.

### ⬜ Unit 2c: Vditor Vendor Provenance — Coverage & Refactor
**What**: Run shell syntax checks, focused vendor check, and release-policy selftests; tune failure messages if needed.
**Output**: Validation logs in the artifacts directory.
**Acceptance**: Focused vendor validation and release-policy selftests pass with no warnings.

### ⬜ Unit 3: AppKit/WebKit Extraction Plan And A-013 Radar
**What**: Add a concrete extraction plan document for future `OuroMDAppSupport` / `OuroMDEditorSupport` candidates, including command catalog, update presentation, file/folder state, editor bridge policy, test gates, ordering, and explicit A-013 deferral.
**Output**: `docs/appkit-webkit-extraction-plan.md`.
**Acceptance**: The document cites current files, names first candidate extractions, states validation requirements, and explicitly prevents broad editor-core decomposition in this lane.

### ⬜ Unit 4: Final Validation, Review, And PR Prep
**What**: Run local validation for changed checks, Swift build/tests as practical, shell boundary/preflight slices, and a cold self-review of the diff.
**Output**: Final validation logs and reviewer notes in the artifacts directory.
**Acceptance**: Changed checks pass; Swift build/test status is recorded; reviewer BLOCKER/MAJOR findings are resolved or proven non-applicable.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- **All artifacts**: Save outputs, logs, data to `./2026-06-29-2201-doing-harness-vendor-editor-extraction/`
- **Fixes/blockers**: Spawn sub-agent immediately — don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- 2026-06-29 22:08 Created from planning doc
