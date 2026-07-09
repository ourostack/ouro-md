# Unit 6d Release Review Summary

Reviewer: Tesla
Status: CONVERGED after evidence cleanup

Findings fixed:
- The first pass found that `unit6c-asc-builds-latest-macos.json` contained ASC `iconAssetToken` / `templateUrl` fields from the raw build response.
- The latest Unit 6c commit was amended from `aede268` to `dd126fc` and force-with-lease pushed, replacing the raw build response with a sanitized summary.

Final reviewer rationale:
- Build `827fa5b9-6994-41eb-bc75-ab3ca469a96f` for version `0.9.80` is visible in App Store Connect with `processingState` `VALID`.
- Final validate/upload passed after the documented 90287 provisioning-profile fix.
- Signing/profile evidence matches `743GT2AJ24.bot.ouro.md`.
- Leakage scans no longer show asset-token, profile-content, certificate-content, JWT, AuthKey, bearer-token, or private-key markers.
