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
- **Native macOS.** A real `.app` with a transparent full-height titlebar, the
  standard menu bar, Open Recent, unsaved-changes prompts, and drag-to-open.
- **Export.** Save to themed, self-contained **HTML** or **PDF**.
- **Images that just work.** Pasted or dropped images are embedded inline (as
  data URIs) — no upload server, no broken links.
- **Headless render.** `ouro-md --render file.md` prints a styled HTML document
  to stdout for scripting and previews.

## First launch

The app is currently **unsigned** (ad-hoc signed). On first launch macOS
Gatekeeper will warn you. Either right-click the app and choose **Open**, or:

```sh
xattr -dr com.apple.quarantine OuroMD.app
open OuroMD.app
```

Developer-ID signing + notarization are planned.

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
Switch themes from **View ▸ Theme** and editing modes from
**View ▸ Editing Mode**. Export from **File ▸ Export**.

### Keyboard shortcuts

| Shortcut          | Action            |
|:------------------|:------------------|
| ⌘N / ⌘O / ⌘S / ⇧⌘S | New / Open / Save / Save As |
| ⌘B / ⌘I           | Bold / Italic     |
| ⌃⌘S / ⌘E          | Strikethrough / Inline code |
| ⌘K                | Insert link       |
| ⌥⌘O               | Toggle outline    |
| ⌘0 / ⌘+ / ⌘-      | Actual size / Zoom in / out |
| ⌃⌘F               | Full screen       |

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

It appears in **View ▸ Theme** by file name (a file containing `dark` in its
name is treated as a dark theme). Built-in themes style the standalone export
(`.markdown-body`) and the live editor (`.vditor-reset`) from a shared palette;
custom CSS is applied to both.

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
- Find & replace
- Local relative-image display in the editor (paste/drop already inlines)
- File-tree sidebar and multi-tab documents
- Paginated PDF export and print

## License

ouro-md is released under the [MIT License](LICENSE). Third-party components and
attributions are listed in [NOTICE](NOTICE). ouro-md is an independent project
and is not affiliated with or derived from Typora.
