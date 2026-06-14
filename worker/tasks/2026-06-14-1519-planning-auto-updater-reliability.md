# Planning: Ouro MD Auto-Updater And Reliability Hardening

**Status**: NEEDS_REVIEW
**Created**: 2026-06-14 15:21

## Goal
Add the in-app auto-updater and use the full-system audit to harden the release, shortcut, warning, and documentation surfaces that most affect day-to-day trust in Ouro MD.

## Upstream Work Items
- A-001 - Add in-app auto-updater
- A-002 - Bulletproof undo/redo shortcuts and stack behavior
- A-003 - Centralize and correct version/release truth
- A-004 - Remove Swift test warnings
- A-005 - Keep updater state out of AppModel god-object growth
- A-007 - Refresh README after pretty URL and updater work

**DO NOT include time estimates (hours/days) - planning should focus on scope and criteria, not duration.**

## Scope

### In Scope
- Add native in-app release checking for `ourostack/ouro-md` GitHub releases.
- Add pure, unit-tested release snapshot, asset planning, manifest decoding, semantic version comparison, and archive verification logic.
- Add an updater installer/stager adapted from Workbench for `Ouro MD.app` and bundle id `org.ourostack.ouro-md`, including sha256, byte count, bundle id, version, extracted app identity, and codesign verification before any swap.
- Add a safe user-triggered update path, such as `Ouro MD -> Check for Updates...` or an equivalent native menu/prompt, that can install and relaunch only after successful staging.
- Add throttled launch-time update checking and background staging. Default behavior: enabled by default, persisted opt-out, check at most once every 3600 seconds, silently stage a verified update when one exists, expose a visible update prompt/menu action once staged, and apply the staged update on normal app quit without surprise relaunch. Manual `Check for Updates...` may install and relaunch immediately after confirmation.
- Keep updater logic in focused new files and only add thin lifecycle/menu hooks to existing app coordinator code.
- Expand undo/redo verification beyond the existing single-edit `--undotest`: multi-step undo/redo, redo invalidation after a new edit, empty-stack no-op behavior, Vditor mode rebuild behavior, native menu selector forwarding to the editor when no native text field owns focus, and native text-field undo/redo preservation when a native `NSTextView` owns focus. If an AppKit focus case cannot be automated reliably in this repo, record an explicit no-op disposition in the doing doc with the attempted harness and the remaining manual smoke command.
- Fix version truth drift so CLI/docs/release metadata agree on the current version and install URL.
- Remove existing Swift test warnings from weak `MockBridge` assignments.
- Update README and installer script comments only where needed to match current release/update behavior and the live `https://ouro.bot/ouro-md-install.sh` installer route.
- Preserve existing distribution behavior: release zip plus manifest, one-line installer, ad-hoc signing until Developer ID signing exists.

### Out of Scope
- Developer ID signing and notarization.
- Payment, licensing, account, or entitlement systems.
- Replacing Vditor or redesigning the editor surface.
- Deep `AppModel.swift` decomposition beyond keeping new updater code out of it.
- Folder-scan performance rewrite from A-006; defer until after the updater and shortcut reliability tranche lands.
- Changing markdown rendering semantics unrelated to update/install or undo/redo reliability.

## Completion Criteria
- [ ] In-app update check can detect current, update-available, unavailable, missing asset, and malformed manifest cases.
- [ ] Update installation refuses bad sha256, byte count, archive name, bundle id, non-newer version, missing app bundle, and failed codesign checks.
- [ ] A safe manual update UI/action exists and does not swap the running app unless staging and verification succeeded.
- [ ] Launch-time update checking is enabled by default, has a persisted opt-out, is throttled to 3600 seconds by default, does not block document editing startup, stages verified updates in the background, and applies a staged update only on normal app quit or explicit manual install/relaunch.
- [ ] Updater implementation keeps pure logic and installer/stager code outside `AppModel.swift`; existing files get only focused lifecycle/menu hooks.
- [ ] Undo/redo harness coverage proves multi-step undo/redo, redo invalidation after a new edit, empty-stack no-op safety, behavior across Vditor mode rebuilds, native menu selector forwarding, and native text-field focus preservation; any non-automated AppKit focus proof has an explicit no-op disposition plus a manual smoke command.
- [ ] `swift run ouro-md --undotest` passes.
- [ ] `swift run ouro-md --wraptest` passes.
- [ ] `swift run ouro-md --renderprobe` passes.
- [ ] Release/version truth is consistent across CLI, bundle metadata, README, and updater configuration.
- [ ] `swift test` passes and emits no Swift compiler warnings for repo source or test files.
- [ ] `swift test --enable-code-coverage` runs successfully; `xcrun llvm-cov export` output is saved to the doing artifacts as `coverage.json`; a deterministic coverage check over changed/new non-harness Swift files reports 100% line coverage or the doing doc records an explicit no-op disposition for code that is not meaningfully coverable because it is an external-process/AppKit boundary already exercised by an E2E harness.
- [ ] All verification commands pass: `swift test`, `swift test --enable-code-coverage`, the changed/new-file coverage check, `swift run ouro-md --undotest`, `swift run ouro-md --wraptest`, `swift run ouro-md --renderprobe`, `swift run ouro-md --roundtrip sample.md`, `./scripts/package-release.sh`, and the safe live installer smoke `OURO_MD_INSTALL_DIR="$(mktemp -d)" OURO_MD_NO_OPEN=1 curl -fsSL https://ouro.bot/ouro-md-install.sh | bash` after the release is published.
- [ ] No warnings from Swift compilation or release packaging commands.

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch, try/catch)
- All error paths tested
- Edge cases: null, empty, boundary values

## Open Questions
- [x] Launch-time updater workflow: use default-on throttled auto-check every 3600 seconds + persisted opt-out + background stage + apply-on-quit; manual check can install and relaunch immediately.
- [x] Undo/redo automation boundary: automate core stack and native routing cases where possible; any AppKit focus case that proves non-deterministic must be recorded as an explicit no-op disposition with a manual smoke command rather than left vague.
- [x] Coverage/warning boundary: require `swift test`, `swift test --enable-code-coverage`, `xcrun llvm-cov export` artifact, deterministic changed/new-file coverage check, and no Swift compiler warnings in repo source/test output.

## Decisions Made
- Use branch `worker/ouro-md-auto-updater`; `worker` is the agent path segment and task docs live under `worker/tasks/`.
- Use Workbench's updater architecture as the source pattern, but rename/adapt types for Ouro MD instead of importing Workbench code directly.
- Use current release artifacts as the distribution contract: `Ouro-MD-<version>.zip` plus `Ouro-MD-<version>.manifest.json`.
- Keep Developer ID signing/notarization out of this code tranche. The updater should still verify the existing ad-hoc signed bundle with `codesign --verify --deep --strict`, matching the current release reality.
- Treat undo/redo as a first-class reliability target, not a minor regression test.
- Defer folder scanner performance item A-006 until after the updater lands; it is real but not on the critical trust path.
- Launch-time updater behavior mirrors Workbench's safest user experience: background staging plus install-on-quit, not an unexpected mid-session relaunch.
- Documentation truth includes installer comments as well as README copy, because the live one-line script is itself user-facing.
- Live installer smoke is constrained to a temporary install directory with `OURO_MD_NO_OPEN=1` so verification proves the published pretty URL works without mutating `/Applications` or launching the app.

## Context / References
- Audit report: `worker/tasks/2026-06-14-1519-audit-ouro-md/audit-report.md`
- Audit backlog: `worker/tasks/2026-06-14-1519-audit-ouro-md/audit-backlog.md`
- Workbench release checking pattern: `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchCore/ReleaseUpdate.swift`
- Workbench update planning/verification pattern: `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchCore/WorkbenchUpdate.swift`
- Workbench installer/stager pattern: `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchApp/WorkbenchUpdateInstaller.swift`
- Workbench app integration reference: `/Users/arimendelow/Projects/ouro-workbench/Sources/OuroWorkbenchApp/OuroWorkbenchApp.swift` around `checkForUpdatesAndPromptInstall`, `installReleaseUpdate`, and `runAutoUpdateCheckIfDue`.
- Ouro MD release packaging: `scripts/package-release.sh`
- Ouro MD installer: `web/ouro-md-install.sh`
- Ouro MD app bundle version source: `make-app.sh`
- Current CLI version drift: `Sources/OuroMD/CLI.swift`
- Current README version/install drift: `README.md`
- Undo/redo routing: `Sources/OuroMD/MenuBuilder.swift`, `Sources/OuroMD/AppDelegate.swift`, `Sources/OuroMD/AppModel.swift`, `Sources/OuroMD/EditorWebView.swift`, `Sources/OuroMD/web/bridge.js`, `Sources/OuroMD/UndoTest.swift`
- Current verification evidence from planning pass: `swift test` passed 42 tests but emitted weak bridge warnings; `swift run ouro-md --undotest` passed; `swift run ouro-md --wraptest` passed 6/6; `swift run ouro-md --renderprobe` passed 10/10; latest GitHub release is `v0.9.0` with zip and manifest assets.

## Notes
The delicate part is not release-feed parsing; it is swapping the running app safely. Keep download/stage/verify pure or side-effect-contained, and treat the helper-process swap/relaunch path as the highest-risk implementation unit.

## Progress Log
- 2026-06-14 15:21 Created
- 2026-06-14 15:22 Tinfoil pass: verified referenced files, release assets, and undo/redo route; no scope changes needed
- 2026-06-14 15:24 Reviewer Round 1 findings addressed: made launch-time workflow explicit, tightened undo/redo evidence, made verification commands measurable, and included installer comments in documentation scope
- 2026-06-14 15:28 Reviewer Round 2 findings addressed: specified 3600-second/default-on updater policy, exact coverage artifact/check shape, and safe live installer smoke command
