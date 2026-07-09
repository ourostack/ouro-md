# Unit 8c Pre-Merge Sanity Review Summary

Reviewer: Kepler (`019f4699-dbf1-7460-9067-9bbc51fe01fd`)

## Round 1

Result: `FINDINGS`

- `MAJOR`: `git diff --check origin/main...HEAD` was not clean because the committed `unit8c-ci-swift-tests-failed.log` preserved a trailing space from the GitHub Actions Swift version line, while `unit8c-git-diff-check.log` was empty from an earlier pre-commit check.
- `MAJOR`: planning/doing docs marked blanket `100% test coverage on all new code`, but the terminal coverage artifact truthfully recorded changed UI/app-surface Swift files at `0%` or absent from Swift line coverage. The docs overclaimed the evidence.

## Fix

- Removed the trailing whitespace from the preserved CI failure log.
- Kept `unit8c-git-diff-check.log` empty for the cleaned diff-check result.
- Replaced blanket global coverage wording in planning/doing docs with the actual task coverage policy: focused red/green coverage for new automation/contract code, and source-contract/native/accessibility/visual/reviewer evidence for UI/app-surface changes.
- Expanded `unit8-final-coverage-summary.json` to call out the UI/app-surface coverage limitation and validation evidence explicitly.

## Round 2

Result: `CONVERGED`

Kepler verified that both MAJOR findings are resolved:

- `git diff --check origin/main` passes and the whitespace at `unit8c-ci-swift-tests-failed.log:197` is gone.
- Planning/doing coverage criteria and `unit8-final-coverage-summary.json` now describe the evidence-backed split between focused automation/contract tests and UI/app-surface validation.
