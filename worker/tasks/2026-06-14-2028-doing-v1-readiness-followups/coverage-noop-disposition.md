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

- Sources/OuroMD/AppDelegate.swift:1-323 - AppKit lifecycle, alert, window, update, help, and responder-chain hooks; menu validation is intentionally outside this range and covered by `UndoRedoRoutingTests`.
- Sources/OuroMD/AppDelegate.swift:345-346 - Manual update install enablement depends on the live update coordinator prompt/install state; coordinator state transitions are covered by `OuroMDUpdateCoordinatorTests`, and AppKit menu routing is covered by `UndoRedoRoutingTests`.
- Sources/OuroMD/AppDelegate.swift:389-999 - End of AppKit delegate type; menu validation is intentionally outside this range and covered by `UndoRedoRoutingTests`.
- Sources/OuroMD/AppModel.swift:1-319 - Pre-existing app/editor lifecycle and WKWebView bridge surface; new Markdown tidy logic moved to `MarkdownTidy.swift`, and the changed save path is intentionally outside this range.
- Sources/OuroMD/AppModel.swift:327-332 - Untitled Save panel handoff is an AppKit UI boundary; titled clean/dirty save behavior is covered by `AppModelReloadTests`.
- Sources/OuroMD/AppModel.swift:360-999 - Pre-existing AppKit error presentation, file watcher, export, sidebar, search, format, and close-confirmation surface; changed save success/no-op paths are intentionally outside this range.
- Sources/OuroMD/MarkdownRenderer.swift:251 - Private visitor image byte cap storage; image inlining, supported MIME branches, remote URLs, empty URLs, and unsupported extensions are covered by `MarkdownRendererTests`.
- Sources/OuroMD/MarkdownRenderer.swift:253-254 - `MarkupVisitor.defaultVisit` fallback for future swift-markdown node types; current supported block/inline nodes touched by this follow-up are covered directly by `MarkdownRendererTests`.
- Sources/OuroMD/OuroMDRelease.swift: all - Release descriptor constants are asserted directly by `ReleaseUpdateTests`; Swift coverage does not emit a file record for this inlined constants-only file.
