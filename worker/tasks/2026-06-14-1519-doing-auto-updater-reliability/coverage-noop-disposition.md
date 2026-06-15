# Coverage No-op Disposition

This file is consumed by `check-changed-coverage.py`. Entries here are not
claims that coverage does not matter; they mark lines whose behavior sits on
external AppKit, process, network, or app-swap boundaries already exercised by
unit seams and E2E harnesses.

Allowed format:

`- path: all - reason`
`- path:start-end - reason`
`- path:line - reason`

## Entries

- Sources/OuroMD/AppDelegate.swift: all - AppKit lifecycle, alert, window, and responder-chain hooks; coordinator logic and undo routing are covered by unit seams and live E2E harnesses.
- Sources/OuroMD/CLI.swift:28-41 - `render(path:themeId:)` is a process-exiting CLI boundary; render behavior is exercised by `swift run ouro-md --renderprobe` and `swift run ouro-md --roundtrip sample.md`.
- Sources/OuroMD/ContentView.swift: all - SwiftUI preferences binding surface; underlying coordinator persistence and state transitions are unit-tested.
- Sources/OuroMD/DocumentWindowController.swift: all - AppKit window-controller chrome callbacks; behavior is exercised through app smoke/self-test and existing model/window tests where feasible.
- Sources/OuroMD/MenuBuilder.swift: all - AppKit menu assembly; selector-sensitive undo/redo changes are covered directly by `UndoRedoRoutingTests`.
- Sources/OuroMD/OuroMDRelease.swift: all - Release descriptor constants are asserted directly by `ReleaseUpdateTests`; Swift coverage does not emit a file record for this inlined constants-only file.
- Sources/OuroMD/OuroMDUpdateCoordinator.swift:68-85 - Default production closures intentionally touch GitHub networking, detached staging, app-swap helpers, NSApp termination, and wall-clock time; coordinator tests inject seams for these behaviors instead.
- Sources/OuroMD/OuroMDUpdateInstaller.swift: all - Real network/download, process runner, unzip, codesign, and app-swap boundaries are covered through injected seams and apply-script tests; real swap is deferred to release/live smoke.
