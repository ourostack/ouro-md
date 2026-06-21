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
| `./scripts/release-policy.sh verify-published --version 0.9.13 --sha <main-sha>` | latest release, manifest, zip, app, and installer all point at the same build | Release |

## Many Columns

| Area | User signal | Source path | Bundle path | Release path | Probe | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| Tables | Large document remains readable | `Sources/OuroMD/Themes.swift` | `OuroMD.app/Contents/Resources/ouro-md_OuroMD.bundle/web/index.html` | `dist/Ouro-MD-0.9.13.zip` | `--tablewraptest` | CI |
| Title | Clicking title opens file picker | `Sources/OuroMD/DocumentWindowController.swift` | `OuroMD.app/Contents/MacOS/ouro-md` | `Ouro-MD-0.9.13.manifest.json` | `DocumentWindowControllerTests` | Swift tests |

## Narrow Prose

| Signal | Meaning |
| --- | --- |
| no horizontal document overflow | only tables may scroll horizontally |
| no collapsed code cells | path/code content should stay readable |
| no initial table scroll offset | opening a document starts every table at the left edge |

## Offline Queue Policy

This table mirrors the sparse two-column shape from the live doing doc: one
side is a dense list, the other is shorter prose. It should not render as a
thin left ribbon beside a huge empty right column.

| Queueable while offline | Online-only while offline |
| --- | --- |
| Recipe create/update/delete/fork; step create/update/delete/reorder; step ingredient add/delete; dependency edits; cookbook create/rename/delete/add/remove recipe; shopping item add/check/delete/add-from-recipe/clear-completed/clear-all; cook progress/checkoff/timer/scale changes; spoon create/update/delete/photo payload updates; cover upload/set-active/remove/archive/regenerate/from-spoon; capture draft create/edit/discard; import submit; profile display-field update; profile photo upload/remove after local media staging; notification preference update; APNs device registration/revocation after a device token exists; Siri writes that map to one of these queueable mutations. | OAuth sign-in/callback; token create; token revoke; OAuth connection disconnect; logout/session revoke; passkey/password/provider-link actions; APNs permission prompt; APNs device-token acquisition; production AASA/APNs/TestFlight validation; provider-generated cover regeneration or recipe import when the matching `ProviderSecret` blocker exists; destructive production operation approval. |

## Mixed Content

| Checklist | Evidence | Status |
| --- | --- | --- |
| File picker title click | `testTitleClickRoutesToOpenPanelInsteadOfRename` | required |
| Dogfood table layout | `Tests/Fixtures/dogfood-wide-tables.md` plus generated built-in fixture | required |
| Published release freshness | `release-policy.sh freshness` and `release-policy.sh verify-published` | required |

## Empty Cells

| Item | Optional owner | Notes | Empty tail |
| --- | --- | --- | --- |
| Sparse row with long content beside blanks |  | This row keeps enough prose to prove empty neighbors keep visible geometry instead of collapsing into zero-width ghosts. |  |
|  | Design review |  |  |
| Whitespace-only cell follows |   | Empty-looking cells should still show borders and row height. | done |

## Alignment Matrix

| Left label | Center status | Right number | Default note |
| :--- | :---: | ---: | --- |
| alpha | pending | 10 | ordinary prose |
| beta | verified | 2000 | `code` |
| gamma |  | 30000 | empty center cell |

## Inline HTML

| HTML span | Keyboard | Break | Link |
| --- | --- | --- | --- |
| <span class="fixture-inline">inline span content</span> | <kbd>Cmd</kbd> + <kbd>O</kbd> | first<br>second | <a href="https://example.com/pathology">inline anchor</a> |
| Text before <span>middle</span> text after | <kbd>Esc</kbd> | line<br>break<br>stack | <a href="mailto:test@example.com">mail link</a> |

## URL Cells

| URL shape | Value | Notes |
| --- | --- | --- |
| Plain long URL | https://example.com/this/is/a/really/long/path/that/should/not/burst/out/of/the/table/cell/or/push/the/document-sideways?with=query&and=more-query | plain autolink-style text |
| Markdown link | [release artifact](https://github.com/ourostack/ouro-md/releases/download/v0.9.15/Ouro-MD-0.9.15.manifest.json) | link element should stay inside its cell |
| Code URL | `https://example.com/code/url/with/a/very-long-token-that-prefers-horizontal-room` | code element gets intrinsic room or local overflow |

## Sparse Screenshot Shape

| Queueable while offline | Online-only while offline | Empty |
| --- | --- | --- |
| Recipe create/update/delete/fork; step create/update/delete/reorder; step ingredient add/delete; dependency edits; cookbook create/rename/delete/add/remove recipe; shopping item add/check/delete/add-from-recipe/clear-completed/clear-all; cook progress/checkoff/timer/scale changes; spoon create/update/delete/photo payload updates; cover upload/set-active/remove/archive/regenerate/from-spoon; capture draft create/edit/discard; import submit; profile display-field update; profile photo upload/remove after local media staging; notification preference update; APNs device registration/revocation after a device token exists. | OAuth sign-in/callback. |  |
| Short left | OAuth sign-in/callback; token create; token revoke; OAuth connection disconnect; logout/session revoke; passkey/password/provider-link actions; APNs permission prompt; APNs device-token acquisition; production AASA/APNs/TestFlight validation; provider-generated cover regeneration or recipe import when the matching `ProviderSecret` blocker exists. |  |

## Long Code

| Kind | Token | Explanation |
| --- | --- | --- |
| Code-only | `Sources/OuroMD/VeryLongGeneratedFixtureNameThatShouldStayReadableInsideATableCellWithoutOverlappingNeighbors.swift` | code-only cells keep intrinsic width |
| Mixed prose/code | The path `Sources/OuroMD/web/vditor/dist/js/lute/lute.min.js` appears inside prose and should not turn the whole cell into a ribbon. | mixed content wraps normally |
| Multiple spans | `alpha/beta/gamma/delta/epsilon.md`, `scripts/capture-native-screenshot-simulator.sh`, and `dist/Ouro-MD-0.9.15.zip` | multiple inline spans remain bounded |

## Stress Grid

| C01 | C02 | C03 | C04 | C05 | C06 | C07 | C08 | C09 | C10 | C11 | C12 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r01 c01 | r01 c02 | r01 c03 | r01 c04 | r01 c05 | r01 c06 | r01 c07 | r01 c08 | r01 c09 | r01 c10 | r01 c11 | r01 c12 |
| r02 c01 | r02 c02 | r02 c03 | r02 c04 | r02 c05 | r02 c06 | r02 c07 | r02 c08 | r02 c09 | r02 c10 | r02 c11 | r02 c12 |
| r03 c01 | r03 c02 | r03 c03 | r03 c04 | r03 c05 | r03 c06 | r03 c07 | r03 c08 | r03 c09 | r03 c10 | r03 c11 | r03 c12 |
| r04 c01 | r04 c02 | r04 c03 | r04 c04 | r04 c05 | r04 c06 | r04 c07 | r04 c08 | r04 c09 | r04 c10 | r04 c11 | r04 c12 |
| r05 c01 | r05 c02 | r05 c03 | r05 c04 | r05 c05 | r05 c06 | r05 c07 | r05 c08 | r05 c09 | r05 c10 | r05 c11 | r05 c12 |
| r06 c01 | r06 c02 | r06 c03 | r06 c04 | r06 c05 | r06 c06 | r06 c07 | r06 c08 | r06 c09 | r06 c10 | r06 c11 | r06 c12 |
| r07 c01 | r07 c02 | r07 c03 | r07 c04 | r07 c05 | r07 c06 | r07 c07 | r07 c08 | r07 c09 | r07 c10 | r07 c11 | r07 c12 |
| r08 c01 | r08 c02 | r08 c03 | r08 c04 | r08 c05 | r08 c06 | r08 c07 | r08 c08 | r08 c09 | r08 c10 | r08 c11 | r08 c12 |
| r09 c01 | r09 c02 | r09 c03 | r09 c04 | r09 c05 | r09 c06 | r09 c07 | r09 c08 | r09 c09 | r09 c10 | r09 c11 | r09 c12 |
| r10 c01 | r10 c02 | r10 c03 | r10 c04 | r10 c05 | r10 c06 | r10 c07 | r10 c08 | r10 c09 | r10 c10 | r10 c11 | r10 c12 |
| r11 c01 | r11 c02 | r11 c03 | r11 c04 | r11 c05 | r11 c06 | r11 c07 | r11 c08 | r11 c09 | r11 c10 | r11 c11 | r11 c12 |
| r12 c01 | r12 c02 | r12 c03 | r12 c04 | r12 c05 | r12 c06 | r12 c07 | r12 c08 | r12 c09 | r12 c10 | r12 c11 | r12 c12 |
