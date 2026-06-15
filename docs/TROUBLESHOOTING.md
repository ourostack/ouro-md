# Troubleshooting

Use this page when Ouro MD behaves differently than expected during dogfood or
early open-source use. Ouro MD is local-first: the fastest useful report usually
has the app version, macOS version, the exact action that failed, and whether the
problem repeats after relaunch.

## First Launch

Ouro MD is currently ad-hoc signed, not Developer-ID signed or notarized. The
recommended installer clears quarantine for the downloaded app:

```sh
curl -fsSL https://ouro.bot/ouro-md-install.sh | bash
```

If the app was copied manually and macOS blocks it, remove quarantine from the
installed bundle:

```sh
xattr -dr com.apple.quarantine "/Applications/Ouro MD.app"
```

If the app is installed in `~/Applications`, use that path instead.

## Update Problems

Use **Ouro MD -> Check for Updates...** or rerun the installer. The updater and
installer both verify the release manifest checksum before installing.

Useful checks:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "/Applications/Ouro MD.app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "/Applications/Ouro MD.app"
```

For installer issues, include the terminal output from:

```sh
curl -fsSL https://ouro.bot/ouro-md-install.sh | OURO_MD_NO_OPEN=1 bash
```

## Save, Reload, Or File Tree Issues

When a document is already saved to disk, Ouro MD auto-saves after edits. If an
external tool changes the same file, Ouro MD reloads it when there are no local
edits and asks before replacing unsaved local edits.

For reports, include:

- Whether the document was new/untitled or already saved.
- Whether another editor, script, or sync tool touched the file.
- The visible prompt or error text.
- Whether **File -> Save** succeeds immediately afterward.

Do not attach private document contents unless you intentionally create a small
reproduction file.

## Rendering Or Export Differences

The app supports CommonMark plus GFM tables, task lists, strikethrough, fenced
code highlighting, math, footnotes, and diagrams. If the editor view, exported
HTML, exported PDF, and command-line render disagree, that is a useful bug.

Useful local probes from a source checkout:

```sh
swift run ouro-md --render sample.md > /tmp/ouro-md-sample.html
swift run ouro-md --renderprobe
swift run ouro-md --shoot sample.md --out /tmp/ouro-md-sample.png
```

Attach the smallest markdown snippet that reproduces the mismatch.

## Keyboard Shortcuts

Undo/redo, formatting, find, sidebar toggles, and mode switches are covered by
unit tests and headless WebView probes. If a shortcut fails, include:

- Keyboard layout and whether another app-level shortcut is intercepting it.
- The focused area: editor, sidebar, title field, find panel, or settings.
- Whether the menu item works when clicked.

From a source checkout, these probes should pass:

```sh
swift run ouro-md --undotest
swift run ouro-md --wraptest
```

## Performance Notes

The readiness stress harness covers:

- A folder containing more than 5,000 markdown files.
- A roughly 550 KB editor roundtrip through the live WebView.
- A roughly 3.9 MB command-line render.
- A rendered editor screenshot fixture.

Known current boundary: multi-megabyte live-editor roundtrip is not a v1 claim.
If ordinary notes feel slow, include file size, folder size, and the action that
felt slow.

The folder sidebar and folder search intentionally cap scans at the first 5,000
openable files to keep the UI responsive. Ouro MD shows a warning when a scan is
truncated; narrow the folder or search path if the omitted files matter.

## Telemetry

Release builds may send anonymous product telemetry when packaged with a PostHog
key. Events are intended to explain product health, not document content. They
include launch/update lifecycle, document create/open/save/rename/reload coarse
codes, folder-open, export, and crash recovery events.

Telemetry does not include document contents, filenames, folder paths, search
queries, clipboard contents, or raw error strings. Disable it in
**Ouro MD -> Settings -> Telemetry**.

See [../PRIVACY.md](../PRIVACY.md) for the complete contract.
