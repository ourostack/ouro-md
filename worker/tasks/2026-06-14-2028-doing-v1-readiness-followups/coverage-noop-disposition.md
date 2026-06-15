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

- Sources/OuroMD/AppDelegate.swift: all - AppKit lifecycle, menu validation, alert, window, and responder-chain hooks; the validation policy added in this follow-up is covered by `UndoRedoRoutingTests`, and shortcut behavior remains covered by `swift run ouro-md --undotest`.
- Sources/OuroMD/AppModel.swift: all - App/editor lifecycle and WKWebView bridge surface; the pure Markdown normalization added in this follow-up is covered by `MarkdownTidyTests`, and the save/roundtrip path is covered by `swift run ouro-md --roundtrip sample.md`.
- Sources/OuroMD/MarkdownRenderer.swift:175 - Private visitor image byte cap storage; image inlining, supported MIME branches, remote URLs, empty URLs, and unsupported extensions are covered by `MarkdownRendererTests`.
- Sources/OuroMD/MarkdownRenderer.swift:177-178 - `MarkupVisitor.defaultVisit` fallback for future swift-markdown node types; current supported block/inline nodes touched by this follow-up are covered directly by `MarkdownRendererTests`.
- Sources/OuroMD/OuroMDRelease.swift: all - Release descriptor constants are asserted directly by `ReleaseUpdateTests`; Swift coverage does not emit a file record for this inlined constants-only file.
