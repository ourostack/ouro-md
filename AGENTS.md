# Ouro MD Agent Notes

## Shared Native App Shell

- Treat `ouro-native-apple-app-shell` as the owner for reusable native Ouro app chrome: app identity/about, release update surfaces, keyboard shortcut reference UI, and utility-window presentation.
- Keep Ouro MD-specific mappings in `Sources/OuroMD/OuroMDShellAdapter.swift`. If a new shared-looking surface needs glue, add the adapter there first; if it needs reusable behavior, move the behavior to `ouro-native-apple-app-shell` before using it in-app.
- `scripts/check-shell-boundary.sh` is part of CI/preflight. Do not bypass it with an allowlist row unless the code is truly document-editor domain behavior or a narrow adapter.
