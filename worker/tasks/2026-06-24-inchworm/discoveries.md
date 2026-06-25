# Inch-worm backlog — ouro-md (campaign started 2026-06-24)

Canonical backlog for the open inch-worm campaign. Append-only except for `Status`
updates. New discoveries get the next `D-00n` id.

---

## [D-001] — App version is triplicated; a bump can't be made atomically

**Source**: observed-during-seed (self-observed during the v0.9.36 release this session)
**What**: The app version is hand-maintained in three places — `Sources/OuroMDCore/OuroMDRelease.swift` (`version = "x.y.z"`), `make-app.sh` (`VERSION="x.y.z"`), and `README.md` (`> **Status:** vx.y.z`) — enforced only by `scripts/verify-release-version.sh`, which fails *after* the fact in CI.
**Where**: `make-app.sh:15`, `Sources/OuroMDCore/OuroMDRelease.swift:7`, `README.md:9`, `scripts/verify-release-version.sh`.
**Why it matters**: During the v0.9.36 release the bump was partial — CI failed once on `make-app.sh`, then again on `README.md`, two wasted ~4-minute CI cycles. The build script (`make-app.sh`) is the most-forgettable pin.
**Evidence**: PR #46 CI run 28131695466 failed with `version mismatch: make-app.sh=0.9.35 OuroMDRelease.swift=0.9.36`, then again on `README=0.9.35`. `scripts/readiness-stress.sh:6` already derives the version from `OuroMDRelease.swift`, so that file is the de-facto source of truth.
**Severity**: high-value
**Blast radius**: affects one module (release tooling)
**Fix shape**: Make `OuroMDRelease.swift` the single source of truth; have `make-app.sh` derive `VERSION` from it (matching `readiness-stress.sh`); update `verify-release-version.sh` to guard that make-app *stays* a derivation and that the README matches. Removes the most error-prone pin.
**Verification**: `./scripts/verify-release-version.sh`, `./scripts/verify-release-version.sh --print`, a simulated partial bump must fail, `bash -n make-app.sh scripts/verify-release-version.sh`, `./scripts/pr-preflight.sh`.
**Status**: fixed
**Linked work**: PR #47 (squash `2de6b45`), shipped v0.9.37.
**Notes**: README can't derive at build time (static docs), so it remains a manual pin — the bump-helper follow-up (see D-002) closes that gap.

---

## [D-002] — No single command to bump the version; README still hand-edited

**Source**: observed-during-seed (logged while fixing D-001)
**What**: Even after D-001 makes `make-app.sh` derive its version, a release bump still requires editing `OuroMDRelease.swift` (version + `releaseDate` + `releaseHighlights`) and the `README.md` status line by hand — two human edits that can still go out of sync.
**Where**: `Sources/OuroMDCore/OuroMDRelease.swift:7,9`, `README.md:9`.
**Why it matters**: The README is the one remaining manual pin; `verify-release-version.sh` catches a mismatch only after the fact. A `scripts/bump-version.sh x.y.z` that updates the Swift constant + `releaseDate` + README atomically would make a partial bump structurally impossible.
**Severity**: nice-to-have
**Blast radius**: self-contained (release tooling)
**Fix shape**: Add `scripts/bump-version.sh <semver>` that rewrites `OuroMDRelease.version`, sets `releaseDate` to today, and rewrites the README status line; document it in the maintainer/release section. Leave `releaseHighlights` to the human.
**Prerequisites**: D-001 (make-app derives) should land first. ✓ landed in #47.
**Verification**: `bash -n scripts/bump-version.sh`; run it on a scratch version and assert `verify-release-version.sh` passes.
**Status**: fixed
**Linked work**: branch `chore/bump-version-helper`
**Notes**: Added `scripts/bump-version.sh <x.y.z>` (rewrites OuroMDRelease.version + releaseDate + README status line atomically, then runs verify) and pointed the README maintainer section at it. Verified: rejects non-semver (exit 2), scratch bump to 0.9.99 updated all pins + verify passed + make-app derived it, reverted clean. `releaseHighlights` stays a manual edit (per-release prose). Not release-affecting (new script + README), so it ships with no version bump.

---

## [D-003] — The "read version from OuroMDRelease.swift" sed is duplicated across three scripts

**Source**: observed-during-seed (logged while fixing D-001)
**What**: After D-001, `make-app.sh`, `scripts/verify-release-version.sh`, and `scripts/readiness-stress.sh` each independently `sed`-extract `static let version = "..."` from `OuroMDRelease.swift` (with slightly different patterns — `[^"]*` vs greedy `.*`).
**Where**: `make-app.sh:15`, `scripts/verify-release-version.sh:24`, `scripts/readiness-stress.sh:6`.
**Why it matters**: Three copies of the same extraction can drift (e.g., if the Swift declaration's formatting changes, only some patterns keep matching). Low urgency — they all currently work — but it's a quiet footgun.
**Severity**: nice-to-have
**Blast radius**: affects one module (release tooling)
**Fix shape**: Extract a tiny `scripts/lib/app-version.sh` (or a `--print-source` flag on verify) that emits the Swift version, and have the three callers source it. Keep it independent of the README check so `make-app.sh` still works when the README is mid-bump.
**Severity-note**: bundle opportunistically; not worth a standalone PR unless touched anyway.
**Status**: open

---

## [D-004] — Headless test harnesses pop visible windows and steal the user's focus

**Source**: observed-during-seed (reported by the user mid-campaign, with a screenshot of a probe window taking over the screen)
**What**: ~18 CLI harnesses (`--tablewraptest`, `--undotest`, `--uisurfacetest`, etc.) each call `setActivationPolicy(.regular)` + create a `.titled` `NSWindow` (which macOS constrains back on-screen even when positioned off-screen) + `makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps: true)` — so every local run (native scenarios, pr-preflight) pops windows over the user's apps and yanks keyboard focus.
**Where**: `Sources/OuroMD/{TableWrapTest,UndoTest,UISurfaceTest,EditorSurfaceTest,...}.swift` (18 files); `Snapshot.swift`/`RoundTrip.swift` already do the gentle `.accessory` no-window thing.
**Why it matters**: Makes the test suite hostile to run on a machine the human is using; also caused a real flake — `tablewraptest: timed out` in a local preflight when the user reclaimed focus and WebKit throttled the (then focus-dependent) render.
**Evidence**: User screenshot of a "Dogfood Tables" probe window floating over iMessage/browser; the v0.9.37 preflight failed only on `tablewraptest: timed out`.
**Severity**: high-value
**Blast radius**: affects one module (test harnesses)
**Fix shape**: Add a shared `HeadlessHarness` (`.accessory` + an off-screen, borderless, key-capable `HeadlessHostWindow` that refuses the on-screen constraint); migrate every harness to it and drop `NSApp.activate(...)`. Proven on TableWrapTest (renders + measures correctly, off-screen, no focus theft). Verify the whole set via one `run-native-scenarios.sh` once all are migrated.
**Verification**: `swift build`; `./scripts/run-native-scenarios.sh` EXIT 0 with no on-screen windows; spot-run a couple of harnesses.
**Status**: fixed
**Linked work**: branch `chore/headless-test-harnesses`
**Notes**: Render/measure harnesses use `HeadlessHarness.offscreenHost` (off-screen, no activation — fully headless). Input/focus harnesses (undo, copy, editor paste/drop, selection blur, search reveal) need WebKit to grant the editable DOM focus, which only happens when the window is on a real screen AND the app is active — so they use `HeadlessHarness.offscreenHostActive`, a transparent (alpha 0), click-through, on-screen window plus `NSApp.activate`. Net effect: no visible windows ever; only a brief app-activation/focus blip for the handful of focus-dependent probes. Verified: `run-native-scenarios.sh` EXIT 0, 21 scenarios / 154 checks, no window pop-ups.

---

## [D-005] — README maintainer note still says to bump the version in make-app.sh

**Source**: observed-during-seed (spotted while bumping the README for the headless release)
**What**: After D-001 made `make-app.sh` *derive* its version, the README "Cutting a release" section still instructed maintainers to "bump `VERSION` in `make-app.sh`, `OuroMDRelease.version`, and this README" — but `verify-release-version.sh` now *rejects* a hardcoded `VERSION=` in make-app.sh, so following the doc would fail the build.
**Where**: `README.md` (maintainer "Cutting a release" section).
**Why it matters**: Actively-wrong release instructions; a maintainer following them re-hardcodes make-app.sh and trips the guard.
**Severity**: nice-to-have
**Blast radius**: self-contained (docs)
**Fix shape**: One-line doc correction — bump only `OuroMDRelease.version` + the README status line; note make-app derives.
**Status**: fixed
**Linked work**: fixed inline in the headless PR (README was already being edited for the version bump).
**Notes**: Should ideally have ridden along with #47; folded here as an incidental doc fix in a file already touched.

---
