# Planning: Command Catalog Extraction

**Status**: approved
**Created**: 2026-06-30 17:51

## Goal
Extract the command palette catalog models and filtering policy from the AppKit/WebKit executable target into a small pure support target so command discovery can be tested without loading editor shell types.

## Upstream Work Items
- Desk R4: `/Users/arimendelow/desk/ouro-md/native-app-shell-next-roadmap/task.md`
- Extraction plan: `docs/appkit-webkit-extraction-plan.md`

## Scope

### In Scope
- Add an `OuroMDAppSupport` target that imports only `Foundation` for this slice.
- Move `CommandPaletteItem` and `CommandPaletteCatalog` out of `Sources/OuroMD/AppModel.swift`.
- Add a catalog-facing theme descriptor so `OuroMD` can adapt executable-target `Theme` values without moving `ThemeStore`.
- Add `OuroMDAppSupportTests` coverage for catalog filtering, shortcut search aliases, empty/result limits, and theme command generation.
- Keep existing `OuroMD` command palette, shell command-reference, and menu contract tests green.
- Extend the coverage gate to require 100% line and region coverage for `OuroMDAppSupport`.

### Out of Scope
- No changes to PR #87 files: `Sources/OuroMD/LinkTest.swift`, `Sources/OuroMD/web/bridge.js`, `README.md`, or release constants.
- No movement of `EditorWebView`, `EditorBridge`, `WKWebView` coordinator code, or `bridge.js`.
- No extraction of `Theme`, `ThemeStore`, AppKit menu construction, or shell adapter rendering.
- No signing, notarization, App Store, or TestFlight work.

## Completion Criteria
- [x] `OuroMDAppSupport` contains the command catalog model/filtering policy and does not import `AppKit`, `SwiftUI`, or `WebKit`.
- [x] Existing executable target call sites use the extracted catalog with an adapter for `ThemeStore.shared.themes`.
- [x] Tests fail before implementation and pass after implementation.
- [x] 100% test coverage on all new code
- [x] All tests pass
- [x] No warnings

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch, try/catch)
- All error paths tested
- Edge cases: null, empty, boundary values

## Open Questions
- [x] Which extraction boundary should land first? Use command catalog extraction because `docs/appkit-webkit-extraction-plan.md` recommends it first and it avoids PR #87 link-opening files.
- [x] Should `Theme` move too? No. Keep `ThemeStore` and full theme rendering in `OuroMD`; add a small support-target descriptor and adapter.

## Decisions Made
- Use branch/worktree `worker/ouro-md-command-catalog-extraction` at `/Users/arimendelow/Projects/worktrees/ouro-md-command-catalog-extraction`.
- Place task docs in `worker/tasks/` because repo instructions derive the agent name from the first branch segment.
- Add a pure `OuroMDAppSupport` target rather than broadening `OuroMDCore`; the extraction plan calls for app-specific support outside the pure renderer core.
- Run reviewer gates under autopilot instead of human approval.

## Context / References
- `/Users/arimendelow/desk/ouro-md/native-app-shell-next-roadmap/task.md`
- `docs/appkit-webkit-extraction-plan.md`
- `Sources/OuroMD/AppModel.swift`
- `Sources/OuroMD/Themes.swift`
- `Sources/OuroMD/OuroMDShellAdapter.swift`
- `Sources/OuroMD/OuroMDShellContract.swift`
- `Tests/OuroMDTests/CommandPaletteTests.swift`
- `Tests/OuroMDTests/OuroMDShellContractTests.swift`
- `scripts/check-coverage.sh`
- PR #87 currently touches `README.md`, `Sources/OuroMD/LinkTest.swift`, `Sources/OuroMD/web/bridge.js`, and `Sources/OuroMDCore/OuroMDRelease.swift`; this task avoids those files.

## Notes
The support target should expose a minimal public API usable by the executable and tests:

- `CommandPaletteItem`
- `CommandPaletteCatalog.items(themes:)`
- `CommandPaletteCatalog.filter(_:query:emptyLimit:resultLimit:)`
- a lightweight theme command descriptor, likely `CommandPaletteTheme`

## Progress Log
- 2026-06-30 17:51 Created
- 2026-06-30 17:51 Planning reviewer gate converged: template compliance, source fidelity, scope tightness, and PR #87 exclusion checked with no blocker/major findings.
- 2026-06-30 18:06 Completed implementation and validation; PR preflight passed.
