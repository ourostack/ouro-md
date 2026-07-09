# Unit 7a Exact-State Dry Run Summary

Status: complete, non-mutating

Live discovery:
- App id: `6787262892`
- Bundle id: `bot.ouro.md`
- Team id: `743GT2AJ24`
- App info id: `9cfeeca8-42d0-4ad6-a2cb-fae6a95681f8`
- Current app info state: `REJECTED`
- Existing app info primary category: `DEVELOPER_TOOLS`
- Existing `en-US` app info localization id: `b5bae77f-a94f-4b39-8ebd-841a6306b1c6`
- Existing subtitle in App Store Connect: `The Markdown App`
- Target version `0.9.80` does not yet have an App Store version resource.
- Uploaded build id `827fa5b9-6994-41eb-bc75-ab3ca469a96f` is version `0.9.80`, `VALID`, not expired.

Dry-run request plan:
- Artifact: `unit7a-dry-run-request-plan.json`
- Request count: 30
- Screenshot scenes: folder workspace, command palette, search/outline, themed export/readability
- Screenshot blockers: none
- Processed build association target: `827fa5b9-6994-41eb-bc75-ab3ca469a96f`
- App category patch target: `DEVELOPER_TOOLS`
- Final submit request is included in the plan, pending Unit 7b reviewer gates and live exact-state apply units.
- Existing rejected review submission `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c` is recorded with strategy `new-submission-review-notes`; no supported API reply endpoint was planned.

Leak check:
- Unit 7a artifacts scan clean for asset-token, profile-content, certificate-content, JWT, bearer-token, AuthKey, and private-key markers.
