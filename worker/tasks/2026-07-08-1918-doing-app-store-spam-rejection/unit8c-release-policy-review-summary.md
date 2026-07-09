# Unit 8c Release Policy Reviewer Summary

Reviewer: Avicenna (`019f468a-8555-73d2-8cb8-92596518e579`)

## Round 1

Result: `FINDINGS`

- `BLOCKER`: the first release-policy exception trusted any committed `worker/tasks/**/*final-live-status.json`, so a PR could fake App Store evidence and bypass same-version freshness.
- `MAJOR`: the first selftest only checked a synthetic parser happy path and did not protect against stale/fake repo evidence, missing exact IDs, unrelated future diffs, or stale state.
- `MINOR`: malformed `screenshotCount` could raise a Python traceback instead of cleanly rejecting the artifact.

## Fix

The broad scan was replaced with a one-time waiver pinned to PR #103 / main merge context, exact version/app/submission/build/screenshot IDs, exact evidence hash, exact release-relevant path set, exact source/package/preflight hashes, a normalized `release-policy.sh` self-hash, and a 14-day evidence age limit.

## Round 2

Result: `CONVERGED`
