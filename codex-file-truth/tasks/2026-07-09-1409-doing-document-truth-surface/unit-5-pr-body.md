## Problem

Ouro MD needed to feel like a native macOS document editor and make the current file's truth obvious for human-agent collaboration:

- Clicking the document title should use AppKit's native document/proxy behavior, not a custom file picker.
- The editor should show where the current Markdown file lives and whether saved changes are visible to ordinary file/git tooling, without requiring the sidebar.
- Commands should make handoff easy: reveal the file, copy absolute/relative paths, and copy the exact git diff command an agent can run.
- The implementation must stay lightweight and agent-agnostic: no hidden metadata, no agent runner, no review workflow bolted into the app.

## Fix

- Restored native document title chrome by removing the custom title-click interception while preserving edited/deleted/subtitle document state.
- Added a pure `DocumentTruth` model/provider with honest states for untitled, unavailable, non-repo local files, git-unavailable files, tracked clean/modified/staged/mixed files, and untracked files.
- Published document truth from `AppModel` across open/save/save-as/rename/delete/reload lifecycle paths.
- Added File menu and Command Palette actions for Reveal in Finder, Copy File Path, Copy Relative Path, and Copy Git Diff Command.
- Added a compact `File status` control in the editor surface so the truth is visible without opening the sidebar.
- Fixed final-reviewer feedback for nested repo paths: root-relative git pathspecs now run from the repository root, backed by a real temporary-git regression test.
- Hardened packaged WebKit smoke probes so release verification no longer depends on incidental `.build` artifacts or silent headless timeouts.
- Bumped the release to `0.9.81` and regenerated local release artifacts.

## Verification

- `swift test` → 316 tests, 0 failures (`unit-5-swift-test-after-nested-fix.log`)
- `swift test --filter DocumentTruthTests/testRealGitClassifiesNestedTrackedModifiedFile` → red before fix, green after fix (`unit-5-nested-real-git-red.log`, `unit-5-nested-real-git-green.log`)
- `scripts/check-shell-boundary.sh` → ok (`unit-5-check-shell-boundary-after-nested-fix.log`)
- `scripts/check-coverage.sh` → `DocumentTruth.swift` 170/170 lines and 82/82 regions, pure support targets 100% (`unit-5-check-coverage-after-nested-fix.log`)
- `scripts/pr-preflight.sh` → ok, including native scenarios and visual QA (`unit-5-pr-preflight-after-nested-fix.log`)
- `OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY=1 ./scripts/package-release.sh` → verified zip, DMG, manifest, installed app, packaged native scenarios, and release policy scan (`unit-5-package-release-after-nested-fix.log`)
- Visual QA dogfood captured sidebar-free/status-visible document truth screenshots and rendered Markdown dogfood screenshots; harsh visual reviewer passed (`unit-4d-visual-ledger.md`, `unit-4d-review.txt`)
- Final harsh reviewer Round 1 found a nested git pathspec blocker; blocker fixed and sent through Round 2.
