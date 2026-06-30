# Holistic Shared Shell Systems Audit

Date: 2026-06-29 21:35 America/Los_Angeles

Scope: Ouro MD, Ouro Workbench, and ouro-native-apple-app-shell after the shared shell adoption work. This is a systems audit of the split: ownership, dependency direction, control-plane scripts, release/update surfaces, and the next places shared behavior is likely to leak back into app code. It is not a deep product bug hunt for either app.

## Repos Audited

| Repo | Local path | Baseline |
| --- | --- | --- |
| Ouro MD | `/Users/arimendelow/Projects/ouro-md` | `97681aa` / `v0.9.61` |
| Ouro Workbench | `/Users/arimendelow/Projects/ouro-workbench` | `3c9ede6` / `v0.1.232` |
| Shell | `/Users/arimendelow/Projects/ouro-native-apple-app-shell` | `38a98a2` |

The shell live-main canary had already passed against both downstream consumers, and both consumer shell pins matched their latest package-relevant shell state at the time of audit.

## Overall Read

The split is directionally strong. The shell is not cosmetic: it owns typed contract models, shared release/update primitives, common UI controls, AppKit utility-window presentation, consumer test helpers, shell boundary scanning, and downstream pinned/live validation. Both native apps have explicit shell adapters and CI/preflight gates.

The main risk has moved. The question is no longer "did the apps adopt the shell?" The question is "will the third Ouro native app have an obvious, low-friction path to put shared behavior in the shell instead of rebuilding it locally?" Today that path exists, but it is still partly enforced by convention, broad allowlists, and duplicated scripts. Those are fine for the second app. They get expensive for the third.

## Healthy Patterns To Preserve

- The shell package is modular: `OuroAppShellCore`, `OuroAppShellContract`, `OuroAppShellConsumerTesting`, `OuroAppShellAppKit`, `OuroAppShellUI`, and `OuroAppShellUISurfaceProbe` keep contracts, shared logic, presentation, and visual probes separate.
- Consumer adapters are real control points:
  - Ouro MD: `Sources/OuroMD/OuroMDShellAdapter.swift` and `Sources/OuroMD/OuroMDShellContract.swift`.
  - Workbench: `Sources/OuroWorkbenchShellAdapter/WorkbenchShellContract.swift` and `Sources/OuroWorkbenchShellAdapter/WorkbenchShellPresentation.swift`.
- CI has the right bones: consumer shell dependency checks, shell boundary checks, downstream pinned smokes, and live-main canaries.
- The Package.resolved freshness policy is thoughtful: it checks the latest package-relevant shell commit rather than forcing consumer churn for shell-only CI/docs edits.
- Workbench already has strong shortcut/a11y catalog tests, which prevented a false positive during this audit: `⌘/` is intentional and tested, even though one nearby comment still says `⌘?`.

## System Map

### Release/Update

The shell owns release policy types, GitHub release snapshots, install planning, manifest verification, update view states, and shared update controls. Consumers still own runtime lifecycle mapping, install staging/apply scripts, telemetry, and some prompt presentation.

This is the hottest shared-boundary area. Both apps now use shell primitives, but each still maps its own coordinator/view-model state into `ReleaseUpdateViewState` and `ReleaseUpdateActions`. Workbench has a distinct presenter shape; Ouro MD has a coordinator adapter plus direct `NSAlert` prompts.

### Command/Shortcut/About Surfaces

The shell has shared about and command-reference UI. Apps provide copy, command rows, and domain actions. Workbench has a better centralized shortcut catalog than Ouro MD, while Ouro MD still spreads command/menu definitions across menu builder, command palette, dispatch, and shell adapter code.

### Boundary/Control Plane

The shell owns a boundary scanner and downstream scripts. Consumers call wrapper scripts from preflight/CI. This is the right model, but the current enforcement still has broad adapter escape hatches and duplicated consumer-local scripts for shell dependency freshness and release policy.

### Scale Hotspots

Source-only line counts show the largest future split risks:

| File | Lines | Why it matters |
| --- | ---: | --- |
| Workbench `WorkbenchViewModel.swift` | 11,252 | Shell-facing state, command palette, release update actions, and app workflow logic share a very large home. |
| Workbench `WorkbenchViews.swift` | 10,828 | Shell-adjacent UI can hide inside general UI churn. |
| Ouro MD `AppModel.swift` | 1,461 | Editor command/control state is still broad and central. |
| Ouro MD `web/bridge.js` | 1,249 | Critical editor bridge behavior is concentrated in one script. |
| Shell `scripts/shell-doctor.sh` | 1,161 | Shared enforcement logic is large and partly embedded. |
| Shell `scripts/scaffold-consumer-adoption.sh` | 619 | New-app adoption is script-driven but not yet declarative enough. |
| Shell `scripts/check-downstream-consumers.sh` | 401 | Consumer metadata is partly manifest-driven and partly hardcoded. |

## Reviewer Gates

Three read-only reviewer slices were fanned out and integrated:

- Ouro MD reviewer: confirmed shell adoption is narrow and CI-enforced, but flagged direct update prompts, scattered command/control definitions, and `What's New` semantics.
- Workbench reviewer: confirmed dedicated adapter target and passing boundary/dependency checks, but flagged direct shell UI type traffic in app views/view model, giant central files, and doc/comment naming drift.
- Shell reviewer: confirmed typed contract/downstream validation strength, but flagged release update lifecycle drift, install capability ambiguity, broad adapter exemptions, branded Workbench APIs in shared core, and hardcoded downstream control deck pieces.

## Assessment

I feel good about the split as a foundation. I would not roll it back or pause adoption. I would, however, treat the next phase as "make the shell path the easiest path" rather than "keep adding guardrails around app code."

The next roadmap should start with release/update lifecycle unification and adapter-boundary tightening, because that is where all three repos already show pressure. After that, the Workbench view/view-model decomposition and shell control-deck consolidation become the structural work that makes future shared surfaces cheaper.

## Validation Performed

- Read AGENTS/README/architecture docs in all three repos.
- Compared package, adapter, contract, boundary, preflight, release, and downstream scripts.
- Ran static searches for shell UI type traffic, release update state/action mapping, stale shortcut/onboarding copy, direct `NSAlert` shell-boundary usage, and Workbench-branded shell core APIs.
- Integrated three independent read-only reviewer slices.

I did not run full Swift test suites for all repos because this audit did not modify product code. The Workbench reviewer did run `scripts/check-shell-boundary.sh --selftest`, `scripts/check-shell-boundary.sh`, and `scripts/check-shell-dependency.sh` for the Workbench slice.

