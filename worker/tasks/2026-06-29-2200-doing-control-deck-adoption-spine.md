# Doing: Control Deck Adoption Spine

**Status**: IN_REVIEW
**Execution Mode**: direct
**Created**: 2026-06-29 22:00
**Planning**: ./2026-06-29-2200-planning-control-deck-adoption-spine.md
**Artifacts**: ./2026-06-29-2200-doing-control-deck-adoption-spine/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts (non-autopilot interactive mode only; autopilot must convert this to `spawn` or `direct` unless a hard exception is present)
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Make shared shell adoption declarative for current and future Ouro native apps by moving consumer metadata, downstream checks, dependency pinning policy, Workbench coverage policy, and clone hygiene into explicit control decks and validation scripts.

## Upstream Work Items
- A-007
- A-009
- A-019
- A-025
- A-026
- A-033

## Completion Criteria
- [x] Shell downstream consumer checks are driven by a declarative manifest.
- [x] CI matrices for downstream consumers are derived from the manifest.
- [x] Ouro MD and Workbench have app-local control deck manifests.
- [x] Non-shell branch dependencies are rejected unless explicitly covered by policy.
- [x] Workbench coverage and scenario digest policy is structured and validated.
- [x] Downstream clones are cleaned by default or explicitly retained by flag.
- [x] 100% test coverage on all new code
- [x] All tests pass
- [x] No warnings

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
**What**: Read audit items, shell downstream scripts, consumer dependency scripts, Workbench coverage policy, and CI workflows.
**Output**: Concrete manifest and script target list.
**Acceptance**: Evidence recorded in progress log and no referenced path is stale.

### ✅ Unit 1a: Shell Consumer Manifest Tests
**What**: Add shell selftest coverage that fails until downstream manifest validation, command lookup, workflow JSON export, and clone cleanup flag behavior exist.
**Acceptance**: New selftests fail red on the current hardcoded implementation.

### ✅ Unit 1b: Shell Consumer Manifest Implementation
**What**: Add shell-owned downstream consumer JSON manifest, update checker to read commands from it, add `--print-matrix`, add `--keep-worktree`, and update workflows/docs.
**Acceptance**: Selftests pass and downstream consumer names/commands no longer require a shell script case branch.

### ✅ Unit 1c: Shell Verification
**What**: Run shell selftests and matrix export validation.
**Acceptance**: `scripts/check-downstream-consumers.sh --selftest`, `--print-matrix`, `scripts/shell-doctor.sh --selftest`, and relevant workflow syntax checks pass where available.

### ✅ Unit 2a: Ouro MD Control Deck Tests
**What**: Add manifest validation that rejects non-shell branch dependencies unless policy explicitly allows them.
**Acceptance**: Validation fails before the app control deck/policy is added.

### ✅ Unit 2b: Ouro MD Control Deck Implementation
**What**: Add `config/ouro-app-control-deck.json`, validation script, CI/preflight wiring where appropriate, and docs for dependency pinning policy.
**Acceptance**: Validation passes with the shell main dependency allowed and `swift-markdown` policy made explicit.

### ✅ Unit 2c: Ouro MD Verification
**What**: Run the new validation plus existing shell dependency/boundary checks practical for this lane.
**Acceptance**: Commands pass without warnings.

### ✅ Unit 3a: Workbench Control Deck Tests
**What**: Add validation that checks shell dependency policy plus structured coverage/digest policy.
**Acceptance**: Validation fails before the Workbench control deck exists.

### ✅ Unit 3b: Workbench Control Deck Implementation
**What**: Add `config/ouro-app-control-deck.json`, structured coverage/digest policy, validation script, and CI/preflight wiring.
**Acceptance**: Coverage allowlist and scenario digest policy have machine-readable owner/revalidation metadata.

### ✅ Unit 3c: Workbench Verification
**What**: Run the new validation and practical existing policy checks.
**Acceptance**: Commands pass without warnings.

### 🔄 Unit 4: Cross-Repo Review, PRs, Merge
**What**: Run cold self-review, push branches, create PRs, wait for checks, merge where safe, and clean worktrees when terminal.
**Output**: PRs/commits and validation evidence.
**Acceptance**: No ready lane work remains except hard external blockers.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- **All artifacts**: Save outputs, logs, data to `./[task-name]/` directory
- **Fixes/blockers**: Spawn sub-agent immediately — don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- 2026-06-29 22:00 Created from planning doc
- 2026-06-29 22:00 Doing reviewer gates converged: granularity, validation, ambiguity, quality, tinfoil, and stranger-with-candy passes found no blocker or major findings.
- 2026-06-29 22:06 Unit 1 complete: shell commit `78d0564` added `scripts/downstream-consumers.json`, manifest-driven smoke command lookup, `--print-matrix`, `--keep-worktree`, default completed-clone cleanup, workflow matrix derivation, and adoption docs. Verification: `scripts/check-downstream-consumers.sh --selftest`, `scripts/check-downstream-consumers.sh --print-matrix`, `scripts/check-downstream-consumers.sh --warn-pins-current`, and `git diff --check` passed.
- 2026-06-29 22:12 Unit 2 complete: Ouro MD commit `1c999ca` added `config/ouro-app-control-deck.json`, `scripts/check-app-control-deck.py`, CI/preflight wiring, and pinned `swift-markdown` to revision `4661b550c55abde97d14e35b89e094084669f40a`. Verification: validator negative selftest, real validator, `swift package resolve`, `scripts/check-shell-boundary.sh --selftest`, `scripts/check-shell-boundary.sh`, `scripts/check-shell-dependency.sh`, and `git diff --check` passed.
- 2026-06-29 22:18 Unit 3 complete: Workbench commit `6902bdd` added `config/ouro-app-control-deck.json`, `scripts/check-app-control-deck.py`, CI/preflight wiring, structured coverage allowlist metadata, and scenario digest policy for standard/deep verifier runs. Verification: validator negative selftest, real validator, `scripts/check-shell-boundary.sh --selftest`, `scripts/check-shell-boundary.sh`, `scripts/check-shell-dependency.sh`, and `git diff --check` passed.
- 2026-06-29 22:24 Shell verification complete: `swift test -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete` passed with 72 tests and 0 failures.
- 2026-06-29 22:26 Cross-repo downstream validation complete from the shell branch: Ouro MD smoke passed with 236 tests and 0 failures; Workbench smoke passed with 4,476 tests, 1 expected skip, and 0 failures. Completed downstream clones were removed by default.
- 2026-06-29 22:30 CI repair: refreshed the shared shell pins in Ouro MD (`2c64a64`, rebased to `ba8683a`) and Workbench (`e4fdece`) after shell `main` advanced to package-relevant revision `e4f1d9f105399c3f5a6dc1d9188d541d43aa18dd`; local shell dependency and control-deck checks passed in both consumers.
- 2026-06-29 22:34 PRs opened: shell https://github.com/ourostack/ouro-native-apple-app-shell/pull/31, Ouro MD https://github.com/ourostack/ouro-md/pull/83, Workbench https://github.com/ourostack/ouro-workbench/pull/416. Shell PR CI passed: coverage, Swift tests, downstream contract, and both downstream matrix jobs.
