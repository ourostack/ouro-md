# Reference-link visual absurdity ledger

| Evidence | State | Observation | Disposition |
|---|---|---|---|
| `reference-ir-focused.png` | IR, expanded reference label selected | The visible selection distinguishes the focused capture; the `irMarkersHidden` live assertion proves expanded markers remain zero-sized. Reference and inline links share one fallback color and underline. | fixed |
| `reference-ir-unfocused.png` | IR, no active selection | Full, collapsed, shortcut, repeated, and normalized reference links read as ordinary rendered links; unresolved syntax remains visible as source text. | intentionally accepted |
| `reference-sv-source-preview.png` | Source Code mode | The source pane intentionally shows authored reference identifiers while the preview pane resolves them into clean links. Pane balance, line length, and contrast remain readable. | intentionally accepted |
| `reference-quartz.png` | Quartz rendered document | Inline and reference links use the Quartz accent with readable contrast against the light document background. | intentionally accepted |
| `reference-graphite.png` | Graphite rendered document | Inline and reference links use the Graphite accent with readable contrast against the dark document background. | intentionally accepted |

No `ready` or `needs reviewer gate` items remain.
