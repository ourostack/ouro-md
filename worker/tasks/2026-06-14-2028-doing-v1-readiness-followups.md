# Doing: Ouro MD V1 Readiness Follow-Ups

**Status**: done
**Execution Mode**: direct
**Created**: 2026-06-14 20:28 PDT
**Artifacts**: ./2026-06-14-2028-doing-v1-readiness-followups/

> Closeout note (2026-06-25): this follow-up shipped in PR #3
> (`https://github.com/ourostack/ouro-md/pull/3`), merge
> `636a1c814840cae880a85714c7e08339679b46e2`, and release `v0.9.2`.
> The folder-scan performance item is now closed in the audit backlog.

## Objective
Complete the remaining dogfood-readiness follow-ups from the Desk task's `Next`
section without adding licensing/payment work or Developer ID signing/notarization.

## Scope
- Performance follow-up: eliminate duplicate recursive folder scans for tree and
  flat views.
- Polish backlog: CLI footnote rendering and native menu item validation.
- Release/telemetry follow-up: publish a 0.9.2 build configured with the same
  PostHog project used by Spoonjoy.
- Trust follow-up discovered during verification: preserve byte-identical
  round trips when the editor only applies known benign Markdown normalization.

## Explicit No-Op
- Hiding raw GFM alert markers in the live editor remains deferred. A CSS-only
  approach cannot safely hide source text in a contenteditable editor, and DOM
  mutation risks corrupting editable Markdown unless verified in the live UI.

## Progress Log
- 2026-06-14 20:28 Started follow-up execution from Desk `v1-editor` Next section.
- 2026-06-14 20:28 Implemented single-pass folder scan snapshot API with targeted
  tests.
- 2026-06-14 20:28 Implemented CLI footnote preprocessing/rendering with fenced
  code protection and targeted tests.
- 2026-06-14 20:28 Added AppKit menu item validation coverage for windowless
  editor-only and global commands.
- 2026-06-14 20:28 Added privacy doc, telemetry documentation link, and release
  truth bump to 0.9.2.
- 2026-06-14 20:28 Fixed no-op roundtrip preservation after live `sample.md`
  roundtrip diff exposed Vditor table/blank-line normalization.
- 2026-06-14 20:38 Added missing branch coverage for folder sort/fallback and
  renderer footnote/image/HTML/line-break behavior after the changed-source
  coverage gate found real gaps.
- 2026-06-14 20:40 Local verification matrix passed through tests, release build,
  coverage export/check, editor harnesses, exact sample roundtrip, and CLI
  footnote smoke; logs saved in this artifact directory.

## Verification Matrix
- [x] `swift test`
- [x] `swift build -c release`
- [x] `swift test --enable-code-coverage`
- [x] Changed-source coverage check
- [x] `swift run ouro-md --undotest`
- [x] `swift run ouro-md --wraptest`
- [x] `swift run ouro-md --renderprobe`
- [x] `swift run ouro-md --roundtrip sample.md`
- [x] CLI footnote smoke
- [x] Package release with embedded PostHog configuration
- [x] Publish GitHub release `v0.9.2`
- [x] Live installer smoke from `https://ouro.bot/ouro-md-install.sh`
- [x] In-app update path smoke from `v0.9.1` to `v0.9.2`
- [x] Harsh cold reviewer gate
