# A Very Long Dogfood Heading That Must Wrap Cleanly Without Pushing The Reading Surface Or Sidebar Out Of Shape

This fixture is intentionally a little unruly: headings, images, nested lists,
callouts, code, prose-heavy tables, and sparse audit rows all in one document.

## Mixed Surface Regression Targets

![Fixture diagram](visual-surface-image.svg)

- Native app surfaces
  - Search sidebar
    - Invalid regex and long snippets must stay contained.
  - Preferences
    - Light, dark, and actual-size controls must fit comfortably.

> [!NOTE]
> Callout markers should become labels while the body remains readable.

> [!WARNING]
> Warning callouts should use the same layout contract without hiding text.

| Surface | Expected behavior | Regression signal |
| - | - | - |
| Long heading | Wrap inside the document column and keep page-level horizontal overflow at zero. | `documentElement.scrollWidth` grows beyond the viewport. |
| Image | Load from a relative path and scale within the reading surface. | Natural size is zero or the rendered rect escapes the viewport. |
| Mixed table | Code and prose cells remain readable without collapsing into vertical ribbons. | `Sources/OuroMD/VisualQATest.swift` spills or narrows below a useful width. |

| Artifact | Repository | Producer | Verification consumer |
| - | - | - | - |
| `/Users/example/Projects/ouro-md/tasks/2026-06-20-visual-surface-fixture.md` | ouro-md | Visual QA dogfood pass before release | CI packaged-app probes must verify the file renders without sparse-table silliness. |
