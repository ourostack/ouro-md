# Goal

Implement the release/update channel spine across Ouro MD, Ouro Workbench, and the shared native app shell so release lifecycle presentation, install capability declaration, channel copy, release metadata, and shared update policy primitives have one shell-owned shape.

## Upstream Work Items

- A-001 Release/update lifecycle presentation
- A-002 Install capability modes
- A-004 Update prompt chrome decision/primitive
- A-014 Narrow raw shell UI type traffic
- A-016 Shared update install/staging primitives
- A-024 Future signed/notarized/App Store channels
- A-028 Cross-repo release metadata model
- A-034 Shared release-policy units
- A-035 Channel-aware Direct download copy

## Scope

### In Scope

- Add shell-owned release/update presentation primitives that derive `ReleaseUpdateViewState` from common lifecycle inputs.
- Replace the coarse `supportsInstallAndRelaunch` contract with explicit install capability modes while preserving source compatibility where practical.
- Add channel descriptors on top of `DistributionChannel` so user-visible copy comes from channel metadata rather than hardcoded "Direct download" strings.
- Add a minimal shared release metadata model covering app name, version, build, repository, channel, highlights, and shell pin.
- Add shared update staging/install value primitives for direct-download apps where the existing consumers already share concepts: staged version, archive, app bundle, backup, and relaunch/apply intent.
- Add shared release-policy unit helpers for common app metadata and channel assertions.
- Update Ouro MD and Workbench adapters/contracts/tests to use the shell-owned capability/channel/presentation shape.
- Keep raw shell UI types at adapter boundaries where feasible; avoid broad edits in Workbench app views/view model.
- Validate shell tests and targeted consumer tests/builds for release/update surfaces.

### Out of Scope

- Control deck/declarative downstream check work from A-007/A-009/A-025/A-033.
- Workbench VM decomposition unrelated to release/update presentation.
- Ouro MD editor extraction or WebKit/AppKit decomposition.
- Implementing Developer ID signing, notarization, Sparkle, or App Store distribution.
- Replacing the app-specific archive download, file move, backup, and relaunch code wholesale.

## Completion Criteria

- Shell exposes explicit release install capability modes and validates them in contract tests.
- Shell exposes channel descriptors and `ReleaseUpdateViewState` helpers that render channel-aware copy for direct download, Developer ID direct, and App Store-style channels.
- Shell exposes a minimal `AppReleaseMetadata` model and policy/assertion helpers that consumer tests can use.
- Shell exposes shared staged update/apply value primitives used or type-aliased by at least one consumer.
- Ouro MD release/update adapter no longer hardcodes "Direct download" in update metadata and declares a review-only/manual prompt install capability that matches its runtime actions.
- Workbench release/update adapter no longer owns its own lifecycle-to-view-state mapping where the shell helper can represent it, and declares direct install/relaunch capability.
- Targeted shell and consumer tests cover current, available, checking, installing, ready, installed, failed/unavailable, missing-assets, and channel-copy cases.
- Branches are pushed, PRs are opened/merged where permissions and CI allow, and terminal validation evidence is recorded.

## Code Coverage Requirements

- Add or update tests before implementation for new shell release/update core and UI helpers.
- New shell logic should have branch coverage for capability modes, channel labels, lifecycle-state derivation, and metadata model validation.
- Consumer tests should prove declared capability matches runtime actions for Ouro MD and Workbench.

## Open Questions

- None blocking under autopilot. The chosen implementation is additive and compatibility-oriented: app-specific install runners stay app-owned, while shared lifecycle and policy primitives move shellward.

## Decisions Made

- Use `worker/release-update-channel-spine` in all three repos, with dedicated sibling worktrees.
- Keep the source-of-truth task docs in Ouro MD under `worker/tasks/` because the audit backlog and repo AGENTS workflow live there.
- Treat `OuroMDUpdatePrompt` as app-owned install policy prompt chrome for this tranche, but narrow the shell contract to `reviewThenInstall` rather than claiming direct shell install.
- Preserve direct-download as the current default channel, but add future channel descriptors now so A-024/A-035 do not bolt copy onto strings later.
- Do not move large install-file operations into shell in this pass; extract shared value types and verification policy first.

## Context / References

- `/Users/arimendelow/Projects/ouro-md` baseline `origin/main`
- `/Users/arimendelow/Projects/ouro-workbench` baseline `origin/main`
- `/Users/arimendelow/Projects/ouro-native-apple-app-shell` baseline `origin/main`
- Source backlog on Ouro MD PR #80 branch `origin/worker/shared-shell-systems-audit`
- Shell files: `Sources/OuroAppShellCore/AppIdentity.swift`, `Sources/OuroAppShellCore/AppUpdate.swift`, `Sources/OuroAppShellUI/ReleaseUpdateViewState.swift`, `Sources/OuroAppShellContract/OuroAppShellContract.swift`
- Ouro MD files: `Sources/OuroMD/OuroMDShellContract.swift`, `Sources/OuroMD/OuroMDShellAdapter.swift`, `Sources/OuroMD/OuroMDUpdateCoordinator.swift`
- Workbench files: `Sources/OuroWorkbenchShellAdapter/WorkbenchShellContract.swift`, `Sources/OuroWorkbenchShellAdapter/WorkbenchShellPresentation.swift`, `Sources/OuroWorkbenchAppViews/WorkbenchViewModel.swift`

## Notes

- The installed Work Suite planner/doer skills are the active source because `subagents/work-planner.md` and `subagents/work-doer.md` are absent from this repo and from the audit branch.
- Desk MCP is available; Desk git sync is blocked by unrelated unstaged Desk changes in `spoonjoy/native-recipe-spoon-api-v1/task.md`.
- Host: `ouroboros-host` / user: `arimendelow` / cwd: `/Users/arimendelow/Projects/ouro-md` / OS: `Darwin` / probed: 2026-06-29 21:59 America/Los_Angeles.

## Progress Log

- 2026-06-29 21:59 Created planning doc from source audit backlog and initial code read.
