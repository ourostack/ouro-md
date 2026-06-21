# Goal

Ship the "next 20+ things" world-class hardening pass for Ouro MD: convert the 25-item acceptance list into permanent CI, release, visual, native UI, update/install, export, folder, and dogfood safeguards.

The work is under autopilot/no-human-gates authority from the operator: do not pause for human approval; use sub-agent reviewer gates, merge to `main`, verify CI/release/install, and clean up branches/worktrees before completion.

# Scope

## In Scope

- CI/local preflight parity:
  1. Local PR preflight script mirrors release freshness and source policy.
  2. GitHub Actions Node 20 deprecation warning is eliminated or made non-actionable by pinning/updating the implicated action.
  3. CI surfaces slowest tests as annotations or a durable artifact.
  4. Individual XCTest runtime budget fails or warns deterministically.
  5. Visual QA failures emit screenshot artifacts.
- Visual/native UX gates:
  6. Visual QA covers Preferences, search sidebar, update progress, and menus.
  7. Accessibility audits cover labels, focus order/proxies, contrast, and reduced motion hooks where practical in headless CI.
  8. File-title/title-click/open flows are dogfooded across untitled, saved, renamed, and missing-file states.
  9. Open Recent / recents surfaces are isolated from shared AppKit globals in tests.
  10. Multi-window regressions cover save, rename, theme, sidebar/search, and menu validation.
  11. Dirty-document + update install + quit-cancelled behavior is covered.
  12. Web content process crash/reload recovery smoke exists.
- Data/search/editor robustness:
  13. Large-folder stress covers thousands of files, deep nesting, unusual names, and symlink traps.
  14. Folder search UX covers too many results, cancellation, binary/unreadable files, and permissions.
  15. Drag/drop file open and image paste/drop are covered at a practical harness level.
  16. Pathological table markdown is locked by fixtures/gates: empty cells, alignment, inline HTML, long URLs.
- Export/update/product polish:
  17. Print/PDF export visual/probe coverage exists.
  18. HTML export snapshot/probe coverage exists for all built-in themes.
  19. Install/update e2e verifies an older live release can update to the latest live release.
  20. Rollback verification covers failed update apply after backup creation.
  21. Updater progress is more cancellable/recoverable for long downloads.
  22. First-launch UX avoids blank white flash/confusing empty state.
  23. Command palette or searchable menu actions exists.
  24. Compact document stats/status surface exists without adding a heavy toolbar.
  25. Signing/notarization readiness is advanced as far as current credentials allow.
- Update docs/scripts/tests/README as needed.
- Bump app release version if any app/release-affecting path changes.
- Use sub-agent reviewer gates for plan and final implementation.

## Out of Scope

- Using or modifying the operator's live in-use Markdown dogfood document.
- Requiring human-only signing/notarization credentials; when unavailable, add local/CI readiness validation and documented hard-exception evidence instead.
- Redesigning Ouro MD into a toolbar-heavy editor.
- Replacing the existing SwiftPM/AppKit/WebKit architecture.

# Completion Criteria

- Each of the 25 acceptance items has a concrete implementation, test/probe, or documented hard-exception disposition with evidence.
- New or changed probes run in both local/package verification and CI where appropriate.
- `swift test`, coverage, native scenario verifier, packaged app verification, and release verification pass.
- App-affecting changes are released and verified from GitHub releases.
- CI produces useful debugging artifacts/annotations for slow tests and visual failures.
- Main is green after merge.
- No stale PR/branch/worktree from this run remains.
- Desk task state records terminal evidence and is archived.

# Code Coverage Requirements

- Maintain `./scripts/check-coverage.sh` passing at 100% line and region coverage for `OuroMDCore`.
- Add focused XCTest coverage for new pure/model/update/menu logic.
- Add headless CLI probes for visual/native/editor/export behavior that XCTest cannot faithfully inspect.
- Add release/package verification coverage for shipped `.app` behavior, not only SwiftPM-local behavior.

# Open Questions

- Signing/notarization cannot be completed without Developer ID credentials. Treat this as a hard exception if no credentials exist, but still add readiness validation/documentation.
- Full drag/drop and image paste can be hard to synthesize headlessly; implement the lowest reliable harness that exercises app code paths and records any remaining AppKit-event limitation.

# Decisions Made

- Branch/worktree: `worker/ouro-md-world-class-hardening` at `/Users/arimendelow/Projects/_worktrees/ouro-md-world-class-hardening`.
- Task docs live in repo under `worker/tasks/` per repo instructions.
- Human gates are replaced by sub-agent reviewer gates under the user's explicit "don't return control" mandate.
- Prefer strengthening existing harnesses (`VisualQATest`, `UISurfaceTest`, `TableWrapTest`, `verify-packaged-app.sh`, CI) before adding new harness types.
- Ship as one or more atomic PRs if the work naturally splits; each PR must reach main/CI/release as applicable before the next.

# Context / References

- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `scripts/verify-packaged-app.sh`
- `scripts/release-policy.sh`
- `scripts/check-coverage.sh`
- `scripts/readiness-stress.sh`
- `Sources/OuroMD/VisualQATest.swift`
- `Sources/OuroMD/UISurfaceTest.swift`
- `Sources/OuroMD/TableWrapTest.swift`
- `Sources/OuroMD/AppDelegate.swift`
- `Sources/OuroMD/AppModel.swift`
- `Sources/OuroMD/DocumentWindowController.swift`
- `Sources/OuroMD/OuroMDUpdateCoordinator.swift`
- `Sources/OuroMD/OuroMDUpdateInstaller.swift`
- `Tests/OuroMDTests/*`
- Desk task: `/Users/arimendelow/desk/ouro-md/world-class-hardening/task.md`

# Notes

- Existing CI already has Swift tests, app bundle verification, native scenario verifier, coverage, release version/freshness, source policy, table/code/visual/search/UI probes, and packaged-app verification.
- Prior release-freshness lesson: run `./scripts/release-policy.sh freshness` before PRs touching app/release-affecting paths.
- Explorer findings folded into scope:
  - CI/release: bump `actions/upload-artifact` to v6, add `scripts/pr-preflight.sh`, add XCTest timing/slow-test budget reporting, upload visual artifacts on failure, and optionally smoke the hosted installer URL.
  - Native UI: add file/open and image transfer harnesses, AX/focus/contrast/reduced-motion checks, real title click-vs-drag decision coverage, and first-frame launch smoke.
  - Updater: add dirty-doc install quit-cancel coverage, structured/cancellable progress, retry recovery, live older-to-latest update harness, and stronger rollback/one-line installer restoration assertions.
  - Coverage matrix: items 3, 4, 15, 17, and 23 are missing today; most others are partial and must be made CI-visible.
- Initial implementation units:
  - Unit 0: discovery/review convergence and exact coverage matrix.
  - Unit 1: CI local preflight, slow-test budget/annotation, artifact plumbing, Node 20 cleanup.
  - Unit 2: visual/native UI/accessibility/menu/title/open/recents/multi-window probes.
  - Unit 3: update/install dirty-quit/cancel/recover/rollback/live-update checks.
  - Unit 4: large-folder/search/drag-drop/image/pathological table/export probes.
  - Unit 5: first-launch, command palette, compact status surface, signing readiness.
  - Unit 6: release bump, full verification, PR/reviewer/merge/release cleanup.

# Progress Log

- 2026-06-21 09:48 Created initial planning doc from the 25-item acceptance list.
