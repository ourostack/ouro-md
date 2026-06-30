# Planning: Control Deck Adoption Spine

**Status**: approved
**Created**: 2026-06-29 22:00

## Goal
Make shared shell adoption declarative for current and future Ouro native apps by moving consumer metadata, downstream checks, dependency pinning policy, Workbench coverage policy, and clone hygiene into explicit control decks and validation scripts.

## Upstream Work Items
- A-007
- A-009
- A-019
- A-025
- A-026
- A-033

## Scope

### In Scope
- Add a shell-owned downstream consumer manifest that records consumer repository, refs, adoption metadata, smoke commands, and local manifest paths.
- Update shell downstream checks and CI to read the manifest instead of hardcoding consumer command branches and workflow matrices.
- Add app-local control deck manifests for Ouro MD and Workbench.
- Add validation for non-shell branch dependency policy and Workbench coverage/digest policy.
- Add docs that define the third-app adoption source of truth and downstream clone cleanup behavior.

### Out of Scope
- Direct release/update API changes.
- UI refactors or shell presentation changes.
- Changing app runtime adapters except where a manifest consumer is needed.
- Changing dependency versions or release channels unless required by validation.

## Completion Criteria
- [ ] Shell downstream consumer checks are driven by a declarative manifest.
- [ ] CI matrices for downstream consumers are derived from the manifest.
- [ ] Ouro MD and Workbench have app-local control deck manifests.
- [ ] Non-shell branch dependencies are rejected unless explicitly covered by policy.
- [ ] Workbench coverage and scenario digest policy is structured and validated.
- [ ] Downstream clones are cleaned by default or explicitly retained by flag.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No warnings

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch, try/catch)
- All error paths tested
- Edge cases: null, empty, boundary values

## Open Questions
- [x] Can workflow matrix derivation be done without adding a new action or generated committed file? Answer: yes, use a shell script command that emits JSON and `fromJSON` in GitHub Actions.
- [x] Should clone hygiene delete clones after every run? Answer: yes by default, with `--keep-worktree` for local debugging.

## Decisions Made
- Use JSON manifests because GitHub Actions can consume JSON directly and Python stdlib can validate it without extra dependencies.
- Keep the legacy downstream TSV as compatibility input only if needed; the new manifest is the source of truth.
- Put app-local control decks under `config/ouro-app-control-deck.json` so future apps have a predictable location outside scripts.
- Use reviewer-gate convergence under the active autopilot mandate; no human stop is required for this planning approval.

## Context / References
- `/tmp/ouro-audit-backlog.md`
- `/tmp/ouro-audit-report.md`
- `/tmp/ouro-pert-chart.md`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell-worker-control-deck/scripts/check-downstream-consumers.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell-worker-control-deck/.github/workflows/ci.yml`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell-worker-control-deck/.github/workflows/downstream-live.yml`
- `/Users/arimendelow/Projects/ouro-md-worker-control-deck/Package.swift`
- `/Users/arimendelow/Projects/ouro-workbench-worker-control-deck/scripts/check-coverage.sh`

## Notes
Cold review pass: the plan preserves the requested lane boundaries and avoids release/update APIs and UI surfaces. The only durable naming choice is the manifest path, which is reviewer-gated by autopilot.

## Progress Log
- 2026-06-29 22:00 Created
- 2026-06-29 22:00 Planning reviewer gate converged; no blocker or major findings.
