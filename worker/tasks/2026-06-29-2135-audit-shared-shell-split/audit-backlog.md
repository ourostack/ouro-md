# Shared Shell Split Audit Backlog

Canonical source: `worker/tasks/2026-06-29-2135-audit-shared-shell-split/audit-report.md`

Routing rules:

- `planner-required`: needs design/ownership sequencing before edits.
- `inch-worm-ready-after-reeval`: small enough for inch-worm only after the planner-required work in its area lands or is explicitly deferred.
- `defer`: valid observation, but not worth pulling into the current work suite.

## A-001: Unify Release/Update Lifecycle Presentation

Status: queued

Route: planner-required

Severity: High

Problem: The shell owns release/update primitives and UI controls, but lifecycle mapping is still downstream-owned in two shapes. Ouro MD maps `OuroMDUpdateCoordinator` into `ReleaseUpdateViewState` and `ReleaseUpdateActions`; Workbench has a separate `WorkbenchShellUpdatePresenter`. Labels, action availability, warnings, staged/installing/failed semantics, and telemetry-facing state can drift.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellAdapter.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDUpdateCoordinator.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchShellAdapter/WorkbenchShellPresentation.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViewModel.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellUI/ReleaseUpdateViewState.swift`

Planner shape: Design a shell-owned presenter/configuration model for common release lifecycle states. Leave app-specific actions, telemetry names, and install runner details in consumers. Add consumer tests proving both apps produce equivalent user-visible states for checking/current/available/installing/ready/installed/failed.

## A-002: Clarify Install Capability Modes In The Shell Contract

Status: queued

Route: planner-required

Severity: Medium

Problem: `supportsInstallAndRelaunch` is too coarse. Ouro MD declares install support but its shell actions expose check/review/open paths rather than direct `installAndRelaunch`; Workbench exposes direct install. Both may be right, but the contract cannot distinguish "install via review prompt" from "direct shell control can install now."

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellContract.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellAdapter.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchShellAdapter/WorkbenchShellContract.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViewModel.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellContract/OuroAppShellContract.swift`

Planner shape: Split install support into explicit modes such as none, review-only, direct-install, and ready-to-relaunch. Require consumer contract tests to prove declared capability matches runtime actions.

## A-003: Tighten Adapter Boundary Exemptions

Status: queued

Route: planner-required

Severity: Medium

Problem: The boundary scanner broadly exempts shell adapter paths and `AppInfoView.swift`. That makes it possible for reusable shell behavior to accumulate inside adapters without CI pressure. Workbench already has reusable-looking release presenter logic in its adapter, and Ouro MD has app-local shell prompt allowances.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/check-shell-boundary.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/docs/shell-boundary.md`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchShellAdapter/WorkbenchShellPresentation.swift`
- `/Users/arimendelow/Projects/ouro-md/scripts/shell-boundary-allowlist.txt`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppDelegate.swift`

Planner shape: Replace broad path exemptions with an adapter-primitive policy: adapters may translate identity, copy, command rows, app actions, and app-owned settings sections; reusable lifecycle/presentation behavior must live in shell. Add a second scanner or metric that flags adapter files crossing complexity/import/symbol thresholds.

## A-004: Move Direct Update Prompt Chrome Shellward Or Classify It Explicitly

Status: queued

Route: planner-required

Severity: Medium

Problem: Ouro MD still builds the "Software Update" prompt as a direct app-owned `NSAlert`, and the boundary allowlist permits it as "direct-update prompt alerts." The shell docs say release update chrome/presentation should be shared. This may be a legitimate app-domain prompt, but it needs a formal boundary decision because it is exactly the kind of surface future apps will copy.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppDelegate.swift`
- `/Users/arimendelow/Projects/ouro-md/scripts/shell-boundary-allowlist.txt`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/ShellBoundary.swift`

Planner shape: Decide whether update prompt alerts are shell chrome or app-owned install policy prompts. If shell-owned, expose a shared prompt/window primitive. If app-owned, narrow the allowlist reason and add a consumer test that proves the prompt does not duplicate shell-owned update controls.

## A-005: Establish A Single Consumer Command/Surface Manifest Pattern

Status: queued

Route: planner-required

Severity: Medium

Problem: Ouro MD command/menu/surface definitions are scattered across menu builder, command palette items, dispatch code, preferences rows, UI surface tests, and shell adapter rows. Workbench is stronger because it has a shortcut catalog, but it still lets app views/view model traffic in raw shell UI action/state types. The third app needs a clear manifest pattern.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/MenuBuilder.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppModel.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellAdapter.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchKeyboardAccessibilityContract.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViewModel.swift`

Planner shape: Define a consumer-side manifest model for commands, shortcuts, shell command-reference rows, menu mounting, and command-palette entries. Start by adapting Workbench's catalog pattern, then bring Ouro MD closer to it.

## A-006: Continue Workbench View/ViewModel Decomposition

Status: queued

Route: planner-required

Severity: High

Problem: `WorkbenchViewModel.swift` and `WorkbenchViews.swift` remain the biggest architectural risk to preserving the shell split. Shell-adjacent drift can hide inside general UI churn because the files are 11,252 and 10,828 lines respectively.

Evidence:

- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViewModel.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViews.swift`

Planner shape: Continue the existing extraction pattern with narrow view modules and view-model feature slices. Prioritize shell-adjacent areas first: about/update/settings/shortcuts, command palette, onboarding/setup naming, and header menus.

## A-007: Consolidate Shell Consumer Control Decks

Status: queued

Route: planner-required

Severity: Medium

Problem: Shared control-plane behavior is partly in shell and partly duplicated in consumers. Both apps have local shell dependency/boundary/preflight/release policy scripts, while shell has large doctor/scaffold/downstream scripts. Adding a third app still means touching multiple scripts and CI matrices.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/scripts/check-shell-dependency.sh`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/check-shell-dependency.sh`
- `/Users/arimendelow/Projects/ouro-md/scripts/release-policy.sh`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/release-policy.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/shell-doctor.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/check-downstream-consumers.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/downstream-consumers.contract.tsv`

Planner shape: Move package-relevant freshness, boundary invocation, release smoke, and downstream consumer metadata into a shell-owned tool/manifest. Consumers should configure a small manifest, not copy script behavior.

## A-008: Remove Consumer-Branded Convenience APIs From Shell Core

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Medium

Problem: `ReleaseAssetNamingPolicy.workbench()` and `ReleaseUpdatePolicy.workbench()` live in shared shell core. That makes the shared package know one consumer by name, while Ouro MD uses generic policy construction. This is small, but it weakens the "shell is consumer-agnostic" rule.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/ReleaseAssetNamingPolicy.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/ReleaseUpdatePolicy.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellContract.swift`

Re-eval gate: Do after A-001/A-002 decide release/update contract shape. If the planner keeps named presets as intentional examples, document that convention instead of deleting them.

## A-009: Make Downstream Consumer Checks More Declarative

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Low/Medium

Problem: The downstream TSV lists consumer names/repos/refs, but smoke commands are hardcoded by consumer in `check-downstream-consumers.sh`, and CI matrices repeat consumer names. The third app should be addable by one manifest row plus app-local scripts.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/downstream-consumers.contract.tsv`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/check-downstream-consumers.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/.github/workflows/ci.yml`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/.github/workflows/downstream-live.yml`

Re-eval gate: Do after A-007, unless A-007 is explicitly narrowed away from downstream metadata.

## A-010: Refresh Workbench Architecture Docs For The Shell Split

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Medium

Problem: Workbench `AGENTS.md` documents shell ownership, but `docs/architecture.md` does not describe `ouro-native-apple-app-shell`, the `OuroWorkbenchShellAdapter` target, allowed dependency directions, or the shell control-deck scripts.

Evidence:

- `/Users/arimendelow/Projects/ouro-workbench/AGENTS.md`
- `/Users/arimendelow/Projects/ouro-workbench/docs/architecture.md`
- `/Users/arimendelow/Projects/ouro-workbench/Package.swift`

Re-eval gate: Do after A-003/A-005 settle the boundary language so docs do not encode stale rules.

## A-011: Fix Small User-Facing Naming/Comment Drift

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Low

Problem: A few small strings/comments are stale enough to mislead future agents or users:

- Workbench shortcut sheet comment says `⌘?`, while the real registered/tested shortcut is `⌘/`.
- Workbench README/guide still mention `Set Up Workbench`, while current product copy says `Set up a boss`.
- Ouro MD release workflow comments still mention bumping `make-app.sh`, while current scripts derive app version from `OuroMDRelease.swift`.

Evidence:

- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViews.swift`
- `/Users/arimendelow/Projects/ouro-workbench/README.md`
- `/Users/arimendelow/Projects/ouro-workbench/docs/guide.md`
- `/Users/arimendelow/Projects/ouro-md/.github/workflows/release.yml`
- `/Users/arimendelow/Projects/ouro-md/README.md`

Re-eval gate: Can be first inch-worm bite after planner accepts or defers the larger shell-boundary items.

## A-012: Decide Whether `What's New` Is A Distinct Shell Surface

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Low/Medium

Problem: Ouro MD exposes "What's New" in menu/command surfaces, but the delegate currently routes it through the About surface. The shell docs classify "About / What's New" together, so this may be intentional. It should be made explicit before the third app copies one of the two interpretations.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/MenuBuilder.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppDelegate.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppInfoView.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/docs/shell-boundary.md`

Re-eval gate: Do after A-005 defines command/surface manifest semantics.

## A-013: Keep Ouro MD Core Editor Decomposition On The Radar

Status: deferred

Route: defer

Severity: Medium

Problem: Ouro MD still has broad core files (`AppModel.swift` at 1,461 lines and `web/bridge.js` at 1,249 lines). This is a real maintainability signal, but it is less directly tied to the shared shell split than the release/update and command/surface items above.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppModel.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/web/bridge.js`

Defer rationale: Revisit in a separate Ouro MD editor architecture audit or after the shell control-plane work lands.

