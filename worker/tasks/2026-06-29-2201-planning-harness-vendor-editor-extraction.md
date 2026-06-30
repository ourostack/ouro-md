# Planning: Harness, Vendor, And Editor Extraction Guardrails

**Status**: approved
**Created**: 2026-06-29 22:01

## Goal
Formalize Ouro MD's shipped CLI and diagnostic harness boundary, add durable provenance policy for vendored Vditor assets, and define a testable AppKit/WebKit extraction plan so future editor decomposition work starts from evidence instead of file size alone.

## Upstream Work Items
- A-017: Formalize Ouro MD's Shipped Harness/Probe Boundary
- A-018: Add A Vendor Provenance Policy For Ouro MD's Web Editor Assets
- A-036: Give Ouro MD AppKit/WebKit Code A Gradual Library-Extraction Plan
- A-013: Keep Ouro MD Core Editor Decomposition On The Radar

**DO NOT include time estimates (hours/days) — planning should focus on scope and criteria, not duration.**

## Scope

### In Scope
- Add `docs/shipped-cli-and-harness-policy.json` as a machine-readable inventory for all shipped non-GUI CLI modes routed from `Sources/OuroMD/main.swift`, with public/maintainer modes classified separately from hidden diagnostic harness modes.
- Add a script-enforced check that the harness policy matches `main.swift`, `scripts/run-native-scenarios.sh`, and release-relevance classification.
- Add `docs/vditor-vendor-manifest.json` describing upstream source, version/provenance, license, refresh policy, asset digest, and validation commands.
- Add a script-enforced check that Vditor vendored files still match the manifest and that release/preflight runs the check.
- Add an AppKit/WebKit extraction plan document identifying candidate seams for a future `OuroMDAppSupport` or `OuroMDEditorSupport` library, test strategy, ordering, and explicit non-goals.
- Keep A-013 as radar only by documenting that broad `AppModel.swift` / `web/bridge.js` decomposition is deferred until the A-036 extraction plan proves the next split.
- Wire new checks into local PR preflight and existing release-policy selftests where appropriate.

### Out of Scope
- Moving harness files into a new Swift executable target in this pass.
- Refactoring `AppModel.swift`, `EditorWebView.swift`, `OuroMDUpdateCoordinator.swift`, or `web/bridge.js` as product-code decomposition.
- Changing Vditor assets, upgrading Vditor, or replacing the editor library.
- Implementing shared shell release/update/control-deck behavior outside what is needed to keep Ouro MD checks green.
- Editing Ouro Workbench or the shared shell, except for small adapter docs if an Ouro MD check requires it.

## Completion Criteria
- [x] A-017 has a documented and machine-checked shipped diagnostic harness contract.
- [x] A-018 has a documented and machine-checked Vditor vendor provenance policy.
- [x] A-036 has a concrete extraction plan with candidates, ordering, tests, and A-013 disposition.
- [x] New checks are part of PR preflight or release-policy selftests so CI/local validation can catch drift.
- [x] Existing release freshness behavior remains intentional for harness-only edits and Vditor/resource edits.
- [x] 100% test coverage on all new code
- [x] All tests pass
- [x] No warnings

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch, try/catch)
- All error paths tested
- Edge cases: null, empty, boundary values

## Open Questions
- [ ] None. Autopilot decision: keep harnesses shipped but explicitly contract and scan them rather than extracting targets immediately, because the current CI/package verification relies on packaged app harness entry points.

## Decisions Made
- Use repo-local policy files under `docs/` rather than a shell-owned manifest for this lane, because the work items are Ouro MD-specific and the user asked to keep write scope primarily in Ouro MD.
- Treat `--render`, `--shoot`, `--roundtrip`, `--bundleprobe`, `--version`, `--help`, and `--list-themes` as shipped public/maintainer CLI modes that must appear in the policy inventory, but not as hidden diagnostic harness modes.
- Treat hidden harness modes as shipped diagnostic modes: allowed in release artifacts, reachable only by explicit flags, no normal GUI launch path, no private document upload, and covered by scenario/preflight checks.
- Use SHA-256 digests over the tracked vendored Vditor files to detect accidental edits without storing hundreds of per-file hashes in the manifest.
- A-013 remains deferred until A-036's plan identifies the first low-risk extraction candidate and associated tests.

## Context / References
- Source backlog reference loaded with `git show`: `origin/worker/shared-shell-systems-audit:worker/tasks/2026-06-29-2135-audit-shared-shell-split/audit-backlog.md`
- PERT lane reference loaded with `git show`: `origin/worker/shared-shell-systems-audit:worker/tasks/2026-06-29-2135-audit-shared-shell-split/pert-chart.md`
- Harness flags: `Sources/OuroMD/main.swift`
- Harness runners: `scripts/run-native-scenarios.sh`, `scripts/run-visual-qa.sh`, `scripts/verify-packaged-app.sh`
- Release classifier: `scripts/release-policy.sh`
- Preflight: `scripts/pr-preflight.sh`
- Vditor assets: `Sources/OuroMD/web/vditor`
- Coverage boundary: `scripts/check-coverage.sh`
- Extraction candidates: `Sources/OuroMD/AppModel.swift`, `Sources/OuroMD/EditorWebView.swift`, `Sources/OuroMD/OuroMDUpdateCoordinator.swift`, `Sources/OuroMD/web/bridge.js`, `Package.swift`

## Notes
The current release classifier already excludes `Sources/OuroMD/*Test.swift`, `Sources/OuroMD/*Probe.swift`, `Sources/OuroMD/Snapshot.swift`, `Sources/OuroMD/RoundTrip.swift`, and `Sources/OuroMD/HeadlessHarness.swift` from release freshness gating. This pass should preserve that intent while making the shipped harness surface explicit and drift-checked.

Current Vditor inventory at planning time: `Sources/OuroMD/web/vditor` contains 529 tracked files, is about 23 MB, and its tracked-file path list digest is `15f4ede251f16d24f7083113a486458c74f66564afa381c3d96053318af8487a`. The content digest must be generated from tracked file paths plus bytes during implementation.

## Progress Log
- 2026-06-29 22:01 Created
- 2026-06-29 22:05 Addressed reviewer findings by separating public/maintainer CLI modes from hidden diagnostic harness modes and naming the policy files.
- 2026-06-29 22:08 Approved after reviewer gate convergence.
- 2026-06-29 22:55 Completed with full PR preflight passing.
