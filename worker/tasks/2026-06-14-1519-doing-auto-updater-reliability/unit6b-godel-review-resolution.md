# Unit 6b Godel Review Resolution

Reviewer: Godel (`019ec8b3-ca6c-7332-9f39-dbb79289961b`)

## Finding

### P1: Manual install can still proceed after a save-cancel/save-failure quit path

Godel found that the `Save All` termination path ignored `performSave(false)`.
That meant a user could start manual install, choose `Save All`, cancel an
untitled save panel or hit a save failure, and still leave the manual update
armed.

## Resolution

- Added `TerminationSaveCoordinator` as a focused, testable main-actor save
  barrier.
- `TerminationSaveCoordinator.saveAll` replies `false` and invokes `onCancel`
  on any failed save completion.
- The timeout safety net now cancels termination instead of forcing quit if a
  save completion is lost.
- `AppDelegate.applicationShouldTerminate` uses `onCancel` to disarm pending
  manual installs before replying `false`.
- Added `TerminationSaveCoordinatorTests` covering:
  - immediate success with no dirty documents,
  - successful quit only after all saves complete,
  - save failure/cancel replies false and cancels once,
  - default cancel handler safety,
  - timeout replies false rather than forcing quit.

## Verification

- `swift test --filter TerminationSaveCoordinatorTests`
- `swift test --filter OuroMDUpdateCoordinatorTests`
- `swift test`
- `swift test --enable-code-coverage`
- `xcrun llvm-cov show ... Sources/OuroMD/TerminationSaveCoordinator.swift`
- changed-source coverage check
- `swift run ouro-md --undotest`
- `swift run ouro-md --wraptest`
- `swift run ouro-md --renderprobe`
- `swift run ouro-md --roundtrip sample.md`
- `./scripts/package-release.sh`

Warning scan after the Godel fix was empty.
