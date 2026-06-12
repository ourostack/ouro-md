# ouro-md

A minimalist, beautiful, themable Markdown editor that's native to macOS.

ouro-md keeps the chrome out of your way: no busy toolbar, just your words set
in careful typography on a centered page. Type Markdown and watch it render in
place — switch themes live, and read the same document four different ways.

> **Status:** v0.1.0. Reads and edits Markdown today. Not yet Developer-ID
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

```sh
./install.sh            # build + install to /Applications/Ouro MD.app
./install.sh --update   # git pull, then rebuild + reinstall (use this to update)
```

- **Where it lives:** `/Applications/Ouro MD.app`
- **How to launch:** double-click in Finder · `open -a "Ouro MD"` · or the `md`
  shell alias (`alias md='open -a "Ouro MD"'`) → `md notes.md`
- **How to update:** re-run `./install.sh --update` any time. (Once the app is
  Developer-ID signed, this becomes a signed/notarized build and Sparkle
  auto-update can replace the manual step.)

The app is currently **unsigned** (ad-hoc), so `install.sh` clears the
quarantine flag and re-registers it with Launch Services. A fresh manual copy
into `/Applications` would otherwise trip Gatekeeper on first launch.

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

ouro-md is a native SwiftUI/AppKit shell around a WKWebView editing surface —
the same architecture Typora-style editors use, made to feel like a Mac app.

- **Swift shell** (`Sources/OuroMD/*.swift`) — window, menu bar, file model
  (open/save/dirty tracking), theming, export, and the JS bridge.
- **Web editor** (`Sources/OuroMD/web/`) — [Vditor](https://github.com/Vanessa219/vditor)
  in instant-rendering mode, plus `bridge.js` connecting it to the app.
- **Markdown core** (`MarkdownRenderer.swift`) — an
  [swift-markdown](https://github.com/apple/swift-markdown) AST→HTML renderer
  powering `--render` and export. Pure and unit-tested.

## Roadmap

- Developer-ID signing + notarization
- Smart typography (curly quotes, dashes) and clickable task checkboxes
- Editor display of pre-existing relative-path local images (paste/drop already inlines)
- Higher-contrast tables in the dark theme
- Paginated PDF export and print

## License

ouro-md is released under the [MIT License](LICENSE). Third-party components and
attributions are listed in [NOTICE](NOTICE). ouro-md is an independent project
and is not affiliated with or derived from Typora.
