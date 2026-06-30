# Shared Shell Split Audit Backlog

Canonical source: `worker/tasks/2026-06-29-2135-audit-shared-shell-split/audit-report.md`

PERT sequencing: `worker/tasks/2026-06-29-2135-audit-shared-shell-split/pert-chart.md`

Implementation outcome: all non-deferred backlog lanes were executed in the
2026-06-30 Work Suite/autopilot campaign. The per-item `Status: queued` fields
below are the historical pre-campaign queue state; see
`audit-report.md#implementation-outcome-2026-06-30` for the terminal PR ledger.

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

## A-014: Narrow Raw Shell UI Type Traffic In Consumers

Status: queued

Route: planner-required

Severity: High

Problem: Workbench app views/view model and Ouro MD adapter-adjacent code traffic directly in raw shell UI types such as `ReleaseUpdateViewState`, `ReleaseUpdateActions`, and `AppShellAboutActions`. Some direct use is legitimate, but the current shape makes it hard to tell adapter glue from shared behavior that should move shellward.

Evidence:

- `/Users/arimendelow/Projects/ouro-workbench/Package.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViewModel.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchViews.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchShellAdapter/WorkbenchShellPresentation.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellAdapter.swift`

Dependencies: A-001, A-002, A-003

Planner shape: Define adapter-facing facades that expose product-language state/actions to app views while keeping shell UI structs at the adapter boundary. Let shell types remain public for app adapters and tests, but discourage broad app-module imports.

## A-015: Move Shared Settings Chrome And Telemetry Consent Into The Shell Roadmap

Status: queued

Route: planner-required

Severity: Medium

Problem: Shell boundary docs explicitly say settings chrome and telemetry consent/common event envelope "should" be shared, but both are still adapter-owned. Ouro MD already has settings sections for Updates and Telemetry; Workbench has its own settings surface. Future apps will otherwise invent consent, settings entry points, and common diagnostics shape separately.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/docs/shell-boundary.md`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/ShellBoundary.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellContract.swift`
- `/Users/arimendelow/Projects/ouro-md/PRIVACY.md`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchShellAdapter/WorkbenchShellContract.swift`

Planner shape: Add shell-owned settings section descriptors for common sections such as Updates, Telemetry, About, Shortcuts, and Privacy. Separate the common telemetry consent/envelope shape from app-specific event names and payload policy.

## A-016: Extract Shared Update Staging/Install Primitives

Status: queued

Route: planner-required

Severity: High

Problem: The shell owns update checking and install planning, but each app still owns its staging/apply/relaunch machinery. That may be necessary in places, but both direct-download native apps need the same invariants: manifest fetch, archive SHA/byte verification, bundle identity checks, backup/rollback, staged update persistence, and relaunch handoff.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDUpdateInstaller.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDUpdateCoordinator.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/LiveUpdateTest.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchCore/WorkbenchUpdateStager.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/AppUpdate.swift`

Dependencies: A-001, A-002

Planner shape: Decide which parts of staging/apply are safely generic for direct-download macOS apps and move those into shell core. Leave bundle-specific identities, app names, telemetry, and final UI triggers in consumers.

## A-017: Formalize Ouro MD's Shipped Harness/Probe Boundary

Status: queued

Route: planner-required

Severity: Medium

Problem: Ouro MD includes more than twenty `*Test.swift`/`*Probe.swift` harness files in the executable target, with hidden flags routed from `main.swift`. This is useful for CI and dogfooding, but it also means release builds ship test/probe entry points unless the boundary is explicitly documented and gated.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/main.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/UISurfaceTest.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/TableWrapTest.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/VisualQATest.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/LiveUpdateTest.swift`
- `/Users/arimendelow/Projects/ouro-md/scripts/run-native-scenarios.sh`

Planner shape: Either extract harnesses into a separate executable target or keep them intentionally in the app with a documented "shipped diagnostic modes" contract, release scan, and user/privacy guarantees.

## A-018: Add A Vendor Provenance Policy For Ouro MD's Web Editor Assets

Status: queued

Route: planner-required

Severity: Medium

Problem: Ouro MD vendors a 23 MB `Sources/OuroMD/web/vditor` distribution as app resources. It includes a license file, but the audit did not find a durable provenance/update/security policy that tells agents how it was produced, which upstream version it represents, or how to refresh it without accidentally changing editor behavior.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/web/vditor`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/web/vditor/LICENSE`
- `/Users/arimendelow/Projects/ouro-md/Package.swift`

Planner shape: Add a vendor manifest with upstream package/version/commit, license, build command, expected checksums, and refresh validation. Include release-policy checks so generated/minified assets are not edited blindly.

## A-019: Define Dependency Pinning Policy For Non-Shell Dependencies

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Medium

Problem: The shell dependency intentionally tracks `main` with freshness automation, but Ouro MD also depends on `swift-markdown` using `branch: "main"` without an equivalent freshness/update policy. Workbench's non-shell dependencies use version ranges/exact pins. A future dependency update can silently alter parsing/rendering behavior.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Package.swift`
- `/Users/arimendelow/Projects/ouro-md/Package.resolved`
- `/Users/arimendelow/Projects/ouro-workbench/Package.swift`

Re-eval gate: Do after A-007 clarifies the shared dependency control-deck. If shell-main remains special, document that special case and pin or guard other branch dependencies.

## A-020: Normalize Swift Language Mode And Strict-Concurrency Expectations

Status: queued

Route: planner-required

Severity: Medium

Problem: The repos all use Swift tools 6, but their language/strictness posture differs. Ouro MD explicitly sets Swift language mode v5 in source and test targets; Workbench relies on strict flags in scripts and tests; shell CI uses warnings-as-errors and strict concurrency. Shared app-shell APIs will be easier to evolve if the expected compiler strictness is declared per target.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Package.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Package.swift`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/check-swift-tests.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/check-coverage.sh`

Planner shape: Create a cross-repo compiler-strictness matrix: current mode, target mode, blockers, and CI gates. Do not flip MD to Swift 6 as a drive-by; plan it.

## A-021: Make App-Shell Visual Surface Coverage Cross-App And Manifest-Driven

Status: queued

Route: planner-required

Severity: Medium

Problem: Shell has a UI surface probe, and downstream checks run consumer `--uisurfacetest` commands, but the coverage is split by convention rather than a shared manifest of required shell surfaces and expected states. New shared shell surfaces need a single place to declare "every consumer must render these states."

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellUISurfaceProbe/main.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/ui-surface-probe.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/check-downstream-consumers.sh`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/UISurfaceTest.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchAppViews/WorkbenchKeyboardAccessibilityContract.swift`

Planner shape: Define a shell-owned surface-state manifest for About, update states, settings entry, command reference, and utility windows. Let consumers provide adapters/fixtures, then have shell CI verify the same manifest across shell, MD, and Workbench.

## A-022: Replace Text-Grep Boundary Scanning With A Typed Boundary Analyzer

Status: queued

Route: planner-required

Severity: Medium

Problem: `check-shell-boundary.sh` is useful but textual. It scans for string patterns such as `NSAlert()` and `ReleaseUpdateControls(` and skips broad adapter paths. This will miss aliases/wrappers and can flag benign code while letting generic behavior hide behind allowed file names.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/check-shell-boundary.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/ShellBoundary.swift`
- `/Users/arimendelow/Projects/ouro-md/scripts/shell-boundary-allowlist.txt`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/shell-boundary-allowlist.txt`

Dependencies: A-003

Planner shape: Move from fixed grep rules toward a typed analyzer that understands imports, target membership, symbol references, adapter modules, and contract declarations. Keep the grep gate as a cheap first-pass until the typed analyzer is trusted.

## A-023: Strengthen Consumer Contract Assertions Beyond Presence Counts

Status: queued

Route: planner-required

Severity: Medium

Problem: `OuroAppShellContract` validates identity fields, required surfaces, descriptors, and basic command counts/sections, but it does not prove runtime surfaces match declared rows/actions/modes. That leaves command rows, utility windows, install modes, and settings sections vulnerable to drift between contract, menus, command palette, and rendered UI.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellContract/OuroAppShellContract.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellConsumerTesting/OuroAppShellContractAssertions.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellContract.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchShellAdapter/WorkbenchShellContract.swift`

Dependencies: A-002, A-005

Planner shape: Add optional consumer assertion helpers that compare contract declarations against runtime command catalogs, utility window specs, settings section catalogs, and release action modes.

## A-024: Model Future Signed/Notarized/App-Store Channels In The Shell

Status: queued

Route: planner-required

Severity: Medium

Problem: Direct download should remain supported, but the shell/update model should not bake in today's unsigned/ad-hoc dogfood state. Once Developer ID signing, notarization, Sparkle-like flows, or App Store distribution enter, update checking, install labels, release pages, and channel eligibility need a shared representation.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/README.md`
- `/Users/arimendelow/Projects/ouro-md/scripts/check-signing-readiness.sh`
- `/Users/arimendelow/Projects/ouro-md/.github/workflows/release.yml`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/AppIdentity.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellCore/ReleaseUpdate.swift`

Planner shape: Extend shell release/update contracts with distribution channel capabilities while preserving direct download. Keep signing/notarization execution deferred until product dogfood says it is time.

## A-025: Give Third-App Adoption A Single Source Of Truth

Status: queued

Route: planner-required

Severity: Medium

Problem: Adding a third native app currently requires understanding shell docs, scaffold output, shell doctor expectations, downstream TSV rows, CI matrices, consumer scripts, and app-local adapter conventions. That is too much ambient knowledge for the next app.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/docs/shell-boundary.md`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/scaffold-consumer-adoption.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/shell-doctor.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/downstream-consumers.contract.tsv`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/.github/workflows/ci.yml`

Dependencies: A-007, A-009

Planner shape: Create a shell-owned consumer manifest/schema that drives scaffold, doctor, downstream checks, docs, and CI matrix generation. The third app should be addable by one manifest plus app adapter code.

## A-026: Audit Workbench Coverage Allowlist And Digest Control Deck As Product Infrastructure

Status: queued

Route: planner-required

Severity: Medium

Problem: Workbench coverage gates are strong, but `coverage-allowlist.txt` is now a large historical ledger, and scenario coverage digests are hardcoded in workflow/scripts/docs. This is high-value infrastructure, but it needs a clearer data model before more apps copy it.

Evidence:

- `/Users/arimendelow/Projects/ouro-workbench/scripts/check-coverage.sh`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/coverage-allowlist.txt`
- `/Users/arimendelow/Projects/ouro-workbench/.github/workflows/ci.yml`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/preflight.sh`
- `/Users/arimendelow/Projects/ouro-workbench/docs/native-scenario-verifier.md`

Planner shape: Split durable coverage policy from historical narrative. Keep strict gates, but move allowlist rows/digests into structured data with validation, owner, last-verified run, and revalidation command.

## A-027: Clean Up Or Archive Stale Workbench Planning/Doing Docs

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Low/Medium

Problem: Workbench's `docs/` folder contains many historical planning/doing/backlog docs alongside current architecture/user docs. That is useful history, but it makes "read every doc" audits noisy and can surface stale product language such as old setup naming.

Evidence:

- `/Users/arimendelow/Projects/ouro-workbench/docs/architecture.md`
- `/Users/arimendelow/Projects/ouro-workbench/docs/fre-ux-backlog.md`
- `/Users/arimendelow/Projects/ouro-workbench/docs/fre-subtraction-doing.md`
- `/Users/arimendelow/Projects/ouro-workbench/docs/onboarding-overhaul-doing.md`
- `/Users/arimendelow/Projects/ouro-workbench/docs/guide.md`

Re-eval gate: Do after A-010 refreshes architecture docs. Then archive or index historical docs so agents know which docs are normative and which are project history.

## A-028: Build A Cross-Repo Release Metadata Model

Status: queued

Route: planner-required

Severity: Medium

Problem: Release metadata lives in app code, README copy, workflow comments, release scripts, release highlights, and package automation. The repos have guards, but the shared native app suite would benefit from a common release metadata model that all release tooling reads.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMDCore/OuroMDRelease.swift`
- `/Users/arimendelow/Projects/ouro-md/.github/workflows/shell-dependency-watch.yml`
- `/Users/arimendelow/Projects/ouro-md/scripts/bump-version.sh`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchCore/WorkbenchRelease.swift`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/release-policy.sh`

Planner shape: Define a minimal shared release metadata schema for app name, version, build, release date, repository, release channel, highlights, and shell pin. Consumers can keep local Swift constants generated from or checked against that schema.

## A-029: Add A Shell-Owned Privacy/Diagnostics Surface Contract

Status: queued

Route: planner-required

Severity: Medium

Problem: Ouro MD has explicit privacy and telemetry docs; Workbench has diagnostics/bug-report/support surfaces. The shell boundary says telemetry consent/common event envelope should be shared, but there is no shell-owned privacy/diagnostics contract covering what user-visible disclosure every native app must provide.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/PRIVACY.md`
- `/Users/arimendelow/Projects/ouro-md/README.md`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchCore/BugReport.swift`
- `/Users/arimendelow/Projects/ouro-workbench/docs/recovery.md`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/docs/shell-boundary.md`

Dependencies: A-015

Planner shape: Define a shell privacy/diagnostics descriptor: telemetry consent entry, privacy doc URL, diagnostics export disclosure, support bundle contents, and content-redaction guarantees.

## A-030: Decide Whether Test-Only ViewInspector Should Become A Shared Testing Pattern

Status: queued

Route: planner-required

Severity: Low/Medium

Problem: Workbench uses exact-pinned ViewInspector for app-view coverage and documents why. Ouro MD and shell use custom surface probes/Vision/OCR instead. The split may be intentional, but future apps need guidance on when to use ViewInspector, shell UI surface probes, app headless probes, or native accessibility checks.

Evidence:

- `/Users/arimendelow/Projects/ouro-workbench/Package.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Tests/OuroWorkbenchAppViewsTests`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/UISurfaceTest.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellUISurfaceProbe/main.swift`

Planner shape: Create a native-app UI testing strategy doc and optional shell testing helper that routes surface types to the right tool: pure view inspection, shell surface probe, app harness, accessibility tree, or screenshot/OCR.

## A-031: Align Minimum macOS Platform Strategy Across Shell And Consumers

Status: queued

Route: defer

Severity: Low/Medium

Problem: Shell and Ouro MD support macOS 13, while Workbench declares macOS 14. This is probably product-driven, but shared shell APIs need a platform floor strategy so shell does not accidentally adopt APIs that strand MD or force Workbench-specific forks.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Package.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Package.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Package.swift`

Defer rationale: Revisit when a shell feature wants macOS 14+ APIs or when a third app chooses a platform floor.

## A-032: Add A Public Surface Naming Audit To CI For Command/Menu/Shortcut Drift

Status: queued

Route: planner-required

Severity: Medium

Problem: The audit found multiple small name drifts (`What's New` semantics, `Set Up Workbench` vs `Set up a boss`, stale `⌘?` comment). These should not rely on human memory; command/menu/shortcut surfaces can be checked against a canonical manifest and docs snippets.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppModel.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/MenuBuilder.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchCore/WorkbenchGuide.swift`
- `/Users/arimendelow/Projects/ouro-workbench/README.md`
- `/Users/arimendelow/Projects/ouro-workbench/docs/guide.md`

Dependencies: A-005

Planner shape: Once the command/surface manifest exists, add CI checks that compare menus, command palette entries, shortcut guide rows, shell command reference rows, and docs excerpts.

## A-033: Make Shell Downstream Checks Close Completed Clone State

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Low

Problem: Shell downstream checks clone consumers under `.downstream-consumers`, and repo scans can accidentally traverse those clones unless every audit/tool remembers to exclude them. This is not a product bug, but it is a recurring agent-footgun.

Evidence:

- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/scripts/check-downstream-consumers.sh`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/.downstream-consumers`

Re-eval gate: Do after A-009/A-025 decide the downstream manifest shape. Options include moving clones to a temp/cache directory by default, adding stronger `.gitignore`/audit excludes, or having the checker clean by default unless `--keep-worktree` is passed.

## A-034: Split Release Policy Scripts Into Shared Tested Units

Status: queued

Route: planner-required

Severity: Medium

Problem: Ouro MD and Workbench both have large `release-policy.sh` scripts that mix release freshness, source scans, API fallback selftests, shell dependency watch checks, package guards, and artifact verification. A-007 covers the overall control deck; this item focuses on splitting release policy itself into reusable, tested units.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/scripts/release-policy.sh`
- `/Users/arimendelow/Projects/ouro-workbench/scripts/release-policy.sh`
- `/Users/arimendelow/Projects/ouro-md/.github/workflows/ci.yml`
- `/Users/arimendelow/Projects/ouro-workbench/.github/workflows/ci.yml`

Dependencies: A-007, A-028

Planner shape: Move common release-policy primitives into shell-owned or shared repo tooling, with app manifests supplying names, bundle IDs, artifacts, forbidden tokens, and release-channel expectations.

## A-035: Make "Direct Download" User Copy Channel-Aware

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Low

Problem: User-visible update metadata in both apps currently presents "Direct download" as a fixed channel label. That is correct now, but it should become channel-derived before signed/notarized/App Store work begins.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDShellAdapter.swift`
- `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchShellAdapter/WorkbenchShellPresentation.swift`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/Sources/OuroAppShellUI/ReleaseUpdateViewState.swift`

Dependencies: A-024

Re-eval gate: Do after A-024 creates a channel model. Then replace hardcoded labels with channel descriptors.

## A-036: Give Ouro MD AppKit/WebKit Code A Gradual Library-Extraction Plan

Status: queued

Route: planner-required

Severity: Medium

Problem: Ouro MD keeps AppKit/WebKit app code in the executable target and gates pure `OuroMDCore` at 100% coverage. That is a reasonable starting split, but more behavior is moving into AppKit/WebKit helpers, probes, and update coordination. A deliberate extraction plan would make future coverage and shell-boundary work less all-or-nothing.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/Package.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/AppModel.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/EditorWebView.swift`
- `/Users/arimendelow/Projects/ouro-md/Sources/OuroMD/OuroMDUpdateCoordinator.swift`
- `/Users/arimendelow/Projects/ouro-md/scripts/check-coverage.sh`

Planner shape: Identify candidates for a testable `OuroMDAppSupport` or `OuroMDEditorSupport` library without forcing WebKit/AppKit UI bodies into pure core. Start with command catalog, update presentation, file/folder state, and editor bridge policy.

## A-037: Decide How Shared Shell Should Treat In-App "What's New"

Status: superseded

Route: superseded

Severity: Low

Problem: This is a more specific version of A-012.

Evidence:

- A-012

Notes: Kept as a placeholder for traceability only; do not execute separately. A-012 is the canonical item.

## A-038: Add A Cross-Repo "Normative Docs" Index

Status: queued

Route: inch-worm-ready-after-reeval

Severity: Low

Problem: Each repo has a mix of normative docs, product docs, historical doing docs, and generated/probe documentation. Audits and future agents need a quick way to know which documents are current source of truth for architecture, release, testing, shell boundaries, and user-facing behavior.

Evidence:

- `/Users/arimendelow/Projects/ouro-md/README.md`
- `/Users/arimendelow/Projects/ouro-md/docs`
- `/Users/arimendelow/Projects/ouro-workbench/docs`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/README.md`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell/docs/shell-boundary.md`

Dependencies: A-010, A-027

Re-eval gate: Do after Workbench docs are refreshed and historical docs are archived/indexed. A simple `docs/INDEX.md` in each repo may be enough.
