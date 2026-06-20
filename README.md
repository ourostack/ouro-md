# ouro-md

A minimalist, beautiful, themable Markdown editor that's native to macOS.

ouro-md keeps the chrome out of your way: no busy toolbar, just your words set
in careful typography on a centered page. Type Markdown and watch it render in
place — switch themes live, and read the same document four different ways.

> **Status:** v0.9.8. Reads and edits Markdown today. Not yet Developer-ID
> signed or notarized — see [First launch](#first-launch).

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
- **Native macOS.** A real `.app` with a transparent titlebar + centered
  filename, the standard menu bar, Open Recent, unsaved-changes prompts,
  drag-to-open, and **auto-save** for titled files.
- **Sidebar.** A collapsible sidebar (**⇧⌘L**) with a live document **Outline**
  (**⌃⌘1**) and a **File Tree** (**⌃⌘3**) of the current folder.
- **Modes & tools.** **Source Code Mode** (**⌘/**), **Focus** (**F8**) and
  **Typewriter** (**F9**) modes, **Find** (**⇧⌘F**), and a word-count popover
  (**View ▸ Toggle Word Count**).
- **Export.** Save to themed, self-contained **HTML** or **PDF**.
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
`/Applications` (falls back to `~/Applications`), clears the download quarantine,
and opens it. macOS-only; needs just `curl`, `ditto`, `shasum`. Re-run it any
time to update to the latest release, or use **Ouro MD ▸ Check for Updates...**
inside the app.

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

The app is currently **unsigned** (ad-hoc), so the installer clears the
quarantine flag and re-registers it with Launch Services — a plain copy into
`/Applications` would otherwise trip Gatekeeper on first launch. Ouro MD also
checks for verified releases in the background by default; disable automatic
checks in **Settings** if you prefer to update manually.

For uninstall/reset steps, see [docs/UNINSTALL_RESET.md](docs/UNINSTALL_RESET.md).
For install or update problems, see
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

### Cutting a release (maintainers)

```sh
./scripts/check-release-secrets.sh          # confirms GitHub release telemetry secrets exist
./scripts/verify-release-version.sh         # make-app.sh / OuroMDRelease.swift / README agree
```

To ship: bump `VERSION` in `make-app.sh`, `OuroMDRelease.version`, and this
README status line, then merge to `main`. The Release workflow builds the app,
requires embedded PostHog telemetry for production publishes, runs packaged-app
probes, uploads the zip/manifest, and publishes `v<VERSION>`. It no-ops when that
tag already exists. Use workflow dispatch with `dry_run=true` to build/probe on a
GitHub macOS runner without publishing.

For a local package smoke:

```sh
./scripts/package-release.sh
./scripts/verify-packaged-app.sh OuroMD.app
```

Release builds can embed anonymous PostHog telemetry by setting
`OURO_MD_POSTHOG_KEY` and, optionally, `OURO_MD_POSTHOG_HOST` before packaging.
The script also accepts Spoonjoy-style `VITE_POSTHOG_KEY` /
`VITE_POSTHOG_HOST` environment variables so maintainers can reuse the same
project configuration without committing the key. `scripts/package-release.sh`
requires a clean git worktree and a telemetry key by default so release artifacts
do not accidentally ship uncommitted or unconfigured bytes; set
`OURO_MD_ALLOW_UNCONFIGURED_TELEMETRY=1` only for local dry runs.

## Build

Requires macOS 13+ and a recent Swift toolchain (Xcode 15+ / Swift 5.9+).

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

- Post-dogfood Developer-ID signing + notarization
- Smart typography (curly quotes, dashes) and clickable task checkboxes
- Editor display of pre-existing relative-path local images (paste/drop already inlines)
- Higher-contrast tables in the dark theme
- Paginated PDF export and print

See [docs/V1_ACCEPTANCE.md](docs/V1_ACCEPTANCE.md) for the current human-use
readiness checklist and known non-goals.

## License

ouro-md is released under the [MIT License](LICENSE). Third-party components and
attributions are listed in [NOTICE](NOTICE). ouro-md is an independent project.
