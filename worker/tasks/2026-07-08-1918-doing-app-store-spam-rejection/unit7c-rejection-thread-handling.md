# Unit 7c Rejection-Thread Handling

Captured: 2026-07-09 02:27 PDT

## Live State

- Existing rejected submission: `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c`
- Existing rejected item: `YjM3Zjg0N2UtMGVjYi00ZTdhLWJiMDAtMTRlMzAzOGIwZjRjfDZ8ODg3ODEyNjgx`
- Existing item state: `REJECTED`
- Existing item App Store version: `7309944f-cbe8-4518-960c-444e6116ab46`
- Retargeted version string: `0.9.80`
- New review submission created by API: `e87d8ecd-9682-4d79-9e60-14c23befd11e`
- New review submission state: `READY_FOR_REVIEW`

## Handling Decision

Apple's App Store Connect UI supports replying to App Review messages after rejection. The source-owned API plan does not include a supported App Store Connect public API endpoint for posting that Resolution Center/App Review message reply: the official OpenAPI evidence in `unit7c-openapi-review-message-surface.json` exposes `reviewSubmissions`, `reviewSubmissionItems`, `appStoreReviewDetails`, and `appStoreReviewAttachments`, but no message/resolution/reply endpoint.

The revised handling is therefore:

1. Continue staged API mutations for metadata, screenshots, build association, and review-submission item creation.
2. Before final submit, use the logged-in App Store Connect UI fallback to reply to the old unresolved App Review message with the same reviewed substance as the new submission review notes.
3. Capture the UI reply evidence or, if Apple no longer presents the reply control, capture that exact UI state and include the response in the new submission review notes before submit.
4. Do not run final submit without either the UI reply artifact or a concrete UI-blocker artifact.

Apple's own App Store Connect help describes rejected items as editable/resubmittable, screenshot upload as available while an app is in `Rejected` status, and the App Review page as the UI reply surface:

- App and submission statuses: https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses/
- Upload app previews and screenshots: https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- Reply to App Review messages: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages/

Unit 7c's live trace proves the API accepted a new review submission skeleton for the same app after the rejected version object was retargeted to `0.9.80`. Later units will update metadata/review notes, replace screenshots, associate build `827fa5b9-6994-41eb-bc75-ab3ca469a96f`, create the review-submission item, perform the UI reply fallback, and submit the review submission.
