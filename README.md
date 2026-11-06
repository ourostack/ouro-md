<!-- ourostack:brand:start -->
<p align="center">
  <a href="https://github.com/ourostack"><img src="https://raw.githubusercontent.com/ourostack/.github/main/brand/headers/ouro-md.webp" alt="Ouro reading a clean page on a wooden lectern beside a lamp and a cup of tea, with pages drifting through the dawn air" width="100%"></a>
</p>
<!-- ourostack:brand:end -->

# ouro-md

A minimalist, beautiful, themable Markdown editor that's native to macOS.

ouro-md keeps the chrome out of your way: no busy toolbar, just your words set
in careful typography on a centered page. Type Markdown and watch it render in
place — switch themes live, and read the same document four different ways.

> **Status:** v0.9.111. Reads and edits Markdown today. Release tooling produces Developer-ID signed/notarized public artifacts — see [First launch](#first-launch).

---

## Features

- **Instant rendering.** Type Markdown and see it render in place (live-preview
  "IR" mode), with syntax markers kept subtle. Also offers WYSIWYG and
  Split (source + preview) modes.
- **Beautiful, themable.** Four built-in themes — **Quartz** (calm light),
  **Graphite** (focused dark), **Manuscript** (warm serif), and **Newsprint**
  (crisp editorial). Drop your own CSS to add more.
- **Full Markdown.** CommonMark + GFM: tables, task lists, strikethrough,
  fenced code with highlighting, math (KaTeX), footnotes, and diagrams.
- **Native macOS.** A real `.app` with a transparent titlebar + clickable
  filename opening the system's Name, Tags, Where and lock controls,
  the standard menu bar, Open Recent, unsaved-changes prompts,
  drag-to-open, and **auto-save** for titled files.
- **Sidebar.** A collapsible sidebar (**⇧⌘L**) with a live document **Outline**
  (**⌃⌘1**) and a **File Tree** (**⌃⌘3**) of the current folder.
- **Modes & tools.** **Source Code Mode** (**⌘/**), **Focus** (**F8**) and
  **Typewriter** (**F9**) modes, **Find** (**⌘F**), and folder **Search** (**⇧⌘F**). A
  compact **status bar** (word/char count, mode, theme) sits a toggle away
  (**View ▸ Toggle Status Bar**) and is hidden by default.
- **Export.** Save to themed, self-contained **HTML** or **PDF**.
- **Print layout.** **File ▸ Print…** and **File ▸ Export ▸ PDF…** share a readable page preview with margins, font size, line spacing, page navigation and zoom. Choose **Page-bottom footnotes**, **Endnotes** or **Original links** under **Citations**; generated sources include web, email, phone and local or relative file destinations, so check that choice before sharing output. **New page before** starts each selected heading level on a fresh page; authored `<div class="page-break"></div>` and `<!-- pagebreak -->` markers also work. Use **Page Setup…** for paper size and orientation. The first page appears while the remaining pages prepare, and you can request output without waiting for the whole preview; only the complete document with your final settings is printed or exported. Folded sections expand in the print copy so their content is not silently omitted. Print settings do not change your Markdown or reading view.
- **Images that just work.** Pasted or dropped images are embedded inline (as
  data URIs) — no upload server, no broken links.
- **Headless render.** `ouro-md --render file.md` prints a styled HTML document
  to stdout for scripting and previews.

## Install

**One line (recommended) — no checkout needed:**

```sh
curl -fsSL https://ouro.bot/ouro-md-install.sh | bash
```

Downloads the latest [release](https://github.com/ourostack/ouro-md/releases),
verifies its checksum against the published manifest, installs **Ouro MD.app** to
`/Applications` (falls back to `~/Applications`), registers it with Launch
Services, and opens it. macOS-only; needs just `curl`, `ditto`, `shasum`. Re-run
it any time to update to the latest release, or use **Ouro MD ▸ Check for Updates...**
inside the direct-download app.

Prefer a Finder install? Download the signed, notarized DMG from
`https://ouro.bot/apps/ouro-md/` or the latest GitHub release, then drag
**Ouro MD.app** to Applications.

**From source (for development):**

```sh
./install.sh            # build + install to /Applications/Ouro MD.app
./install.sh --update   # git pull, then rebuild + reinstall
```

- **Where it lives:** `/Applications/Ouro MD.app` (or `~/Applications`)
- **How to launch:** double-click in Finder · `open -a "Ouro MD"` · or the `md`
  shell alias (`md notes.md`). The one-line installer adds the `md` alias to your
  shell rc automatically (skipped if you already have an `md` alias; opt out with
  `OURO_MD_NO_ALIAS=1`).

Public direct-download releases are Developer-ID signed and notarized. Ouro MD
also checks for verified releases in the background by default; disable
automatic checks in **Settings** if you prefer to update manually.

For uninstall/reset steps, see [docs/UNINSTALL_RESET.md](docs/UNINSTALL_RESET.md).
For install or update problems, see
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
For a map of current source-of-truth docs versus historical task artifacts, see
[docs/INDEX.md](docs/INDEX.md).

### Cutting a release (maintainers)

```sh
./scripts/bump-version.sh 0.9.39            # rewrites the version + release date atomically
./scripts/check-release-secrets.sh          # confirms GitHub release telemetry secrets exist
./scripts/check-signing-readiness.sh        # confirms signing/notarization tooling and secret shape
./scripts/verify-release-version.sh         # OuroMDRelease.swift / README agree (make-app derives)
./scripts/pr-preflight.sh                   # local mirror of PR freshness, policy, tests, coverage, and native scenarios
```

Shell dependency drift is watched by **Shell Dependency Watch**. The workflow runs
daily, on demand, and from `repository_dispatch`; when the shared native app shell
pin is stale, it refreshes `Package.resolved`, bumps the patch version, and opens
or updates a single refresh PR when repository permissions allow it. If GitHub
blocks PR creation, the workflow still pushes the stable automation branch and
writes the compare link plus manual `gh pr create` command to the run summary.

To ship: run `./scripts/bump-version.sh <x.y.z>` — it rewrites `OuroMDRelease.version`,
the release date, and this README status line in one shot (`make-app.sh` derives its
`VERSION` from `OuroMDRelease.swift`, so there's no third place to edit; a partial bump
is impossible). Then update `releaseHighlights` and merge to `main`. The Release workflow builds the app,
requires embedded PostHog telemetry for production direct-download publishes,
runs packaged-app probes, uploads the zip/DMG/manifest, and publishes
`v<VERSION>`. It no-ops when that tag already exists. Use workflow dispatch with
`dry_run=true` to build/probe on a GitHub macOS runner without publishing.

For a local package smoke:

```sh
./scripts/package-release.sh
./scripts/verify-packaged-app.sh OuroMD.app
./scripts/check-hosted-installer.sh         # smoke the public one-line installer URL
./scripts/check-live-update-path.sh         # smoke older published release -> latest updater path
```

For Mac App Store packaging, see [docs/APP_STORE.md](docs/APP_STORE.md). Store
builds use a separate `app-store` distribution channel: sandboxed, telemetry off,
and direct GitHub update checks disabled because the App Store owns updates.

Release builds can embed anonymous PostHog telemetry by setting
`OURO_MD_POSTHOG_KEY` and, optionally, `OURO_MD_POSTHOG_HOST` before packaging.
The script also accepts Spoonjoy-style `VITE_POSTHOG_KEY` /
`VITE_POSTHOG_HOST` environment variables so maintainers can reuse the same
project configuration without committing the key. `scripts/package-release.sh`
requires a clean git worktree and a telemetry key by default so release artifacts
do not accidentally ship uncommitted or unconfigured bytes; set
`OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY=1` only for local dry runs.

Developer-ID signing/notarization is intentionally checked as a separate
readiness gate. `scripts/check-signing-readiness.sh` verifies host tooling on
every PR and can fail closed with `OURO_REQUIRE_NOTARIZATION=1` when release
signing is enabled. Set `OURO_RELEASE_SIGNING_MODE=developer-id` to make
`scripts/package-release.sh` sign with hardened runtime, submit to Apple's
notary service, staple the ticket, and mark the manifest as
`"signingMode": "developer-id"` / `"notarized": true`. Leave it unset for
ad-hoc dry runs. Set `OURO_VALIDATE_NOTARY_CREDENTIALS=1` only when a runner
should make a live notary credential call.

## Build

Requires macOS 15+ and Xcode 26 or later (Swift 6.2).

```sh
# Build and run during development
swift build
swift run ouro-md sample.md

# Run the tests
swift test

# Build a double-clickable OuroMD.app (release, ad-hoc signed)
./make-app.sh
open OuroMD.app
```

### Hosted native rendering evidence

On macOS 26 and later, the native header samples scrolling document content in
windowed and full-screen mode. Full-screen toolbar controls stay system-owned;
their detached native window receives a behind-window material and regular
glass backdrop, without extending the editing bounds beneath pinned chrome.

The **Window chrome** workflow captures the real native header with a released
flat-layout negative control. The **Native site media and accessibility**
workflow opens `Tests/Fixtures/Launch plan.md` in a real committed sample
repository, with the sidebar closed and larger native editor text. It captures
reading, native human feedback with autosave, then an external agent-style edit
of that same saved file with margin marks and Next change. Committed and Modified
are asserted against both the real Git provider and native toolbar text. The
Intel job requires the published release's production source and OCR-readable
document content—not just editor readiness or a WK snapshot.
Per-frame timestamps and UI state accompany the PNGs for authentic GIF export.
The plan's original fictional route sketch is ordinary document imagery,
not replacement app UI. The media job selects non-reduced motion/transparency
settings on its disposable runner and verifies the actual native signals;
`scripts/run-hosted-native-proof.sh` restores the original keys afterwards.

These interactive tests require both `GITHUB_ACTIONS=true` and their explicit
workflow opt-in. They skip before presenting a window on an ordinary developer
Mac. The accessibility job restores the original preference keys, records
actual NSWorkspace/WebKit propagation and live-change attempts, and distinguishes
native AX exposure from VoiceOver traversal. Native Paste also checks steady
versus fading feedback under the actual Reduce Motion setting. Failed propagation is reported as
unverified, never replaced with a synthetic media-query override. macOS 27
on-screen/per-window capture comparisons are diagnostics until the native
document body demonstrably paints; blank bodies are not publication assets or
platform glass qualification.

### CI runners

Pull requests run only on GitHub's free standard runners (`macos-26`, `macos-26-intel`, `macos-15`). The billed
`xcode-27` runner is for checks that truly need Xcode 27 and the macOS 27 SDK the app ships with, and runs only on
pushes to `main` and for releases: the **Xcode 27 SDK** job in `ci.yml` and the harness and release jobs in
`release.yml`. They select Xcode 27.2 (`/Applications/Xcode_27.2.app`), the same SDK as local builds: the image's
`Xcode_27.app` is 27.0, whose macOS 27.0 SDK lacks APIs Ouro HX uses from 27.1. On the 2026-10-26 image that
path is the 27.2 release candidate (27B48); it builds only main-branch checks and releases, which are Developer ID
direct downloads, so App Store rules on release-candidate Xcodes don't apply. Prefer a final `Xcode_27.2.app` once the
image carries one. `scripts/check-ci-runners.py` fails CI if a pull request job could use it. Code that needs a newer SDK
than the free image's must be fenced with `canImport(..., _version:)`, as ouro-ui-apple does, so it compiles to nothing
there. A $15-a-month GitHub Actions budget scoped to `ourostack/ouro-md` stops further billed use when reached and
alerts `arimendelow`.

When the free macOS image carries Xcode 27:

1. Delete the `xcode-27-sdk` job in `ci.yml`, or move it to that image if its SDK check is still worth running.
2. In `release.yml`, change `runs-on: xcode-27` to that image and delete the `Select Xcode 27.2` steps.
3. Delete this repository's Actions budget if no billed runner is left.

## Usage

### As an app

Open a file with **⌘O**, start a new document with **⌘N**, save with **⌘S**.
Pick a theme from the **Themes** menu, toggle the sidebar with **⇧⌘L**, and
export from **File ▸ Export**. Auto-save keeps a titled file written as you type.

### Telemetry

When configured in a release build, Ouro MD sends anonymous product telemetry to
PostHog: launches, update lifecycle events, document create/open events,
coarse save/open/rename/reload success or failure codes, folder-open events,
export success/failure, and editor crash recovery. It never sends document
contents, filenames, folder paths, search queries, or raw error messages.
Disable it in **Settings ▸ Telemetry**.
See [PRIVACY.md](PRIVACY.md) for the full telemetry contract.

During dogfood, telemetry should tell a complete content-free story for launch,
update, open, save, rename, external reload, folder-open, export, and editor
crash-recovery flows. If telemetry is enabled and something feels wrong, include the
approximate local time in bug reports so maintainers can match coarse event
status without needing document contents.

### Keyboard shortcuts

| Shortcut            | Action |
|:--------------------|:-------|
| ⌘N / ⌘O / ⌘S / ⇧⌘S  | New / Open / Save / Save As |
| ⇧⌘L                 | Toggle sidebar |
| ⌃⌘1 / ⌃⌘3           | Sidebar: Outline / File Tree |
| ⇧⌘F                 | Find |
| ⌘/                  | Source Code Mode |
| F8 / F9             | Focus / Typewriter mode |
| ⌘B / ⌘I / ⌃⌘S       | Bold / Italic / Strikethrough |
| ⌘E / ⌘K             | Inline code / Insert link |
| ⌘1…⌘6 / ⌘0          | Heading 1–6 / Paragraph |
| ⇧⌘0 / ⇧⌘= / ⇧⌘-     | Actual size / Zoom in / out |
| ⌃⌘F                 | Full screen |

### From the command line

```sh
ouro-md notes.md                      # open in the editor
ouro-md --render notes.md > out.html  # render to a themed HTML document
ouro-md --render notes.md --theme graphite > out.html
ouro-md --list-themes
ouro-md --mcp --root ~/notes            # serve ~/notes to an agent over MCP (stdio)
ouro-md --help
```

## Custom themes

Drop a `.css` file into:

```
~/Library/Application Support/ouro-md/Themes/
```

It appears in the **Themes** menu by file name (a file containing `dark` or
`night` in its name is treated as a dark theme). Built-in themes style the
standalone export (`.markdown-body`) and the live editor (`.vditor-reset`) from
a shared palette; custom CSS is applied to both.

## Siri, Shortcuts and agents

Ouro MD's App Intents (`Sources/OuroMD/DocumentIntents.swift`) let Siri, Shortcuts and Spotlight open, read, add to
and replace your Markdown documents. They follow [Ouro AX for Apple](https://github.com/ourostack/ouro-ui-apple):

- **One implementation.** `Sources/OuroMD/DocumentActions.swift` does the work and returns an `OuroAX.Outcome`; the
  intents speak its summary, and a refusal is an `OuroAX.Problem` whose fix says what to do next.
- **Replace asks first.** Replacing a whole document asks you to confirm; adding to one doesn't, and either is one
  undo in an open window.
- **App skills.** `Resources/Skills.skillsbundle` tells Siri how to use the intents (macOS 27.3 and later).
- **The X-ray.** CI's `AX X-ray` job builds the app, runs ouro-ui-apple's `ouro-ax-xray` on it and checks the result
  against `config/xray-expected.json`, which lists each claim that holds and why each other one can't yet.

### Agents over MCP

`ouro-md --mcp --root <folder>` serves the Markdown documents under a folder to an agent over MCP (stdio), with four
tools: `list_documents`, `read_document`, `append_to_document` and `replace_document`. They run the same code as the
intents, and `replace_document` changes nothing until the agent sends `confirmed: true` after you've said yes. Nothing
outside the `--root` folders is listed, read or written. For Claude Code:

```sh
claude mcp add ouro-md -- "/Applications/Ouro MD.app/Contents/MacOS/ouro-md" --mcp --root ~/Documents/notes
```

It needs the direct-download app; the App Store build is sandboxed. Decisions and prior art:
[docs/mcp-door.md](docs/mcp-door.md).

### Siri AI

The Siri AI Developer Preview needs the Xcode 27.3 beta SDK. Until Ouro MD builds with it, two things compile to
nothing, behind `#if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)`: the intents' `ToolIntent`
conformances (so Siri can call them as tools) and the descriptions on the document's properties. Once CI's image has
27.3, move `intent.tool` and `entity.property-description` to `hold` in `config/xray-expected.json`.

## Architecture

ouro-md is a native SwiftUI/AppKit shell around a WKWebView editing surface,
with document chrome, menus, file handling, and validation built for macOS.

- **Swift shell** (`Sources/OuroMD/*.swift`) — window, menu bar, file model
  (open/save/dirty tracking), theming, export, and the JS bridge.
- **Web editor** (`Sources/OuroMD/web/`) — [Vditor](https://github.com/Vanessa219/vditor)
  in instant-rendering mode, plus `bridge.js` connecting it to the app.
- **Markdown core** (`MarkdownRenderer.swift`) — an
  [swift-markdown](https://github.com/apple/swift-markdown) AST→HTML renderer
  powering `--render` and export. Pure and unit-tested.

## Roadmap

- Enable Developer-ID signed public artifacts once Apple renewal/certificates are active
- Smart typography (curly quotes, dashes) and clickable task checkboxes
- Editor display of pre-existing relative-path local images (paste/drop already inlines)
- Higher-contrast tables in the dark theme
- Paginated PDF export and print

See [docs/V1_ACCEPTANCE.md](docs/V1_ACCEPTANCE.md) for the current human-use
readiness checklist and known non-goals.

## License

ouro-md is released under the [MIT License](LICENSE). Third-party components and
attributions are listed in [NOTICE](NOTICE).
