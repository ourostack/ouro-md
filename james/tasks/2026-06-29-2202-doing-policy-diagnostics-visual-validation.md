# Doing: Shared Shell Policy Diagnostics Visual Validation

**Status**: drafting
**Execution Mode**: direct
**Created**: pending initial commit
**Planning**: ./2026-06-29-2202-planning-policy-diagnostics-visual-validation.md
**Artifacts**: ./2026-06-29-2202-doing-policy-diagnostics-visual-validation/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts (non-autopilot interactive mode only; autopilot must convert this to `spawn` or `direct` unless a hard exception is present)
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Implement the policy/diagnostics/visual-validation lane for the shared Ouro native app shell campaign across Ouro MD, Ouro Workbench, and the shared shell. The lane should turn settings/telemetry, privacy/diagnostics, Swift strictness, visual surface coverage, and native UI testing strategy from audit backlog items into enforceable docs, contracts, manifests, scripts, and tests where feasible.

## Upstream Work Items
- A-015: Shared settings/telemetry roadmap
- A-020: Swift strictness matrix
- A-021: Cross-app visual surface manifest
- A-029: Privacy/diagnostics contract
- A-030: Shared UI testing strategy

## Completion Criteria
- [ ] A-015 is complete when shell docs define the shared settings-section taxonomy and telemetry consent/envelope boundary, `OuroAppShellSettingsContract` can declare shared section descriptors, and shell tests reject malformed settings descriptors.
- [ ] A-020 is complete when a checked-in strictness matrix lists every Swift target in the three `Package.swift` files with current language mode, target posture, blockers, and the exact validation command; a script verifies the matrix still mentions all current targets.
- [ ] A-021 is complete when a shell-owned visual surface manifest file declares required states for About, update controls, settings entry, command reference, and utility windows, and `scripts/ui-surface-probe.sh` validates that the manifest is parseable and represented by the shell probe.
- [ ] A-029 is complete when `OuroAppShellContract` includes a privacy/diagnostics descriptor with fields for telemetry consent entry, privacy doc URL, diagnostics export disclosure, support-bundle contents, and redaction guarantees; validator tests cover missing/blank invalid descriptors; MD and Workbench declare descriptors.
- [ ] A-030 is complete when shell docs map native app surface types to ViewInspector, shell surface probe, app harness, accessibility tree, and screenshot/OCR gates, and the visual surface manifest records the selected validation tool per surface row.
- [ ] Ouro MD and Ouro Workbench consume or validate the new contract fields by compiling contract declarations and passing shell consumer assertion tests; verification must not require moving app-owned event names, support bundle collectors, or domain settings behavior into shell.
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
**Strict TDD - no exceptions:**
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
**What**: Reconfirm branch/worktree state, source backlog lanes, and existing shell/consumer settings, diagnostics, strictness, and visual testing surfaces.
**Output**: Notes in this doing doc and any command logs saved under `./2026-06-29-2202-doing-policy-diagnostics-visual-validation/`.
**Acceptance**: All three James worktrees are on `james/policy-diagnostics-visual-validation`; cited source paths exist; implementation targets are listed before code edits.

### ⬜ Unit 1a: Shell Settings/Privacy Contract - Tests
**What**: Add failing shell contract tests for shared settings section descriptors and privacy/diagnostics descriptors in `Tests/OuroAppShellContractTests/OuroAppShellContractTests.swift`.
**Acceptance**: Targeted shell tests fail because `OuroAppShellSettingsSectionContract`/privacy diagnostics descriptor APIs or validation behavior do not exist yet.

### ⬜ Unit 1b: Shell Settings/Privacy Contract - Implementation
**What**: Extend `Sources/OuroAppShellContract/OuroAppShellContract.swift` with shared settings section descriptors and privacy/diagnostics descriptor fields, validation issues, and docs-friendly Codable/Sendable value types.
**Acceptance**: Targeted shell contract tests pass with `swift test --filter OuroAppShellContractTests -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete`.

### ⬜ Unit 1c: Shell Settings/Privacy Contract - Coverage & Refactor
**What**: Run shell contract test/build gates, refactor names if needed, and ensure branch/error paths have tests.
**Acceptance**: Shell contract tests and `swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete` pass with no warnings.

### ⬜ Unit 2a: Shell Policy Docs And Strictness Matrix - Tests
**What**: Add a shell script or test fixture that fails when the strictness matrix omits current Swift targets or validation commands.
**Acceptance**: The new validation fails before the matrix/doc exists or before all three repo target sets are represented.

### ⬜ Unit 2b: Shell Policy Docs And Strictness Matrix - Implementation
**What**: Add shell docs for settings/telemetry roadmap, privacy/diagnostics contract, native UI testing strategy, and cross-repo Swift strictness matrix; implement the matrix validation script.
**Acceptance**: The validation script passes and the matrix includes every target from the three current `Package.swift` files with current mode, target posture, blockers, and commands.

### ⬜ Unit 2c: Shell Policy Docs And Strictness Matrix - Coverage & Refactor
**What**: Run shell docs/script validation and shell boundary checks.
**Acceptance**: Matrix validation and shell boundary selftest pass.

### ⬜ Unit 3a: Visual Surface Manifest - Tests
**What**: Add a manifest validator test/script that fails on missing manifest rows, unknown validation tools, or shell probe surfaces not represented in the manifest.
**Acceptance**: The validator fails before a compliant manifest exists.

### ⬜ Unit 3b: Visual Surface Manifest - Implementation
**What**: Add `docs/visual-surface-manifest.json` or equivalent structured manifest and wire `scripts/ui-surface-probe.sh` to validate it before running the Swift probe.
**Acceptance**: Manifest validation passes and covers About, update states, settings entry, command reference, and utility windows with validation tool routing.

### ⬜ Unit 3c: Visual Surface Manifest - Coverage & Refactor
**What**: Run shell UI probe and manifest validation, adjusting manifest/probe rows to avoid drift.
**Acceptance**: `scripts/ui-surface-probe.sh` passes or records a hard environment blocker if AppKit/Vision cannot run headlessly.

### ⬜ Unit 4a: Consumer Contract Adoption - Tests
**What**: Add or update Ouro MD and Workbench tests that assert their shell contracts declare shared settings sections and privacy/diagnostics descriptors.
**Acceptance**: Tests fail before consumer contracts include the new required descriptors.

### ⬜ Unit 4b: Consumer Contract Adoption - Implementation
**What**: Update `OuroMDShellContract.swift` and `WorkbenchShellContract.swift` with new settings-section and privacy/diagnostics descriptors, keeping app-specific settings/event/support-bundle implementation local.
**Acceptance**: Consumer contract tests pass in both app repos.

### ⬜ Unit 4c: Consumer Contract Adoption - Coverage & Refactor
**What**: Run targeted and practical consumer validation: contract tests, package build/tests where feasible, and downstream consumer check from the shell.
**Acceptance**: Ouro MD and Workbench compile/tests pass for the touched targets; shell downstream consumer validation passes or records an external blocker with logs.

### ⬜ Unit 5: Final Review, PRs, Merge, Cleanup
**What**: Run final validation, self-review reviewer gate, open PRs for touched repos, merge where safe, and clean James worktrees/branches once terminal.
**Output**: PR links/merge commits, validation logs, and updated desk/task state.
**Acceptance**: All feasible lane work is merged/pushed as permissions allow; residual blockers are evidence-backed and not merely TODOs.

## Execution
- **TDD strictly enforced**: tests -> red -> implement -> green -> refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- **All artifacts**: Save outputs, logs, data to `./2026-06-29-2202-doing-policy-diagnostics-visual-validation/`
- **Fixes/blockers**: Spawn sub-agent immediately - don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- pending initial commit Created from planning doc
