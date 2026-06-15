# Ouro MD Full System Audit

**Status**: NEEDS_REVIEW
**Created**: 2026-06-14 15:19
**Branch**: worker/ouro-md-auto-updater

## System Summary

Ouro MD is a compact native macOS Markdown editor: a SwiftUI/AppKit shell around
a WKWebView-hosted Vditor editor. The repo is small once vendored Vditor assets
are treated as third-party code: 24 source files, 7 test files, and roughly 5.4k
non-vendor lines across Swift, JavaScript, and shell scripts.

Major runtime surfaces:
- Native app lifecycle, windows, menus, session restore: `Sources/OuroMD/AppDelegate.swift`
- Document state, save/reload/folder/search orchestration: `Sources/OuroMD/AppModel.swift`
- WKWebView bridge: `Sources/OuroMD/EditorWebView.swift`
- Editor behavior and Vditor integration: `Sources/OuroMD/web/bridge.js`
- Folder/file watchers and search: `Sources/OuroMD/FileWatcher.swift`, `Sources/OuroMD/FolderBrowser.swift`, `Sources/OuroMD/ContentSearcher.swift`
- Release packaging and installer: `scripts/package-release.sh`, `web/ouro-md-install.sh`, `make-app.sh`

Current verification evidence from this pass:
- `swift test`: 42 tests passed, with Swift warnings in `AppModelReloadTests.swift` caused by assigning temporary `MockBridge()` instances into a weak `bridge` property.
- `swift run ouro-md --undotest`: passed. Real edit was undone and redone through the Vditor undo stack.
- `swift run ouro-md --wraptest`: passed 6/6.
- `swift run ouro-md --renderprobe`: passed 10/10.
- `swift run ouro-md --roundtrip sample.md`: completed successfully.
- `gh release view --repo ourostack/ouro-md`: latest published release is `v0.9.0` with `Ouro-MD-0.9.0.zip` and `Ouro-MD-0.9.0.manifest.json`.

## Architecture Notes

The architecture is appropriate for the product: native shell for Mac behavior,
web editor for Markdown IR/WYSIWYG rendering, and pure Swift helpers for file
system/search/render logic. The key risk is not the choice of architecture, but
the concentration of coordination logic in `AppModel.swift` and the thinness of
end-to-end coverage around keyboard shortcuts, updater state, and release truth.

Largest non-vendor files:
- `Sources/OuroMD/AppModel.swift`: 846 lines
- `Sources/OuroMD/web/bridge.js`: 559 lines
- `Sources/OuroMD/Sidebar.swift`: 421 lines
- `Sources/OuroMD/MenuBuilder.swift`: 337 lines
- `Sources/OuroMD/Themes.swift`: 324 lines
- `Sources/OuroMD/DocumentWindowController.swift`: 283 lines
- `Sources/OuroMD/AppDelegate.swift`: 280 lines

`AppModel.swift` is the main growth pressure. It currently handles document IO,
autosave, reload conflict UX, folder scanning, folder search, theme/mode state,
find/replace, export, format commands, and teardown. This is still navigable,
but new updater state should not be added there casually unless it is split into
a small coordinator type.

## Flow Notes

Document open/save:
- AppDelegate or window command calls `AppModel.open(url:)`.
- AppModel reads text using UTF-8 plus fallback encodings, pushes Markdown to
  `EditorBridge`, starts a `FileWatcher`, and updates recent documents.
- Save pulls Markdown from the bridge, tidies Vditor roundtrip artifacts, writes
  atomically to the symlink-resolved target, marks saved in JS, and re-arms the
  watcher.

External reload:
- `FileWatcher` coalesces file events and re-arms across atomic replace.
- `AppModel.handleExternalChange()` ignores self-save echoes by comparing
  against `lastLoadedContent`.
- Clean buffers reload silently through `bridge.reloadMarkdown`; dirty buffers
  get a modal conflict prompt.

Undo/redo:
- `MenuBuilder` binds Edit -> Undo/Redo to `AppDelegate.undoEdit(_:)` and
  `redoEdit(_:)`.
- AppDelegate first lets focused native `NSTextView` controls consume undo/redo,
  then falls back to `AppModel.undo()` / `redo()`.
- AppModel forwards to the bridge.
- `EditorWebView` evaluates `window.ouro.undo()` / `redo()`.
- `bridge.js` calls `vditor.vditor.undo.undo(vditor.vditor)` and redo equivalent,
  then refreshes `state.value`, dirty state, and counts.
- `UndoTest.swift` verifies one real edit through this path.

Release/update:
- `make-app.sh` builds `OuroMD.app` with bundle id `org.ourostack.ouro-md` and
  version `0.9.0`.
- `scripts/package-release.sh` stages that as `Ouro MD.app`, zips it, and writes
  a manifest with `appName`, `bundleIdentifier`, `version`, `build`, `archive`,
  `sha256`, `bytes`, and `createdAt`.
- `web/ouro-md-install.sh` downloads the newest release asset pair, verifies
  sha256, extracts, installs, clears quarantine, and opens the app.
- In-app updater code is not present yet. Workbench has reusable patterns in
  `ReleaseUpdate.swift`, `WorkbenchUpdate.swift`, and `WorkbenchUpdateInstaller.swift`.

## Control Deck

Configuration and external state:
- `Package.swift`: SwiftPM product and dependency.
- `make-app.sh`: bundle identity and version source for app packaging.
- `scripts/package-release.sh`: manifest schema and release artifact names.
- `web/ouro-md-install.sh`: install defaults and environment overrides.
- UserDefaults keys under `ouro.*`: theme, sidebar, autosave, auto-pair, zoom,
  session docs/folder.
- `~/Library/Application Support/ouro-md/Themes/`: custom theme directory.
- GitHub Releases: distribution/update source of truth.

Control-deck assessment: workable, but version truth is split. `make-app.sh`
claims `0.9.0`, release metadata is `v0.9.0`, while README status and CLI
`--version` still claim `0.1.0`. The updater should centralize version/bundle
identity behind a Swift release descriptor and the docs/CLI should derive from
the same truth or be deliberately synchronized.

## Findings

### High: In-app updater is missing despite release assets being ready

Ouro MD now has signed-by-ad-hoc release archives, manifests, a one-line
installer, and a live pretty URL, but no native update check/install path.
Users must re-run the installer. This is the biggest remaining reliability and
distribution gap.

Evidence:
- `web/ouro-md-install.sh` already verifies sha256 and installs latest release.
- Latest release `v0.9.0` has `.zip` and `.manifest.json` assets.
- No `ReleaseUpdate`, `OuroMDUpdate`, or update UI/actions exist in `Sources/OuroMD`.
- Workbench has the target pattern in `ReleaseUpdate.swift`,
  `WorkbenchUpdate.swift`, and `WorkbenchUpdateInstaller.swift`.

Recommendation: add pure release checking/planning/verification types, an
installer/stager adapted for `Ouro MD.app` and `org.ourostack.ouro-md`, menu or
preference UI for update checks, and launch-time throttled staging. Keep swap
and relaunch isolated and heavily verified.

### High: Undo/redo is fixed but not yet bulletproof

The current undo/redo path works and `--undotest` passes. For a text editor,
coverage should be broader than one edit. The fragile surfaces are native menu
shortcut routing, focus routing between editor and native text controls,
multi-step undo/redo, redo invalidation after a new edit, mode rebuilds, and
external reload interactions.

Evidence:
- `MenuBuilder.swift` binds Undo/Redo to `AppDelegate`.
- `AppDelegate.swift` routes native text view undo first, then editor undo.
- `bridge.js` directly calls Vditor internals.
- `UndoTest.swift` verifies a single edit, undo, redo.

Recommendation: expand `UndoTest.swift` or add a second harness covering
multi-step edits, redo invalidation, no-op behavior on empty stack, native menu
selectors, and editor focus after mode/theme changes where practical.

### Medium: Version/documentation drift

Release and bundle version are `0.9.0`, but user-facing version text still says
`0.1.0`.

Evidence:
- `make-app.sh:15` has `VERSION="0.9.0"`.
- GitHub release is `v0.9.0`.
- `Sources/OuroMD/CLI.swift:5` has `static let version = "0.1.0"`.
- `README.md:9` says status `v0.1.0`.
- `README.md:43` still uses the raw GitHub installer URL even though the pretty
  URL is now live.

Recommendation: create a single Swift release descriptor for version and bundle
identity, update CLI/docs, and prefer `https://ouro.bot/ouro-md-install.sh` in
install docs.

### Medium: Test suite passes with warnings

`swift test` passes, but warnings show temporary mock bridge instances are
immediately deallocated because `AppModel.bridge` is weak. Warnings reduce the
signal of future builds and conflict with the planner's no-warning completion
criterion.

Evidence:
- `Tests/OuroMDTests/AppModelReloadTests.swift` assigns `model.bridge = MockBridge()`
  directly in multiple tests.
- `swift test` emits repeated "weak reference will always be nil" warnings.

Recommendation: keep a strong local `let bridge = MockBridge()` in each test
or add a helper that returns `(model, bridge)`.

### Medium: `AppModel.swift` is a god coordinator candidate

`AppModel.swift` remains understandable but holds too many subsystems. Adding
update state directly to it would increase coupling and test setup pain.

Evidence:
- `AppModel.swift` is 846 lines.
- It coordinates editor lifecycle, document IO, autosave, file watching,
  external conflicts, export, theming, folder tree, content search, find/replace,
  formatting, clipboard, zoom, and teardown.

Recommendation: add new updater code as separate pure types plus a small app
coordinator, not as a large block inside AppModel. Later, consider extracting
document IO/reload and folder/search coordination after updater work lands.

### Medium: Folder search scans the folder tree twice

`rescanFolder()` computes both tree and flat list by independently walking the
folder. This is probably fine under the current 5000-file cap, but it is easy
performance headroom to reclaim later.

Evidence:
- `AppModel.rescanFolder()` calls both `FolderScanner.tree(at:)` and
  `FolderScanner.flatList(at:)`.
- `FolderScanner.tree` and `flatList` perform separate recursive scans.

Recommendation: after higher-priority reliability work, create a single scan
result that can derive both tree and flat views.

### Low: README installation and roadmap are stale

The README still references "future in-app auto-updater" and raw GitHub install
URL. This is partially true before the updater lands, but the pretty URL is live
now and should be the primary install path.

Evidence:
- `README.md` install snippet uses raw GitHub.
- `README.md` status/roadmap predates v0.9.0 and the pretty URL.

Recommendation: update README in the same tranche as version truth and updater.

## Healthy Areas To Preserve

- File watcher and external reload behavior is intentionally designed and
  covered by tests for in-place and atomic writes.
- Folder scanning has budget/depth/symlink guards.
- Release packaging already publishes a manifest with all fields the in-app
  updater needs.
- Web editor QOL has dedicated harness coverage (`--wraptest`).
- Rendering coverage has an app-level live surface probe (`--renderprobe`).
- Roundtrip fidelity has an explicit harness path.
- Undo/redo now routes through Vditor's own undo stack instead of generic
  `setValue` behavior.
