# V1 Acceptance Checklist

This checklist defines what "ready for ordinary human dogfood" means for Ouro MD
before the deferred Developer-ID/notarization pass. It intentionally excludes
licensing and paid-hosting decisions.

## Product Surface

- Create, open, edit, save, save-as, rename, and reopen markdown files.
- Auto-save titled files without losing unsaved local edits.
- Detect external file changes and reload or preserve local edits predictably.
- Undo/redo and common formatting shortcuts work from the editor focus state.
- Sidebar outline and file tree remain responsive on large-but-normal folders.
- Export to HTML and PDF without document-content telemetry.

## Install And Update

- One-line installer downloads the latest release, validates checksum, installs,
  clears quarantine, and can be rerun safely.
- In-app updater discovers the newest published GitHub release, validates the
  manifest, stages the app, and applies on quit or relaunch.
- Release packaging refuses dirty worktrees and unconfigured telemetry unless a
  maintainer explicitly opts into a local dry run.

## Telemetry

- Release telemetry is opt-out and disabled when no key is embedded.
- Events are content-free and avoid filenames, paths, search terms, clipboard
  contents, and raw error strings.
- Dogfood-critical flows emit enough coarse status to debug launch, update,
  open, save, rename, reload, folder-open, export, and crash recovery behavior.
- Tests assert payload shape and sensitive-data absence for representative
  document lifecycle events.

## Stress Coverage

- Full `swift test` passes from a clean checkout.
- Release package dry run produces a zip and manifest with the expected version.
- Large-folder browser test covers more than 5,000 markdown files.
- Live editor roundtrip covers a roughly 550 KB document.
- Command-line render covers a roughly 3.9 MB markdown document.
- Headless editor probes cover undo/redo, wrapping shortcuts, rendering, and a
  screenshot smoke.

## Current Non-Goals

- Developer-ID signing and notarization.
- Paid hosting, team sync, accounts, or cloud storage.
- Multi-megabyte live-editor roundtrip guarantees.
- Displaying pre-existing relative-path local images in the editor.
- Paginated print-quality PDF layout.
