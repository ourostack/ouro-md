# Planning: Shared Shell Policy Diagnostics Visual Validation

**Status**: drafting
**Created**: pending initial commit

## Goal
Implement the policy/diagnostics/visual-validation lane for the shared Ouro native app shell campaign across Ouro MD, Ouro Workbench, and the shared shell. The lane should turn settings/telemetry, privacy/diagnostics, Swift strictness, visual surface coverage, and native UI testing strategy from audit backlog items into enforceable docs, contracts, manifests, scripts, and tests where feasible.

## Upstream Work Items
- A-015: Shared settings/telemetry roadmap
- A-020: Swift strictness matrix
- A-021: Cross-app visual surface manifest
- A-029: Privacy/diagnostics contract
- A-030: Shared UI testing strategy

**DO NOT include time estimates (hours/days) - planning should focus on scope and criteria, not duration.**

## Scope

### In Scope
- Add shell-owned contract data for shared settings sections and privacy/diagnostics disclosure, with validator coverage in `ouro-native-apple-app-shell`.
- Add shell-owned documentation for shared settings/telemetry roadmap, privacy/diagnostics requirements, Swift strictness expectations, native UI testing strategy, and visual surface manifest expectations.
- Add a manifest-driven visual surface validation path in the shell, and wire shell CI/scripts so the manifest is checked by the surface probe.
- Add consumer contract declarations or validation fixtures in Ouro MD and Ouro Workbench where needed to prove the new shell contracts and manifest policy can be adopted by both apps.
- Add focused tests and script checks for new shell contracts, manifest parsing, and consumer declarations.
- Run practical shell and consumer validation gates from the dedicated James worktrees.

### Out of Scope
- Do not implement release/update staging, signing, notarization, App Store, or direct-download installer behavior.
- Do not perform a drive-by Swift 6 language-mode migration for Ouro MD or Workbench.
- Do not decompose Workbench views or replace Workbench's existing ViewInspector coverage beyond documenting the shared strategy and validating test-only scope.
- Do not move app-specific telemetry event names, payload semantics, document editor behavior, boss/session diagnostics internals, or support-bundle collectors into the shell.
- Do not depend on A-023 implementation for this lane; if A-021 cannot fully enforce runtime command/action parity without A-023, record that as a manifest boundary and validate the feasible manifest layer.

## Completion Criteria
- [ ] A-015 is represented by shell settings-section and telemetry-envelope roadmap/docs, plus contract data/tests where feasible.
- [ ] A-020 is represented by a cross-repo Swift strictness matrix and a validation command or script check.
- [ ] A-021 is represented by a shell-owned visual surface manifest and validation path that covers shell surfaces and consumer expectations.
- [ ] A-029 is represented by a shell privacy/diagnostics descriptor contract with validator/tests and consumer declarations.
- [ ] A-030 is represented by a native-app UI testing strategy doc and any feasible helper/manifest routing support.
- [ ] Ouro MD and Ouro Workbench consume or validate the new contract fields without moving app-owned behavior into the shell.
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
- [ ] A-021 depends on A-023 in the upstream PERT chart. Decision under autopilot: implement the manifest/probe layer now and leave deeper runtime parity assertions to A-023-owned helpers.
- [ ] The repo-local `subagents/work-planner.md` and `subagents/work-doer.md` files are absent in the current Ouro MD checkout. Decision under autopilot: use installed Work Suite skill files and record the absence as source-check evidence.

## Decisions Made
- Use dedicated branches/worktrees named `james/policy-diagnostics-visual-validation` for all three repos: `/Users/arimendelow/Projects/ouro-md-james-policy`, `/Users/arimendelow/Projects/ouro-workbench-james-policy`, and `/Users/arimendelow/Projects/ouro-shell-james-policy`.
- Keep shell additions generic: settings sections, telemetry consent/envelope requirements, privacy/diagnostics descriptors, surface manifest rows, and testing-tool routing live in shell; consumer-specific settings labels, event names, support bundle implementation, and domain diagnostics stay in the apps.
- Treat human approval gates as disabled by the operator's autopilot mandate; use reviewer gates and concrete validation instead.
- Keep A-020 to a matrix and validation policy. Do not change Swift language modes as part of this lane.

## Context / References
- Source backlog: Ouro MD `origin/worker/shared-shell-systems-audit:worker/tasks/2026-06-29-2135-audit-shared-shell-split/audit-backlog.md`
- PERT source: Ouro MD `origin/worker/shared-shell-systems-audit:worker/tasks/2026-06-29-2135-audit-shared-shell-split/pert-chart.md`
- Shell contract: `/Users/arimendelow/Projects/ouro-shell-james-policy/Sources/OuroAppShellContract/OuroAppShellContract.swift`
- Shell boundary: `/Users/arimendelow/Projects/ouro-shell-james-policy/Sources/OuroAppShellCore/ShellBoundary.swift`
- Shell surface probe: `/Users/arimendelow/Projects/ouro-shell-james-policy/Sources/OuroAppShellUISurfaceProbe/main.swift`
- Shell downstream check: `/Users/arimendelow/Projects/ouro-shell-james-policy/scripts/check-downstream-consumers.sh`
- Ouro MD contract/privacy/surface probe: `/Users/arimendelow/Projects/ouro-md-james-policy/Sources/OuroMD/OuroMDShellContract.swift`, `/Users/arimendelow/Projects/ouro-md-james-policy/PRIVACY.md`, `/Users/arimendelow/Projects/ouro-md-james-policy/Sources/OuroMD/UISurfaceTest.swift`
- Workbench contract/diagnostics/testing: `/Users/arimendelow/Projects/ouro-workbench-james-policy/Sources/OuroWorkbenchShellAdapter/WorkbenchShellContract.swift`, `/Users/arimendelow/Projects/ouro-workbench-james-policy/Sources/OuroWorkbenchCore/BugReport.swift`, `/Users/arimendelow/Projects/ouro-workbench-james-policy/Package.swift`

## Notes
The shell already has `OuroAppShellSettingsContract(entryPoint:appOwnedSections:)` and a `.telemetry` boundary surface, but no shared section descriptors, telemetry consent envelope, privacy/diagnostics descriptor, or manifest-owned visual surface rows. Ouro MD declares Updates and Telemetry as app-owned settings sections and has `PRIVACY.md`; Workbench declares Software Updates and support diagnostics in README/recovery docs and keeps ViewInspector pinned to test targets only.

## Progress Log
- pending initial commit Created
