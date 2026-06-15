---
status: in_progress
execution_mode: direct
branch: worker/ouro-md-human-use-readiness
planning: worker/tasks/2026-06-14-2236-planning-human-use-readiness.md
created: 2026-06-14-2236
---

## Goal

Execute the human-use readiness sweep described in the planning doc, patch reachable gaps, and verify the branch end to end.

## Units

- [x] Unit 1 - Telemetry truth audit and fixes
  - Output: local payload audit, focused tests, and any production telemetry patches required.
  - Acceptance: events are content-free, opt-out safe, useful for dogfood debugging, and tested.

- [x] Unit 2 - Synthetic stress harness
  - Output: repeatable stress script/fixtures for large folders, large docs, rendering, editor commands, install/update, first-run, accessibility, and release reproduction.
  - Acceptance: harness runs locally and stores logs/artifacts under this task directory.

- [ ] Unit 3 - Docs and feedback surfaces
  - Output: README/PRIVACY/docs updates, uninstall/reset docs, issue templates, and v1 acceptance checklist.
  - Acceptance: docs match actual product/release behavior and exclude deferred signing/licensing work.

- [ ] Unit 4 - Full verification and harsh review
  - Output: full test/build/probe/stress logs, final reviewer convergence, and PR/release handoff evidence.
  - Acceptance: branch is clean, pushed, reviewed, and either merged/published or clearly ready with no blocking residual.

## Completion Criteria

- [x] Unit 1 complete.
- [x] Unit 2 complete.
- [ ] Unit 3 complete.
- [ ] Unit 4 complete.

## Evidence Directory

`worker/tasks/2026-06-14-2236-doing-human-use-readiness/`

## Progress Log

- 2026-06-14 22:36 Created doing doc and artifact plan.
- 2026-06-14 22:42 Unit 1 complete: added content-free save/open/rename/reload telemetry codes and focused payload/no-leak tests; addressed telemetry reviewer findings.
- 2026-06-14 23:41 Unit 2 complete: added and ran `scripts/readiness-stress.sh`; artifacts cover large folder, large editor roundtrip, large render, screenshot smoke, editor lifecycle, first-run, accessibility, live installer, clean-clone release packaging, and deterministic update checks. Recorded multi-megabyte live-editor roundtrip as a known non-v1 limit.
