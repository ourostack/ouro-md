# Doing: Ouro MD World-Class Hardening

Planning doc: `worker/tasks/2026-06-21-0948-planning-world-class-hardening.md`

## Rules

- Work in `/Users/arimendelow/Projects/_worktrees/ouro-md-world-class-hardening` on branch `worker/ouro-md-world-class-hardening`.
- Do not use the operator's live dogfood document.
- No human gates. Use sub-agent reviewer gates for planning/final review and for any ambiguous implementation slice.
- Commit logical units atomically.
- If any app/release-affecting path changes, bump the release version and verify/publish the release before declaring completion.

## Acceptance Trace

| # | Criterion | Implementation Evidence | Status |
|---|---|---|---|
| 1 | Local PR preflight mirrors freshness/source policy | Add `scripts/pr-preflight.sh`; document in README | pending |
| 2 | Node 20 warning handled | Bump `actions/upload-artifact` v5 -> v6; verify release log | pending |
| 3 | Slowest-test annotations/artifact | Add timing parser/wrapper and CI artifact/annotations | pending |
| 4 | Individual XCTest runtime budget | Add deterministic per-test budget enforcement | pending |
| 5 | Visual QA screenshots on failure | Add visual QA wrapper and upload artifact on failure | pending |
| 6 | Visual QA covers prefs/search/update/menu | Extend `UISurfaceTest`/menu probes | pending |
| 7 | Accessibility audit | Add AX labels/focus/contrast/reduced-motion checks | pending |
| 8 | Title/click/open flows | Add title decision/open-state tests | pending |
| 9 | Open Recent isolation | Inject recents provider into menu delegate and tests | pending |
| 10 | Multi-window regressions | Add two-window model/app tests | pending |
| 11 | Dirty doc + update install + quit cancel | Add coordinator/app-level cancellation tests | pending |
| 12 | Web crash/reload smoke | Add actual headless WebKit crash/reload probe | pending |
| 13 | Large folders/deep/unusual/symlink | Extend folder scanner/browser tests | pending |
| 14 | Folder search UX edge cases | Add truncation/cancel/binary/unreadable tests | pending |
| 15 | Drag/drop file open + image paste/drop | Add file-open and JS image-transfer harness | pending |
| 16 | Pathological tables | Extend fixture with empty/aligned/HTML/URL cases and gate | pending |
| 17 | Print/PDF export probe | Add headless export probe with PDF validation | pending |
| 18 | HTML export snapshots all themes | Add render/export checks for each built-in theme | pending |
| 19 | Older-live to latest-live update e2e | Add script harness; run when feasible | pending |
| 20 | Rollback after backup creation | Strengthen installer/one-line rollback tests | pending |
| 21 | Cancellable/recoverable updater progress | Add structured progress/cancel/retry | pending |
| 22 | First-launch blank/empty gate | Add first-launch screenshot/pixel smoke | pending |
| 23 | Command palette/searchable actions | Implement and test action palette | pending |
| 24 | Compact document stats/status | Add status surface and tests | pending |
| 25 | Signing/notarization readiness | Add credential-aware readiness script/check | pending |

## Unit 0: Planning Gate

- [ ] Planning reviewer converges.
- [ ] Patch planning/doing docs if reviewer finds BLOCKER/MAJOR issues.
- [ ] Commit docs.

## Unit 1: CI And Release Harnesses

- [ ] Add `scripts/pr-preflight.sh`.
- [ ] Add XCTest timing/budget wrapper.
- [ ] Add slow-test manifest or allowlist and CI annotations/artifact.
- [ ] Add visual QA artifact wrapper for screenshots on failure.
- [ ] Upgrade `actions/upload-artifact` to v6.
- [ ] Add hosted installer smoke/check.
- [ ] Update README maintainer workflow.
- [ ] Run local script validations.

## Unit 2: Native UI, Accessibility, Menus, Open Flows

- [ ] Inject recents provider through `RecentMenuDelegate` and test without `NSDocumentController.shared`.
- [ ] Extract/test title click-vs-drag decision.
- [ ] Add app/file-open state tests for untitled, saved, renamed, and missing-file documents.
- [ ] Add two-window tests for menu validation, theme/sidebar/search independence, save/rename targeting.
- [ ] Extend `UISurfaceTest` for Preferences/search/update progress/menu layout and AX labels/actions/focus.
- [ ] Add contrast and reduced-motion guardrails.

## Unit 3: Updater Cancellable Progress And Rollback

- [ ] Introduce structured install progress state.
- [ ] Add install cancellation while staging is in-flight.
- [ ] Render Cancel/Retry/status affordances in update progress.
- [ ] Add dirty-doc install quit-cancel test that prevents apply and preserves retry.
- [ ] Harden one-line installer rollback verification.
- [ ] Add forced post-backup rollback test/harness for apply script.

## Unit 4: Editor, Search, Folder, Tables, Image Transfer, Export

- [ ] Extend large-folder/deep/unusual/symlink tests.
- [ ] Add search truncation/cancel/binary/unreadable/permissions coverage.
- [ ] Add `--imagetransfertest` or equivalent bridge transfer probe.
- [ ] Extend pathological table fixture and table gate.
- [ ] Add HTML export checks for all themes.
- [ ] Add PDF/print export probe.
- [ ] Add WebKit crash/reload headless smoke.

## Unit 5: Product Polish

- [ ] Add first-launch nonblank/themed screenshot or pixel smoke.
- [ ] Implement searchable command palette.
- [ ] Add compact document stats/status surface.
- [ ] Add signing/notarization readiness check and document hard exception if credentials unavailable.

## Unit 6: Verification, Review, Merge, Release

- [ ] Run `git diff --check`.
- [ ] Run targeted tests/probes for each changed unit.
- [ ] Run `swift test`.
- [ ] Run `./scripts/check-coverage.sh`.
- [ ] Run app bundle verification.
- [ ] Run PR preflight.
- [ ] Run final sub-agent implementation reviewer gate.
- [ ] Push branch and open PR.
- [ ] Wait for PR CI.
- [ ] Merge to `main`.
- [ ] Wait for main CI and release workflow.
- [ ] Verify published release if app-affecting.
- [ ] Clean branch/worktree.
- [ ] Update and archive Desk task.

## Progress Log

- 2026-06-21 09:48 Created doing doc from audit-backed planning scope.
