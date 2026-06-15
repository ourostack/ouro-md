# Unit 6b Zeno Review Resolution

Reviewer: Zeno (`019ec8aa-8cb2-7a12-89e9-f1551606fed2`)

## Findings

### P2: Manual install can outlive a canceled quit

Zeno found that manual install launched the app-swap helper before calling
`NSApp.terminate(nil)`. If the user canceled the unsaved-changes quit prompt,
the helper could remain waiting on the current app PID and apply later.

Resolution:

- `OuroMDUpdateCoordinator.installReleaseUpdate` now stages and records a
  pending manual update, then requests app termination.
- `AppDelegate.applicationWillTerminate` launches the manual apply/relaunch
  helper only after macOS has accepted termination.
- `AppDelegate.applicationShouldTerminate` calls
  `cancelPendingManualInstall()` when the user cancels the quit prompt.
- Added coordinator tests proving delayed manual apply and cancellation.

### P2: Installer coverage no-op was too broad

Zeno found `OuroMDUpdateInstaller.swift: all` waived coverage for a high-risk
file.

Resolution:

- Replaced the whole-file waiver with exact ranges for default live
  URLSession/process/app-swap boundaries.
- Regenerated `coverage.json`.
- Reran the changed-source coverage check successfully with
  `OuroMDUpdateInstaller.swift` no longer listed as a no-op file.

### P3: Update planner accepted plain HTTP asset URLs

Zeno found the updater accepted `http://` release asset URLs.

Resolution:

- `OuroMDUpdatePlanner` now accepts HTTPS asset URLs only.
- Added `testPlanRejectsPlainHTTPAssetURLs`.

## Verification

- `swift test --filter OuroMDUpdateTests`
- `swift test --filter OuroMDUpdateCoordinatorTests`
- `swift test`
- `swift test --enable-code-coverage`
- `python3 worker/tasks/2026-06-14-1519-doing-auto-updater-reliability/check-changed-coverage.py --base "$(git merge-base origin/main HEAD)" --coverage worker/tasks/2026-06-14-1519-doing-auto-updater-reliability/coverage.json`
- `swift run ouro-md --undotest`
- `swift run ouro-md --wraptest`
- `swift run ouro-md --renderprobe`
- `swift run ouro-md --roundtrip sample.md`
- `./scripts/package-release.sh`

Warning scan after the review fixes was empty.
