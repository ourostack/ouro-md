# Ouro MD AppKit/WebKit Extraction Plan

## Purpose

Ouro MD currently keeps its AppKit/WebKit application shell in the `OuroMD`
executable target while enforcing 100% line and region coverage for the pure
`OuroMDCore` target. That split is still a good boundary: the core renderer and
release constants stay pure, while the executable target owns windows, WebKit,
menus, file coordination, update prompts, and headless shipped diagnostics.

The next extraction should not be a broad move of UI bodies into core. The goal
is to create one or two testable support libraries that hold app-specific policy
and state machines without forcing `NSViewRepresentable`, `WKWebView`, or
`NSApplication` behavior into pure core.

## Current Signals

| Surface | Current home | Signal | Existing tests |
| --- | --- | ---: | --- |
| Document/editor state and commands | `Sources/OuroMD/AppModel.swift` | 1,461 lines | `AppModelReloadTests`, `AppModelDeletionTests`, `CommandPaletteTests` |
| WebKit bridge host | `Sources/OuroMD/EditorWebView.swift` | 336 lines | `EditorWebViewTests`, headless harnesses |
| Update lifecycle coordinator | `Sources/OuroMD/OuroMDUpdateCoordinator.swift` | 638 lines | `OuroMDUpdateCoordinatorTests`, `TerminationSaveCoordinatorTests` |
| Editor JavaScript bridge | `Sources/OuroMD/web/bridge.js` | 1,249 lines | headless harnesses in `scripts/run-native-scenarios.sh` |
| Folder display and scanning | `Sources/OuroMD/FolderDisplay.swift`, `Sources/OuroMD/FolderBrowser.swift` | already partly separated | `FolderDisplayTests`, folder/search tests in `AppModelReloadTests` |
| Command/menu/reference catalog | `Sources/OuroMD/AppModel.swift`, `Sources/OuroMD/MenuBuilder.swift`, `Sources/OuroMD/OuroMDShellAdapter.swift` | scattered public surface | `CommandPaletteTests`, `OuroMDShellContractTests` |

## Candidate Library Shape

Start with `OuroMDAppSupport` rather than moving directly to an
`OuroMDEditorSupport` WebKit library.

`OuroMDAppSupport` should be allowed to import `Foundation`, `Combine`, and
`OuroMDCore`. It should not import `AppKit`, `SwiftUI`, or `WebKit` for the first
pass. If a later extraction needs AppKit-only types, create a separate
`OuroMDAppKitSupport` target instead of diluting the pure support target.

Likely first contents:

- Command catalog models and filtering from `CommandPaletteItem` and
  `CommandPaletteCatalog`.
- Folder display naming/duplicate/search result policy that is currently split
  between `FolderDisplay`, `FolderBrowser`, and `AppModel`.
- Update presentation state mapping that is app-specific but testable without
  `NSAlert` or `NSApplication`.
- Editor bridge command names and validation policy, not the `WKWebView`
  coordinator itself.

Possible later `OuroMDEditorSupport` contents:

- JavaScript command names and payload schemas shared by Swift and `bridge.js`.
- Table/code wrapping policy inputs and outputs once the Swift side can test them
  without spinning up WebKit.
- A manifest describing bridge capabilities exercised by the headless harnesses.

## Recommended Order

1. **Command catalog extraction.**
   Move `CommandPaletteItem` and `CommandPaletteCatalog` out of `AppModel.swift`
   into `OuroMDAppSupport`. Add tests that compare command IDs used by
   `MenuBuilder`, command palette filtering, and shell command-reference rows.

2. **Folder display/search policy extraction.**
   Keep file watching and async scanning in the executable target, but move
   duplicate-name display, result trimming, query normalization, and visible error
   policy into support types. Extend `FolderDisplayTests` and focused AppModel
   tests before moving code.

3. **Update presentation mapping extraction.**
   Leave install staging/apply in `OuroMDUpdateInstaller` and lifecycle ownership
   in `OuroMDUpdateCoordinator`, but extract prompt/progress label selection into
   support structs. This keeps A-001/A-002/A-016 future shell work easier without
   preemptively changing shell APIs in this lane.

4. **Editor bridge policy extraction.**
   Extract Swift-side command names and capability declarations first. Do not move
   `EditorWebView.Coordinator` or `bridge.js` until the policy manifest can prove
   the same commands are exercised by tests and headless harnesses.

5. **Evaluate an AppKit/WebKit support target only after the pure support target
   is stable.**
   If repeated code remains trapped by `NSView`, `WKWebView`, or `NSAlert` types,
   introduce an AppKit-specific support target with its own tests. Do not broaden
   `OuroMDCore` to carry AppKit or WebKit.

## Test And CI Requirements

Every extraction PR should satisfy:

- Tests are written before moving behavior.
- New pure support code has 100% line and region coverage.
- `scripts/check-coverage.sh` still gates `OuroMDCore`; if a new pure support
  target is added, extend the coverage script to gate that target too.
- `swift build` and focused Swift tests pass.
- `scripts/run-native-scenarios.sh` passes when bridge/editor behavior moves.
- `scripts/check-shipped-harness-policy.sh` remains green when harness flags or
  coverage scripts change.
- `scripts/check-vditor-vendor.sh` remains green when editor web assets are
  touched.

## Explicit Non-Goals

- Do not move `EditorWebView` or `WKWebView` coordinator code into `OuroMDCore`.
- Do not move generated/minified Vditor assets into Swift targets.
- Do not decompose `Sources/OuroMD/web/bridge.js` just because it is large.
- Do not move shell-owned chrome or release/update primitives into Ouro MD
  support libraries; use `ouro-native-apple-app-shell` for reusable native Ouro
  app chrome.
- Do not change product behavior as part of extraction setup. Behavior moves need
  red/green tests and one visible user-facing reason or maintenance win.

## A-013 Radar Disposition

A-013 remains deferred. `AppModel.swift` and `web/bridge.js` are real
maintainability signals, but this plan intentionally does not authorize a broad
editor-core decomposition. Revisit A-013 after at least one A-036 extraction PR
lands and proves:

- which policy/state surface moved cleanly,
- which tests caught behavior drift,
- which AppKit/WebKit dependencies blocked further movement, and
- whether the next split belongs in `OuroMDAppSupport`, `OuroMDEditorSupport`,
  the executable target, or the shared shell.

Until that evidence exists, treat A-013 as radar only.
