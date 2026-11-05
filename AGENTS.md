# Ouro MD Agent Notes

## Shared Native App Shell

- Treat `ouro-native-apple-app-shell` as the owner for reusable native Ouro app chrome: app identity/about, release update surfaces, keyboard shortcut reference UI, and utility-window presentation.
- Keep Ouro MD-specific mappings in `Sources/OuroMD/OuroMDShellAdapter.swift`. If a new shared-looking surface needs glue, add the adapter there first; if it needs reusable behavior, move the behavior to `ouro-native-apple-app-shell` before using it in-app.
- `scripts/check-shell-boundary.sh` is part of CI/preflight. Do not bypass it with an allowlist row unless the code is truly document-editor domain behavior or a narrow adapter.

## CI runners

- Pull request jobs run on GitHub's free runners only (`macos-26`, `macos-26-intel`, `macos-15`; `ubuntu-latest` for anything that needs no Mac). Never put `xcode-27` on a pull request job; `scripts/check-ci-runners.py` enforces it.
- `xcode-27` is billed. Use it only for a check that truly needs Xcode 27, and only on pushes to `main` and releases (`ci.yml`'s `xcode-27-sdk`, `release.yml`). Fence newer-SDK code with `canImport(..., _version:)` so the free image compiles it to nothing.
- A $15-a-month Actions budget scoped to this repository caps the billed spend. When the free image has Xcode 27, follow README's "CI runners" to drop the billed lane.
- Free runners sometimes stall one WebKit test for a minute. `scripts/swift-test-budget.sh` times an over-budget test once more on its own and fails the 20 s budget only if it is still slow; a pass after a warning titled "XCTest runner stall" is a runner stall, not a regression. Don't raise the budget or rerun jobs by hand to get past it.
