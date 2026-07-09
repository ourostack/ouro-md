# Unit 0 Artifact Index

- `unit0-git-state.txt`: branch, commit, remote, and initial worktree state.
- `unit0-tool-versions.txt`: Xcode, Swift, Node, npm, and jq versions.
- `unit0-version-state.txt`: source version, manifest version, and App Store manifest category.
- `unit0-asc-smoke.json`: redacted App Store Connect API smoke result.
- `unit0-asc-*.json`: redacted live App Store Connect reads for app, versions, builds, review submissions, rejected-version localization/review-detail/screenshot state.
- `unit0-baseline-summary.pretty.json`: compact state summary used by later units.
- `unit0-secret-scan.txt`: artifact secret scan result.

Baseline conclusion: source/manifest are already `0.9.80`; App Store Connect currently has rejected version `0.9.79`, one valid uploaded `0.9.79` build, one unresolved rejected review submission, and one complete desktop screenshot attached to the rejected version.
