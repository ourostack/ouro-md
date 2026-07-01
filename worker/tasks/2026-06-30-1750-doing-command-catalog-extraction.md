# Doing: Command Catalog Extraction

**Status**: drafting
**Execution Mode**: direct
**Created**: pending initial commit
**Planning**: ./2026-06-30-1750-planning-command-catalog-extraction.md
**Artifacts**: ./2026-06-30-1750-doing-command-catalog-extraction/

## Execution Mode

- **pending**: Awaiting user approval before each unit starts (non-autopilot interactive mode only; autopilot must convert this to `spawn` or `direct` unless a hard exception is present)
- **spawn**: Spawn sub-agent for each unit (parallel/autonomous)
- **direct**: Execute units sequentially in current session (default)

## Objective
Extract the command palette catalog models and filtering policy from the AppKit/WebKit executable target into a small pure support target so command discovery can be tested without loading editor shell types.

## Upstream Work Items
- Desk R4: `/Users/arimendelow/desk/ouro-md/native-app-shell-next-roadmap/task.md`
- Extraction plan: `docs/appkit-webkit-extraction-plan.md`

## Completion Criteria
- [ ] `OuroMDAppSupport` contains the command catalog model/filtering policy and does not import `AppKit`, `SwiftUI`, or `WebKit`.
- [ ] Existing executable target call sites use the extracted catalog with an adapter for `ThemeStore.shared.themes`.
- [ ] Tests fail before implementation and pass after implementation.
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
**What**: Verify command catalog call sites, PR #87 overlap, package target layout, and coverage script behavior.
**Output**: Notes in this doing doc progress log and artifacts as needed.
**Acceptance**: Scope remains limited to command catalog support extraction and excludes PR #87 files.

### ⬜ Unit 1a: Command Catalog Support Boundary — Tests
**What**: Add focused `OuroMDAppSupportTests` proving filtering, shortcut aliases, empty/result limits, and theme command generation against the future support target API.
**Output**: New support-target tests committed before implementation.
**Acceptance**: Focused tests fail because `OuroMDAppSupport` does not exist yet.

### ⬜ Unit 1b: Command Catalog Support Boundary — Implementation
**What**: Add `OuroMDAppSupport`, move `CommandPaletteItem`/`CommandPaletteCatalog` into it, add a theme descriptor adapter in `OuroMD`, and update imports/call sites.
**Output**: Support target, executable adapter, package wiring, and existing call sites compile.
**Acceptance**: Focused tests and existing command/shell tests pass with no warnings.

### ⬜ Unit 1c: Command Catalog Support Boundary — Coverage & Validation
**What**: Extend `scripts/check-coverage.sh` to gate `OuroMDAppSupport`, run required local validation, and refactor only if needed.
**Output**: Coverage gate update and validation logs in artifacts.
**Acceptance**: New support code has 100% line/region coverage; full required local validation passes.

## Execution
- **TDD strictly enforced**: tests → red → implement → green → refactor
- Commit after each phase (1a, 1b, 1c)
- Push after each unit complete
- Run full test suite before marking unit done
- **All artifacts**: Save outputs, logs, data to `./2026-06-30-1750-doing-command-catalog-extraction/` directory
- **Fixes/blockers**: Spawn sub-agent immediately — don't ask, just do it
- **Decisions made**: Update docs immediately, commit right away

## Progress Log
- pending initial commit Created from planning doc
