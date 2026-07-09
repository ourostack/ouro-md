# Unit 4b Wrapper Suffices Note

`scripts/app-store-request-plan.mjs` is a dry-run planner only. It does not sign,
send, or upload App Store Connect mutations, so the existing local wrapper around
`ourostack/apple-distribution-kit` is sufficient for this unit.

The planner emits JSON:API request shapes, upload-operation placeholders, stale
rejected-ID guards, and redacted artifacts. Live authenticated mutation support
remains intentionally deferred to the Unit 4d/4e executor, where the shared kit
may need a signed non-GET request primitive.

Validation:

- `swift test --filter OuroMDAppStoreRequestPlanTests`
- `./scripts/check-apple-distribution-kit.sh`
- `node scripts/app-store-request-plan.mjs --selftest --json`
- `node scripts/app-store-request-plan.mjs --selftest-stale-ids --json`
- Unit 4b artifact secret scan.
