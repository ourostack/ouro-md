## Current Item

- Objective: fix reference-style link rendering and heading-fragment navigation, validate through CI, merge, publish, and smoke the consuming app.
- Planning: `worker/tasks/2026-08-21-1214-planning-reference-links-and-anchors.md`
- Doing: `worker/tasks/2026-08-21-1214-doing-reference-links-and-anchors.md`
- Source PR: https://github.com/ourostack/ouro-md/pull/111
- Merge commit: `a768fc54f69269afe77d8803f9a1581a6d484086`
- Release: https://github.com/ourostack/ouro-md/releases/tag/v0.9.85
- State: terminal.
- Next action: none.

## Terminal Evidence

- PR #111 merged through the repository's squash policy after App bundle, Coverage, Native scenario verifier, and Swift tests passed on the final head.
- `scripts/pr-preflight.sh` passed locally with release policy, shell boundaries, Vditor vendor integrity, the XCTest budget, support-target line/region coverage, native scenarios, and visual QA.
- Release workflow `32811257413` published `v0.9.85` from the merge commit after retrying one transient `hdiutil: Resource busy` packaging failure.
- The release contains ZIP, DMG, and manifest assets; the workflow verified the published release, hosted installer, and older-release-to-current live update path.
- A fresh download of the public ZIP passed `scripts/verify-packaged-app.sh`. The packaged IR fixture resolved reference links and scrolled fragments; the Source Code fixture stayed literal, rendered references in preview, and scrolled heading and footnote fragments.
- The public hosted installer downloaded, checksum-verified, installed, code-signature-verified, and policy-scanned Ouro MD 0.9.85 in an isolated destination.
- The feature PR, remote branch, local branch, disposable worktree, browser artifacts, release-smoke directory, and hosted-installer directory were removed. The canonical checkout was clean before this state-only update.

## Continuation Scan

| candidate | classification | evidence | disposition |
| --- | --- | --- | --- |
| reference links and anchors | none | PR #111 merged; v0.9.85 published; packaged and hosted-installer smokes passed | no next action |
| App Store rejection task | deferred by scope | older task doc remains non-terminal, but PR #103 merged and the current mandate is the direct-download link/anchor release | leave for its own App Store operational mandate |
| Apple distribution kit task | deferred by scope | separate non-terminal distribution task doc; no open Ouro MD PR or issue | leave for its own distribution mandate |
| control-deck adoption task | deferred by scope | separate review-state task doc; no open Ouro MD PR or issue | leave for its own control-deck mandate |

## Stop Condition

Hard no: no ready work remains in the reference-link and anchor mandate. Remaining non-terminal records belong to separate, explicitly out-of-scope mandates.
