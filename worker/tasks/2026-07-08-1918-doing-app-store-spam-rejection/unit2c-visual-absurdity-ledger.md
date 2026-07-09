# Unit 2c Visual Absurdity Ledger

## Surfaces

- About/shell subtitle: `Local Markdown workspace for Mac files.`
- First-launch welcome document: local workspace, File Tree, Search, Outline,
  Command Palette, PDF/HTML export, and no-account copy.
- Release highlights/What's New copy.
- CLI help headline.

## Evidence

- `unit2c-swift-test.log`: full Swift package tests pass.
- `unit2c-make-app.log`: app bundle build passes.
- `unit2c-run-visual-qa.log`: visual QA wrapper passes quartz and graphite probes.
- `unit2c-firstlaunchtest.log`: built-in first-launch DOM and snapshot-pixel
  probe passes.
- `unit2c-uisurfacetest.log`: About, preferences, command reference, menu, and
  search surface metrics pass.
- `unit2c-accessibilityaudit.log`: runtime accessibility, source labels, menu
  shortcut, and command discoverability audits pass.
- `unit2c-welcome-snapshot.png`: durable rendered welcome snapshot from the app
  `--shoot` path using `Tests/Fixtures/welcome-app-store-positioning.md`.
- `unit2c-welcome-snapshot-dimensions.log`: captured PNG dimensions.
- `unit2c-review-fix-green-positioning-tests.log`: verifies user-facing
  release highlights, rejects internal review/remediation language, and proves
  the visual fixture matches `Welcome.markdown` apart from the conventional
  terminal file newline.

## Inspection

| artifact | viewport/state | observation | disposition |
| --- | --- | --- | --- |
| `unit2c-welcome-snapshot.png` | rendered welcome Markdown at 900px capture width | Copy is readable, heading hierarchy is coherent, no text overlaps, no words are clipped, and the local workspace/File Tree/Search/Outline/Command Palette/PDF/HTML/no-account claims are visible in the first viewport. | intentionally accepted |
| `unit2c-welcome-snapshot.png` | lower welcome document | There is white space below the short first-launch document, but the content itself is complete and the empty area is ordinary document canvas, not hidden or broken content. | intentionally accepted |
| `unit2c-uisurfacetest.log` | About window, preferences, command reference, search sidebar, command palette/status surfaces | Fitting-size and semantic checks pass; no control overflow, stale update-state mismatch, or missing accessibility label was reported. | intentionally accepted |
| `unit2c-run-visual-qa.log` | quartz and graphite rendered dogfood documents | Visual QA reports zero horizontal overflow, no collapsed/imbalanced tables, no escaped visual artifacts, and loaded image coverage. | intentionally accepted |
| `unit2c-review-fix-green-positioning-tests.log` | source copy drift guard | The fixture used for visual capture is locked to `Welcome.markdown`, so the screenshot cannot silently drift from the source welcome copy. | intentionally accepted |

No `ready` or `needs reviewer gate` ledger items remain.
