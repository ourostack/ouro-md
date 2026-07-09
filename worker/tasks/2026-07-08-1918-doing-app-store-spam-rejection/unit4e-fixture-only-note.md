# Unit 4e Fixture-Only Executor Note

`scripts/app-store-apply-plan.mjs` currently supports only
`--transport-fixture`. It verifies apply-mode gates, blocked-plan refusal,
placeholder ID substitution, upload-operation traversal, retryable error
classification, redaction, and trace artifact writing without sending any live
App Store Connect mutation.

This is intentional for Unit 4e. Live signed HTTP mutation support remains
deferred until the executor review gate and shared-kit request primitive work
are complete.

Validation:

- `swift test --filter OuroMDAppStoreApplyPlanTests`
- `./scripts/check-apple-distribution-kit.sh`
- Fake apply sample: 30 planned requests, 4 upload operations, redacted trace.
- Unit 4e artifact secret scan.
