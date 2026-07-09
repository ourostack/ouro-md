# Unit 7f Review-Submission Graph Decision

Captured: 2026-07-09 03:12 PDT

## Finding

The planned new review submission `e87d8ecd-9682-4d79-9e60-14c23befd11e` cannot receive the target App Store version item because App Store Connect reports that appStoreVersion `7309944f-cbe8-4518-960c-444e6116ab46` is already present in existing review submission `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c`.

Evidence:

- `unit7f-create-review-submission-item-direct.json`
- Apple error code: `STATE_ERROR.ITEM_PART_OF_ANOTHER_SUBMISSION`
- Existing submission item: `YjM3Zjg0N2UtMGVjYi00ZTdhLWJiMDAtMTRlMzAzOGIwZjRjfDZ8ODg3ODEyNjgx`

## Resolution

Use the existing unresolved review submission graph:

- Review submission: `b37f847e-0ecb-4e7a-bb00-14e3038b0f4c`
- Review submission item: `YjM3Zjg0N2UtMGVjYi00ZTdhLWJiMDAtMTRlMzAzOGIwZjRjfDZ8ODg3ODEyNjgx`
- App Store version: `7309944f-cbe8-4518-960c-444e6116ab46`
- Selected build: `827fa5b9-6994-41eb-bc75-ab3ca469a96f`

`unit7f-resolve-existing-review-submission-item.json` shows the existing item was patched with `resolved: true` and App Store Connect returned item state `READY_FOR_REVIEW`. `unit7f-post-build-review-summary.json` shows the target app store version is `READY_FOR_REVIEW`, the selected build is the uploaded `0.9.80` build, and the accepted review-submission item references the target version.

The empty review submission `e87d8ecd-9682-4d79-9e60-14c23befd11e` has no items. A cancel attempt is recorded in `unit7f-cancel-empty-review-submission.json`; Apple rejected cancellation because the resource is not in a cancellable state. It is not used for final submission.
