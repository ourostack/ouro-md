# Task

Release/update channel spine across Ouro MD, Ouro Workbench, and the shared native app shell.

## Planning Doc

- `worker/tasks/2026-06-29-2159-planning-release-update-channel-spine.md`

## Execution Mode

direct

## Completion Criteria

- [ ] Shell install capability modes and channel descriptors are implemented and tested.
- [ ] Shell release lifecycle presentation helper and release metadata/policy units are implemented and tested.
- [ ] Shared staging/apply value primitives are implemented and adopted or type-aliased by consumers where safe.
- [ ] Ouro MD declares review/prompt install capability and uses channel-derived presentation/copy.
- [ ] Workbench declares direct install/relaunch capability and uses shell lifecycle presentation helpers.
- [ ] Targeted shell, Ouro MD, and Workbench validations pass or have documented hard blockers.
- [ ] PR/merge path is attempted where safe, with terminal evidence recorded.

## Units

### ⬜ Unit 1: Shell Release Contract Tests

What: Add failing shell tests for install capability modes, channel descriptors, release metadata, lifecycle presentation derivation, and staging primitive value semantics.

Output: Shell test files updated under `Tests/OuroAppShellCoreTests`, `Tests/OuroAppShellUITests`, and `Tests/OuroAppShellContractTests`.

Acceptance: New tests fail before implementation because the new APIs do not exist or do not produce the expected values.

### ⬜ Unit 2: Shell Release Contract Implementation

What: Implement additive shell APIs for `ReleaseInstallCapability`, channel descriptors, `AppReleaseMetadata`, lifecycle presentation input/builder, release policy assertion helpers, and generic staged update/apply value primitives.

Output: Shell source files updated under `Sources/OuroAppShellCore`, `Sources/OuroAppShellUI`, and `Sources/OuroAppShellContract`.

Acceptance: Shell tests pass and existing APIs remain source-compatible for consumers where practical.

### ⬜ Unit 3: Ouro MD Consumer Adoption

What: Update Ouro MD contract and adapter tests/code to declare review/prompt install capability and use shell channel/presentation helpers without claiming direct shell install.

Output: Ouro MD adapter/contract/tests updated.

Acceptance: Targeted Ouro MD tests pass; update UI still exposes review/open release, not direct shell install.

### ⬜ Unit 4: Workbench Consumer Adoption

What: Update Workbench contract and presenter/tests to use shell capability/channel/presentation helpers while preserving direct install/relaunch behavior.

Output: Workbench adapter/contract/tests updated.

Acceptance: Targeted Workbench tests pass; update state/copy snapshots reflect channel-derived label.

### ⬜ Unit 5: Validation And PR/Merge Prep

What: Run targeted builds/tests/preflight checks, update task evidence, push branches, open PRs, run self-review, and merge where branch protection/CI allow.

Output: Validation logs in `worker/tasks/2026-06-29-2159-doing-release-update-channel-spine/` and PR/merge evidence.

Acceptance: All feasible validations pass; residual blockers are limited to true credentials/capability/branch-protection constraints.

## Progress Log

- 2026-06-29 22:06 Created doing doc after planning approval under autopilot.
