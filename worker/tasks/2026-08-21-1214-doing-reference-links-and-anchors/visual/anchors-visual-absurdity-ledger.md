# Anchor-navigation visual absurdity ledger

| Evidence | State | Observation | Disposition |
|---|---|---|---|
| `anchor-ir-after.png` | IR after `#target-heading` activation | The intended heading lands at the top of the reading region without a URL change, horizontal shift, or duplicated scroll. | intentionally accepted |
| `anchor-sv-preview-after.png` | Source Code preview after anchor activation | The rendered preview lands below its still-visible device toolbar while the source pane remains independently scrollable, literal, and unclipped. | fixed |
| `visual-qa.log` | Existing automated visual suite | Fallback and dogfood fixtures remain free of horizontal overflow, unloaded images, collapsed cells, imbalanced tables, and malformed callouts. | intentionally accepted |

No `ready` or `needs reviewer gate` items remain.
