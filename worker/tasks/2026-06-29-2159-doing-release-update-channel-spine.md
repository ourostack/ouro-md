# Task

Release/update channel spine across Ouro MD, Ouro Workbench, and the shared native app shell.

## Planning Doc

- `worker/tasks/2026-06-29-2159-planning-release-update-channel-spine.md`

## Execution Mode

direct

## Completion Criteria

- [x] Shell install capability modes and channel descriptors are implemented and tested.
- [x] Shell release lifecycle presentation helper and release metadata/policy units are implemented and tested.
- [x] Shared staging/apply value primitives are implemented and adopted or type-aliased by consumers where safe.
- [x] Ouro MD declares review/prompt install capability and uses channel-derived presentation/copy.
- [x] Workbench declares direct install/relaunch capability and uses shell lifecycle presentation helpers.
- [x] Targeted shell, Ouro MD, and Workbench validations pass or have documented hard blockers.
- [ ] PR/merge path is attempted where safe, with terminal evidence recorded.

## Units

### ✅ Unit 1: Shell Release Contract Tests

What: Add failing shell tests for install capability modes, channel descriptors, release metadata, lifecycle presentation derivation, and staging primitive value semantics.

Output: Shell test files updated under `Tests/OuroAppShellCoreTests`, `Tests/OuroAppShellUITests`, and `Tests/OuroAppShellContractTests`.

Acceptance: New tests fail before implementation because the new APIs do not exist or do not produce the expected values.

### ✅ Unit 2: Shell Release Contract Implementation

What: Implement additive shell APIs for `ReleaseInstallCapability`, channel descriptors, `AppReleaseMetadata`, lifecycle presentation input/builder, release policy assertion helpers, and generic staged update/apply value primitives.

Output: Shell source files updated under `Sources/OuroAppShellCore`, `Sources/OuroAppShellUI`, and `Sources/OuroAppShellContract`.

Acceptance: Shell tests pass and existing APIs remain source-compatible for consumers where practical.

### ✅ Unit 3: Ouro MD Consumer Adoption

What: Update Ouro MD contract and adapter tests/code to declare review/prompt install capability and use shell channel/presentation helpers without claiming direct shell install.

Output: Ouro MD adapter/contract/tests updated.

Acceptance: Targeted Ouro MD tests pass; update UI still exposes review/open release, not direct shell install.

### ✅ Unit 4: Workbench Consumer Adoption

What: Update Workbench contract and presenter/tests to use shell capability/channel/presentation helpers while preserving direct install/relaunch behavior.

Output: Workbench adapter/contract/tests updated.

Acceptance: Targeted Workbench tests pass; update state/copy snapshots reflect channel-derived label.

### ⬜ Unit 5: Validation And PR/Merge Prep

What: Run targeted builds/tests/preflight checks, update task evidence, push branches, open PRs, run self-review, and merge where branch protection/CI allow.

Output: Validation logs in `worker/tasks/2026-06-29-2159-doing-release-update-channel-spine/` and PR/merge evidence.

Acceptance: All feasible validations pass; residual blockers are limited to true credentials/capability/branch-protection constraints.

## Progress Log

- 2026-06-29 22:06 Created doing doc after planning approval under autopilot.
- 2026-06-29 22:13 Unit 1 complete: added red shell tests for capability modes, channel descriptors, release metadata, lifecycle presentation, and staging primitives. Red evidence saved in `unit-1-red-shell-tests.log`.
- 2026-06-29 22:15 Unit 2 complete: implemented shell channel descriptors, explicit install capability modes, release metadata, lifecycle presentation input, and staged update/apply value primitives. `swift test --filter 'AppIdentityTests|AppUpdateTests|ReleaseUpdateViewStateTests|OuroAppShellContractTests'` passed with 34 tests.
- 2026-06-29 22:16 Shell full validation passed: `swift test` ran 79 tests with 0 failures.
- 2026-06-29 22:17 Unit 3 complete: Ouro MD now declares `.reviewThenInstall`, routes update state through shell presentation input, and preserves review-only/direct-install-suppressed actions. Targeted MD tests passed with 4 tests.
- 2026-06-29 22:21 Unit 4 complete: Workbench now declares `.directInstallAndRelaunch`, routes update state through shell presentation input, and keeps Workbench-specific retry/detail copy as overrides. Targeted Workbench shell presentation tests passed with 17 tests.
- 2026-06-29 22:22 Shell PR #28 merged to `main` at `e4f1d9f`; consumer `Package.resolved` files updated to that shell revision. Post-merge targeted validations passed: MD 4 tests, Workbench 17 tests.
- 2026-06-29 22:29 Local shell validation passed while hosted app CI remained queued: MD and Workbench `check-shell-dependency.sh` and `check-shell-boundary.sh`.
