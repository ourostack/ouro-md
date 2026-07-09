# Unit 4d Visual QA Ledger

## Surfaces

- Native editor pane, sidebar closed, status bar hidden: `unit-4d-visual-qa/ouro-md-document-truth-status-hidden.png`
- Native editor pane, sidebar closed, status bar visible: `unit-4d-visual-qa/ouro-md-document-truth-status-visible.png`
- Rendered Markdown dogfood fixture, Quartz: `unit-4d-visual-qa/ouro-md-dogfood-quartz.png`
- Rendered Markdown dogfood fixture, Graphite: `unit-4d-visual-qa/ouro-md-dogfood-graphite.png`
- Rendered wide-table fixture, Quartz: `unit-4d-visual-qa/ouro-md-wide-tables-quartz.png`

## Automated Evidence

- `unit-4d-ui-surface.log`: native UI probe passed; document truth strip fitting size was hidden `400.0x320.0`, visible `500.0x320.0`; labels exposed `File status` and `Modified`.
- `unit-4d-web-visual-qa.log`: visual QA passed fallback Quartz, dogfood Quartz, and dogfood Graphite with `0.0px` page horizontal overflow, no escaped headings/images/tables, no collapsed cells, and no imbalanced tables.

## Absurdity Ledger

| artifact | state | observation | disposition |
| --- | --- | --- | --- |
| `ouro-md-document-truth-status-hidden.png` | sidebar closed, status bar hidden | Bottom strip is readable and reserved below the editor, not floating over document content. The editor body is blank in this native SwiftUI snapshot because WebKit content is covered by the separate rendered-document captures. | intentionally accepted |
| `ouro-md-document-truth-status-visible.png` | sidebar closed, status bar visible | File status and word/character/mode status fit on one bottom strip with no overlap or cramped wrapping. | fixed |
| `ouro-md-dogfood-quartz.png` | Quartz rendered Markdown | Long heading wraps, callouts are readable, table stays contained. The small blank rectangle is the intentionally tiny fixture image and the probe confirms it loaded. | intentionally accepted |
| `ouro-md-dogfood-graphite.png` | Graphite rendered Markdown | Same layout as Quartz with readable contrast and no sideways escape. Tiny image placeholder is fixture content. | intentionally accepted |
| `ouro-md-wide-tables-quartz.png` | dense wide-table fixture | Wide tables scroll locally; the page itself remains aligned and readable. Right-edge clipping is the expected local table viewport, not document overflow. | intentionally accepted |

## Closed State

- No `ready` or `needs reviewer gate` visual issues remain.
- The status-visible row is marked `fixed` because it verifies the layout change that moved file status into the reserved bottom strip.
