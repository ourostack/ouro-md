# Source-Fit Notes

## Native Title Chrome

- `Sources/OuroMD/DocumentWindowController.swift` installs a custom `DocumentWindow` subclass and routes title clicks through `openDocumentFromTitleClick()`.
- `Tests/OuroMDTests/DocumentWindowControllerTests.swift` currently asserts that title clicks open the file panel and that the custom drag classifier exists.
- Desired first move: replace those tests with native chrome assertions, then remove the custom title-click interception. Keep `syncChrome()` behavior for `title`, `subtitle`, `representedURL`, `isDocumentEdited`, appearance, and menu refresh.

## File/Git Truth Model

- `AppModel` already owns `currentURL`, `isDirty`, `deletedOnDisk`, save/open/rename/autosave/external reload, and `onChromeUpdate`.
- Best source-fit seam is a small read-only model/provider that can be tested independently with an injected git runner. App integration should publish the latest truth state from `AppModel`.
- Lifecycle hooks to refresh truth: welcome/new/open/load initial/rename/save-as/save success/deletion restore/delete marker/external reload/conflict resolution and dirty changes. Editing may show an unsaved overlay while git truth remains read-only.
- Git probes must be read-only and failure-tolerant. No staging, committing, checkout, branch changes, or sidecar metadata.

## Commands

- `Sources/OuroMDAppSupport/CommandPaletteCatalog.swift` owns searchable command items.
- `Sources/OuroMD/AppModel.swift` dispatches palette commands in `performPaletteCommand(id:)`.
- `Sources/OuroMD/MenuBuilder.swift` owns menu placement; File menu is the source-fit home for reveal/copy path/copy relative path/copy git diff command.
- `Sources/OuroMD/AppDelegate.swift` owns menu actions and validation. New actions should route to `AppModel` and be enabled based on current file/repo state.
- Test seams should inject pasteboard writing and Finder reveal behavior so tests do not touch global UI state.

## Sidebar-Free UI

- `Sources/OuroMD/Sidebar.swift` contains `EditorPane`, `DocumentStatusBar`, and command palette.
- The status bar is optional and hidden by default, so file truth cannot live only inside `DocumentStatusBar`.
- Best first pass: add a compact document truth menu/control in the editor overlay near the lower trailing status area, visible when a file/truth state exists even if `statusBarVisible` is false. It should not require or reveal the sidebar.
- Visual QA must cover sidebar closed with status bar hidden and visible.

## Validation Targets

- Focused tests first:
  - `DocumentWindowControllerTests`
  - new file truth model tests
  - `CommandPaletteCatalogTests`
  - `CommandPaletteTests`
  - app/menu routing tests where source-fit
  - accessibility/UI surface test strings
- Full gates later:
  - `swift test`
  - `scripts/check-shell-boundary.sh`
  - `scripts/pr-preflight.sh`
  - scenario/visual QA scripts
