# Unit 8c CI Freshness Fix Summary

## Failure

PR #103 initially failed the `Swift tests` job at `Verify release freshness policy`.

The failing command was:

```bash
./scripts/release-policy.sh freshness
```

The failure was expected for this App Store resubmission shape: source and packaging-visible files changed, but the source version intentionally remains `0.9.80` because App Store Connect accepted the existing rejected `0.9.80` version/build graph and the final submission is already `WAITING_FOR_REVIEW`.

## Fix

`scripts/release-policy.sh` now contains a one-time App Store resubmission waiver for this exact submission only. The waiver requires:

- version `0.9.80`
- repository `ourostack/ouro-md`
- PR context `refs/pull/103/merge` from branch `worker/app-store-spam-rejection`, or push-main context after merge
- base ref `main` or `origin/main`
- the exact release-relevant path set for this resubmission
- exact SHA-256 hashes for the release-relevant source/package/preflight files
- a normalized self-hash for `scripts/release-policy.sh`
- exact final App Store evidence path and hash
- exact App Store app/version/submission/build/screenshot IDs and states from `unit7h-final-live-status.json`
- final evidence captured within 14 days

Normal same-version app/release-affecting changes remain blocked.

## Verification

- `unit8c-release-policy-app-store-resubmission-selftest.log`
- `unit8c-release-policy-freshness.log`
- `unit8c-release-policy-main-freshness.log`
- `unit8c-release-policy-package-guards.log`
- `unit8c-release-policy-paths.log`
- `unit8c-release-policy-scan.log`
- `unit8c-release-policy-bash-n.log`
- `unit8c-git-diff-check.log`

Harsh reviewer Round 1 found the broad evidence scan unsafe. Round 2 reviews the pinned waiver.
