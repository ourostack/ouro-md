# Wide Table Dogfood Fixture

This fixture captures table shapes that have historically failed in the editor:
long path cells, code-heavy cells, wide ownership matrices, sparse artifact
rows, and tables that should scroll locally without pushing the whole document.

## Ownership Matrix

| Unit | Worker-owned tests/checks | Orchestrator-only integration | Notes |
| --- | --- | --- | --- |
| 1 | `Tests/SpoonjoyCoreTests/NativeAPIExpansionTests.swift` | Project membership, scenario metadata | Medium path cells should keep natural proportions. |
| 2 | `Tests/SpoonjoyCoreTests/APITransportTests.swift` | Shared app state wiring | Short prose should not become a huge empty column. |
| 3 | `Tests/SpoonjoyCoreTests/NativeAuthSessionTests.swift` | App auth adapters, URL callback wiring, project member lookup | Prose may wrap, code should remain readable. |
| 4 | `Tests/SpoonjoyCoreTests/NativeCacheFreshnessTests.swift` | `NativeAppSnapshot`, shell indicator integration | Inline code in prose should not force the entire cell into a ribbon. |
| 5 | `Tests/SpoonjoyCoreTests/NativeSyncEngineTests.swift` | `MutationQueue`, global sync shell integration | Multiple code spans should stay legible. |
| 6 | `Tests/SpoonjoyCoreTests/NativeLiveStoreTests.swift` | Unit 16b, `Sources/SpoonjoyCore/AppState/**`, AppShell smoke path | Globs and code paths should widen the table instead of overlapping. |
| 7 | Screenshot/smoke shell contract tests and `scripts/check-launch-screenshot-contract.rb` updates | Orchestrator-only `scripts/capture-native-screenshot-simulator.sh`, `scripts/smoke-macos.sh`, screenshot blocker/design-review artifact contract | Dense row with both prose and code. |
| 8 | Unit-named `Tests/SpoonjoyCoreTests/*TerminalReadinessTests.swift` | Release readiness, install/update checks, telemetry wiring | End of table should not drift sideways on load. |

## Audit Artifacts

| Artifact | Repository | Producer | Verification consumer |
| --- | --- | --- | --- |
| `/Users/example/Projects/spoonjoy-apple/tasks/2026-06-16-1754-planning-siri-full-access-parity/web-product-surface-audit.md` | spoonjoy-apple | Planning pass before doing conversion | Unit 0 baseline must verify the file exists |
| `/Users/example/Projects/spoonjoy-apple/tasks/2026-06-16-1754-doing-siri-full-access-parity/native-shell-contract.md` | spoonjoy-apple | Native shell worker | `scripts/smoke-macos.sh` plus screenshot diff review |
| `/Users/example/Projects/spoonjoy-apple/artifacts/siri-full-access/native-product-surface-audit-very-wide-table-fixture.md` | spoonjoy-apple | Dogfood editor pass | Ouro MD table local-scroll probe |

## Release Chain

| Stage | Source of truth | Required proof | Failure mode caught |
| --- | --- | --- | --- |
| PR source | `Sources/**`, `Resources/**`, `web/**`, `make-app.sh` | CI freshness check confirms version is newer than latest public release | Merged source that no installed user can receive |
| Package | `OuroMD.app` | `verify-packaged-app.sh` probes the bundle while `.build` is hidden | App works from source but shipped bundle misses resources |
| Artifact | `dist/Ouro-MD-<version>.zip` and manifest | SHA, byte count, bundle id, version, build, and git SHA all match | Stale zip attached to a new release |
| Public release | GitHub release assets | Download latest assets, verify manifest, extract, probe app, installer smoke | Latest updater says current while code is not shipped |

## Sparse Wide Table

| Very long left column with path-like content | Narrow | Extremely wide prose column that should wrap comfortably without collapsing the first column or causing document-level horizontal scroll | Last |
| --- | --- | --- | --- |
| `/Users/example/Projects/ouro-md/Sources/OuroMD/web/vditor/dist/js/lute/lute.min.js` | ok | This prose intentionally runs for a while so the column has enough natural width to demonstrate wrapping while the table itself may still need local horizontal scroll at narrow viewport sizes. | done |
| `/Users/example/Projects/ouro-md/Sources/OuroMD/DocumentWindowController.swift` | ok | Title-click behavior is intentionally unrelated to table layout, but the row shape mimics real planning docs where different concerns sit next to each other. | done |

## Code Heavy

| Command | Expected output | Owner |
| --- | --- | --- |
| `swift run ouro-md --tablewraptest --tablewrap-file Tests/Fixtures/dogfood-wide-tables.md --tablewrap-width 1400 --tablewrap-height 5000` | no page overflow, table-local scroll only when needed, initial scroll offsets all zero | CI |
| `./scripts/release-policy.sh verify-published --version 0.9.9 --sha <main-sha>` | latest release, manifest, zip, app, and installer all point at the same build | Release |

## Many Columns

| Area | User signal | Source path | Bundle path | Release path | Probe | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| Tables | Large document remains readable | `Sources/OuroMD/Themes.swift` | `OuroMD.app/Contents/Resources/ouro-md_OuroMD.bundle/web/index.html` | `dist/Ouro-MD-0.9.9.zip` | `--tablewraptest` | CI |
| Title | Clicking title opens file picker | `Sources/OuroMD/DocumentWindowController.swift` | `OuroMD.app/Contents/MacOS/ouro-md` | `Ouro-MD-0.9.9.manifest.json` | `DocumentWindowControllerTests` | Swift tests |

## Narrow Prose

| Signal | Meaning |
| --- | --- |
| no horizontal document overflow | only tables may scroll horizontally |
| no collapsed code cells | path/code content should stay readable |
| no initial table scroll offset | opening a document starts every table at the left edge |

## Mixed Content

| Checklist | Evidence | Status |
| --- | --- | --- |
| File picker title click | `testTitleClickRoutesToOpenPanelInsteadOfRename` | required |
| Dogfood table layout | `Tests/Fixtures/dogfood-wide-tables.md` plus generated built-in fixture | required |
| Published release freshness | `release-policy.sh freshness` and `release-policy.sh verify-published` | required |
