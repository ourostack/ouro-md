# Planning: Apple Distribution Kit Program

**Status**: approved
**Created**: 2026-07-03 10:00

## Goal
Create a reusable, app-neutral Apple distribution system that can drive signing, notarization, Mac App Store packaging, upload, metadata, processing checks, and review submission for Ouro MD first and later Ouro Workbench, Spoonjoy, and non-Ouro native apps. The system must replace brittle browser driving with a deterministic reconciler plus local Xcode/Apple CLI runner, while naming the few Apple-account actions that truly require a human.

## Upstream Work Items
- `/Users/arimendelow/desk/ouro-md/app-store-connect-submission/task.md`

## Scope

### In Scope
- Design and implement a neutral executable Apple distribution kit, preferably named `apple-distribution-kit`, with reusable schemas, CLI commands, tests, templates, and app-local manifest contracts.
- Keep app-local desired state in each app repo through a manifest that declares bundle IDs, team/provider hints, distribution channels, certificate/profile requirements, packaging commands, metadata, privacy/export-compliance answers, screenshots/assets, upload policy, and review-submission policy.
- Use App Store Connect API for what Apple exposes programmatically: certificates, bundle IDs, profiles, app/version metadata, app info/localizations, build lookup/status, review submissions, and state reads.
- Use Xcode/Apple command line tooling for binary work: `codesign`, `productbuild`, `xcrun notarytool`, `xcrun stapler`, and `xcrun altool`/Transporter for validation and package upload.
- Treat Apple as authoritative remote state. The kit reconciles desired manifest state against Apple state, plans changes, applies safe changes, and emits explicit `requiresHuman` steps when Apple lacks a public API or account prompts are unavoidable.
- Support direct-download Developer ID releases and Mac App Store releases in apply mode for macOS. Support iOS/TestFlight/App Store lanes in the v1 manifest schema and dry-run planner so Spoonjoy can adopt the shape, but defer iOS apply-mode execution until the Spoonjoy lane unless implementation proves it is cheap and reviewer-approved.
- Make Ouro MD the first consumer: migrate its App Store lane from bespoke docs/scripts toward the shared kit, preserve current behavior, and prove the shared path can reach readiness, validation, upload, build processing, and review-submission preparation.
- Add CI contracts that prove the shared kit works without secrets by default, imports signing assets only when configured, validates manifests, runs dry-run reconciliation, and fails closed on missing required Apple state.
- Update `ouroboros-skills/skills/sign-apple-apps/SKILL.md` to point future agents at the executable kit instead of prose-only playbook steps.
- Document the exact reusable playbook for future apps, including Spoonjoy's current `app.spoonjoy` iOS identity and Workbench's `bot.ouro.workbench` macOS identity.

### Out of Scope
- Pretending every Apple operation is fully automatable. API key creation, Apple Developer membership/payment, legal agreements, first App Store app-record creation, 2FA/CAPTCHA, and managed capability approvals remain human/account gates when Apple requires them.
- Moving release automation into `ouro-native-apple-app-shell`. The shell owns app chrome/contracts, not certificates, secrets, uploads, review metadata, or Apple account state.
- Submitting Ouro Workbench or Spoonjoy to App Review in this first program. They should become ready consumers of the shared kit, but only Ouro MD is the first App Store submission target.
- Committing private keys, `.p8`, `.p12`, `.cer`, provisioning profiles, app-specific passwords, or generated secret material.
- Replacing native app product validation, screenshots, store copy strategy, or domain-specific privacy decisions with generic defaults. The kit can validate presence and schema; app teams still own truth.

## Completion Criteria
- [ ] A neutral shared kit exists with executable CLI, schema, templates, and tests; it is not only a skill or markdown playbook.
- [ ] App manifests are canonical for desired release state, while credentials remain in Keychain/secret stores and Apple remains canonical for remote cert/profile/app/build/review state.
- [ ] The kit has dry-run and apply modes with machine-readable plans, redacted logs, and explicit `requiresHuman` outputs for the known Apple-only human gates.
- [ ] Certificate creation/import supports at least `MAC_APP_DISTRIBUTION`, `MAC_INSTALLER_DISTRIBUTION`, and Developer ID lanes where Apple API/tooling permits; unsupported portal-only steps produce exact handoffs.
- [ ] Bundle ID/profile reconciliation supports macOS `MAC_OS` bundle IDs and `MAC_APP_STORE` provisioning profiles, with reusable extension points for iOS/TestFlight.
- [ ] Developer ID direct-download validation has explicit proof: app signed with Developer ID Application, notarization submitted and accepted through `notarytool`, ticket stapled, `stapler validate` passes, `spctl --assess --type execute` passes, and release manifest records `signingMode: developer-id` plus `notarized: true`.
- [ ] Binary validation/upload uses `altool`/Transporter semantics rather than falsely modeling upload as a plain App Store Connect REST call.
- [ ] App metadata/version/build/review submission automation covers the path after an app record exists: app lookup, version creation/update, localization metadata, build processing lookup, build association, review submission/item creation, and status polling.
- [ ] Ouro MD consumes the shared kit for App Store readiness/validation/upload/review-prep, with existing local scripts either delegated to the kit or reduced to thin app-local wrappers.
- [ ] CI has no-secret gates for manifest validation, API payload generation, redaction, command generation, and selftests; secret-backed workflows import Mac App Store certs/profile/API key only when configured. When secrets or Apple state are absent, the kit produces canonical blocker artifacts instead of ambiguous failures.
- [ ] Live Apple gates have named pass/blocker artifacts for App Store API auth, provider resolution, app-record discovery, certificate presence/import, profile creation/download, package validation, upload id, processed-build discovery, build association, and review-submission readiness.
- [ ] Workbench and Spoonjoy have manifest/adoption PRs or generated adoption fixtures proving the kit is app-neutral and not overfit to Ouro MD; Spoonjoy coverage is dry-run/schema/manifest only unless the lane is explicitly promoted.
- [ ] The `sign-apple-apps` skill and relevant app docs tell future agents to use the shared kit and explain the human/account boundary plainly.
- [ ] 100% test coverage on all new code
- [ ] All tests pass
- [ ] No warnings

## Code Coverage Requirements
**MANDATORY: 100% coverage on all new code.**
- No `[ExcludeFromCodeCoverage]` or equivalent on new code
- All branches covered (if/else, switch, try/catch)
- All error paths tested
- Edge cases: null, empty, boundary values

## Open Questions
- [x] Durable home/name for the executable kit: create a new neutral public repo/package named `apple-distribution-kit` under the existing GitHub org for now, with package/CLI names that contain no Ouro branding. The skills repo references it but is not the implementation.
- [x] Destructive Apple deletes are not allowed by default. Apply mode may print destructive plans, but executing Apple deletes requires an explicit manual flag and reviewer-gated evidence.

## Decisions Made
- The honest primitive is an Apple distribution reconciler/runner, not a “fully programmatic Apple setup” tool. Apple API-key creation, first app record creation, membership/payment, agreements, 2FA/CAPTCHA, and managed capabilities stay explicit `requiresHuman` steps.
- Binary upload is owned by Xcode/Apple CLI tooling (`altool`/Transporter), not the App Store Connect REST client. The REST client manages surrounding state and reads processed builds.
- `ouro-native-apple-app-shell` is not the home for this work. At most, shell may expose distribution-channel descriptors consumed by apps, but release automation belongs in a separate neutral kit.
- App-local desired state must live in app repos. `docs/APP_STORE.md` in Ouro MD should not become canonical for Workbench/Spoonjoy; each app gets its own manifest and generated local docs.
- The first dogfood app is Ouro MD. Workbench and Spoonjoy are adoption/fixture consumers in this program unless explicitly promoted to submission targets.
- v1 supports iOS/TestFlight/App Store in schema and dry-run planner only. macOS Developer ID and Mac App Store are the apply-mode lanes for this program.
- Provider/team ambiguity must be resolved programmatically with `altool --list-providers`, App Store Connect API reads, and manifest/provider hints; ambiguity is a failure, not a guess.
- Secrets are never source state. The kit may materialize temporary files/keychains in CI and local runs, but must redact logs and clean up temp material.
- App Store Connect API access is available locally through a locked neutral credentials directory at `~/Library/Application Support/AppleDistributionKit/app-store-connect/`. The key was validated against the App Store Connect REST API with a custom ES256 JWT; `altool --generate-jwt` produced a token that Apple's REST API rejected, so the kit must own REST JWT generation itself.

## Context / References
- Apple App Store Connect API overview and OpenAPI specification: `https://developer.apple.com/documentation/appstoreconnectapi`
- Apple official OpenAPI zip: `https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip`
- Apple certificate API: `POST /v1/certificates`, `CertificateType` includes `MAC_APP_DISTRIBUTION`, `MAC_INSTALLER_DISTRIBUTION`, `DEVELOPER_ID_APPLICATION`, and `DEVELOPER_ID_APPLICATION_G2`.
- Apple profile API: `POST /v1/profiles`, `profileType` includes `MAC_APP_STORE`, `IOS_APP_STORE`, `MAC_APP_DIRECT`, and TestFlight-related store/ad-hoc variants.
- Apple apps API: `/v1/apps` is currently read/list-only in the public OpenAPI spec; there is no public `POST /v1/apps` endpoint for first app-record creation.
- Local Xcode `xcrun altool --help` supports `--validate-app`, `--upload-package`, `--list-apps`, `--list-providers`, `--generate-jwt`, `--api-key`, `--api-issuer`, and `--p8-file-path`.
- Ouro MD current app-store lane: `/Users/arimendelow/Projects/ouro-md/docs/APP_STORE.md`, `/Users/arimendelow/Projects/ouro-md/scripts/package-app-store.sh`, `/Users/arimendelow/Projects/ouro-md/scripts/check-app-store-build.sh`, `/Users/arimendelow/Projects/ouro-md/scripts/prepare-ci-signing-assets.sh`.
- Reusable signing skill source: `/Users/arimendelow/Projects/ouroboros-skills/skills/sign-apple-apps/SKILL.md`.
- Shared app shell docs: `/Users/arimendelow/Projects/ouro-native-apple-app-shell/docs/INDEX.md`, which intentionally cover shell adoption rather than distribution automation.
- Ouro Workbench release reference: `/Users/arimendelow/Projects/ouro-workbench/scripts/package-app.sh`, `/Users/arimendelow/Projects/ouro-workbench/.github/workflows/release.yml`.
- Spoonjoy current app identity reference: `/Users/arimendelow/Projects/spoonjoy/web/capacitor.config.ts` declares `appId: 'app.spoonjoy'`.
- Reviewer gates already run during ideation:
  - Tinfoil Hat: flagged first app-record creation, current missing identities/API key, CI App Store asset gaps, upload-vs-submission, and provider ambiguity.
  - Stranger With Candy: flagged the misleading “fully programmatic” phrase, binary upload boundary, wrong home in app shell, prose-only skills trap, and canonical state split.

## Notes
Recommended program structure:

1. Shared kit foundation: schema, CLI, redaction, config discovery, manifest validation, dry-run planner, OpenAPI enum pinning, and no-secret tests.
2. Apple auth/provider discovery: JWT signing, App Store Connect API client, provider/team/app lookup, provider ambiguity handling, and credential shape checks.
3. Signing assets: CSR generation, certificate create/download where API-supported, portal handoff where not, local Keychain import, `.p12` export for CI, temporary keychain CI import, and provisioning profile create/download/install.
4. Local package runners: Developer ID sign/notarize/staple, Mac App Store app signing/pkg signing, App Store channel invariants, direct-download channel invariants, and app-neutral wrapper hooks for build commands.
5. Upload/processing: package validation, package upload, upload id capture, build processing wait, processed build lookup by app/version/build number, and exact failure diagnostics.
6. Store state: app lookup, app info/category/privacy/export-compliance checks, app-store version creation/update, localization metadata, screenshots/assets manifest checks, build association, review submission/item creation, and submission status polling.
7. Consumer adoption: Ouro MD first full consumer; Workbench and Spoonjoy manifests/fixtures; generated docs and CI templates for any future app.
8. Skill/docs upgrade: `sign-apple-apps` becomes the human-readable playbook that tells agents to use the executable kit and how to classify Apple-only gates.

Canonical state split:

- App repo manifest: desired release identity, metadata, assets, package commands, channel policy.
- Shared kit: schema, commands, reusable Apple/Xcode integrations, tests.
- Secret stores: API key, certificate passwords, private keys, app-specific passwords, GitHub secrets, Keychain profiles.
- Apple: actual teams, providers, certificates, bundle IDs, profiles, app records, processed builds, review submissions.
- Artifacts: packages, logs, plans, generated docs, screenshots; never canonical secrets.

## Progress Log
- 2026-07-03 10:00 Created after source/API inspection and two fresh sub-agent ideation reviewers.
- 2026-07-03 10:00 Addressed planning reviewer findings: narrowed iOS/TestFlight v1 to schema/dry-run, added Developer ID notarization/stapling proof, and made secret-backed Apple gates produce named pass/blocker artifacts.
- 2026-07-03 10:00 Planning approved after Round 2 cold reviewer convergence.
- 2026-07-03 11:47 Resolved repo/destructive-delete questions and recorded validated App Store Connect API credential boundary.
