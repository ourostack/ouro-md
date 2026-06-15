---
status: approved
execution_mode: direct
branch: worker/ouro-md-human-use-readiness
created: 2026-06-14-2236
---

## Goal

Make Ouro MD ready for Ari's first real dogfood session by running a synthetic human-use readiness sweep, fixing reachable gaps, and leaving durable evidence for telemetry, stress, docs, install/update, first-run, accessibility, and release reproducibility.

## Scope

### In Scope

- Verify the telemetry story is accurate, complete enough for debugging, opt-out safe, and content-free.
- Add non-content telemetry/error coverage if synthetic tests show missing user-debuggable events.
- Create and run synthetic stress tests for large folders, large documents, rendering fixtures, save/reload/rename paths, install/update, first-run, and release reproducibility.
- Review and patch docs for install, update, privacy, troubleshooting, uninstall/reset, known limits, issue templates, and a v1 acceptance checklist.
- Run harsh sub-agent review gates against planning, implementation, and release-readiness evidence.
- Keep all evidence under `worker/tasks/2026-06-14-2236-doing-human-use-readiness/`.

### Out of Scope

- Developer ID signing and notarization.
- Licensing, payment, or hosted-value work.
- Multi-day real dogfooding that only Ari can perform.
- PostHog dashboard confirmation requiring browser login or API credentials unavailable in the repo.

## Completion Criteria

- Telemetry payload tests prove expected events are content-free, opt-out respected, and synthetic debug story is coherent.
- Synthetic stress suite runs and records large workspace, large document, rendering, editor command, install/update, first-run, accessibility, and clean-clone release results.
- Any verified P0/P1/P2 reachable defect found by the sweep is fixed or explicitly dispositioned with evidence.
- README/PRIVACY/docs/templates/checklist describe the current v1 human-use story accurately.
- Full local verification passes after changes.
- Harsh sub-agent reviewers converge or all findings are addressed/dispositioned.

## Code Coverage Requirements

- New production code must have focused tests for success and failure/error paths.
- New scripts/docs-only harnesses must have live execution evidence in the artifact directory.
- Modified telemetry code must assert outgoing event names/properties and must not rely only on mocked response success.

## Open Questions

- None blocking. If PostHog dashboard auth is unavailable, local payload verification is sufficient for this branch and dashboard verification remains an Ari dogfood task.

## Decisions Made

- Use direct execution on `worker/ouro-md-human-use-readiness` under the user's no-human-gates/autonomous mandate.
- Treat GUI-only findings as fixable only when an automated or live local verification path can prove the fix without risking editor corruption.
- Keep all test fixtures synthetic and outside user documents.

## Context / References

- Prior readiness PR: https://github.com/ourostack/ouro-md/pull/3
- Current release: https://github.com/ourostack/ouro-md/releases/tag/v0.9.2
- Desk task: `/Users/arimendelow/desk/ouro-md/v1-editor/task.md`
- Telemetry implementation: `Sources/OuroMD/OuroMDTelemetry.swift`
- Release tooling: `scripts/package-release.sh`, `web/ouro-md-install.sh`, `make-app.sh`

## Notes

- User will begin real dogfooding tomorrow; this branch should make the app boring enough for real use and make telemetry useful when dogfood issues appear.

## Progress Log

- 2026-06-14 22:36 Created planning doc under autonomous direct execution.
