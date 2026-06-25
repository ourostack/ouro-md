# Anneal campaign — OuroMDCore text/escaping core

**Skill**: `anneal` (dogfood run #1, driven by the ouro-md agent at Ari's request)
**Started**: 2026-06-25
**Status**: annealed

> This is the resumable journal (anneal §5). Every iteration's energy, the PERT graph,
> and the backlog live here and are committed each iteration. A reboot must not lose
> the descent.

---

## Scope (S)

`Sources/OuroMDCore/HTMLDocument.swift` + `Sources/OuroMDCore/MarkdownTidy.swift`
and their tests (`Tests/OuroMDTests/HTMLDocumentTests.swift`, `MarkdownTidyTests.swift`).

Chosen because it's small (~142 logic lines), pure (no GUI/IO in the logic), already
under the 100%-coverage gate (so the P1 baseline is known), and security-relevant
(`HTMLDocument.escape`/`escapeAttr` is the Markdown→HTML escaping surface). That makes
it the right scope to dogfood anneal's *harder* criteria — P2 (non-vacuity), P3
(determinism), and P5 (adversarial review) — i.e. finding defects **beyond** coverage.

Out of scope (recorded so it doesn't leak into the backlog): the *callers* of
`escape`/`escapeAttr` in the OuroMD app target (URL-scheme sanitization, attribute
quoting style) — those are a separate scope; here the escaper is judged only against
its **declared contexts** (element content / double-quoted attribute).

---

## Instantiated rubric

Core (every anneal run):
- **P1 — Coverage completeness.** 100% line+region for the scope (already gated for OuroMDCore).
- **P2 — Test non-vacuity.** Every behavioral invariant has a negative control: deliberately breaking it fails a test. No vacuous assertions; no fixtures the real path can't produce.
- **P3 — Determinism.** Tests produce byte-identical output across repeated runs.
- **P5 — Zero surviving defects.** ≥2 independent, perspective-diverse adversarial reviewers over S → zero surviving CRITICAL/HIGH.
- **P6 — CI integrity.** Full suite green, deterministic, clean build.

Scope-specific:
- **SEC-1 — Escaping soundness.** For its declared context, `escape` (HTML element content) and `escapeAttr` (double-quoted attribute) escape exactly the characters that could break out of that context, proven by a negative control per character. No attacker-controlled text can introduce markup/break the attribute.
- **RT-1 — Tidy soundness.** `MarkdownTidy.normalized` is (a) **idempotent** — `tidy(tidy(x)) == tidy(x)` for all x; (b) **content-preserving** outside the two declared normalizations (table-separator expansion, blank-run collapse, front-matter blank restore); (c) each declared normalization + each guard (fence, mid-doc `---`, unclosed front matter) is covered AND negatively-controlled.

### Termination
Annealed when one full audit pass over S finds zero P-violations and discovers no new
in-scope unit. Safety cap: 4 iterations / this session's budget — tripping it is a
convergence-failure report, not "good enough."

---

## Energy log

| Iteration | Energy (open violations) | Notes |
|---|---|---|
| baseline | P1 ✓ · P3 ✓ · P2/P5 pending | `check-coverage.sh`: HTMLDocument 100%, MarkdownTidy 75/75 line + 50/50 region 100%. Determinism: scope tests give identical results across runs (the runner's timing line varies but is not asserted output). P2/P5 from the audit workflow (3 adversarial reviewers, running).
| audit | **energy = 3** (AN-001, AN-002, AN-003) | 3-reviewer audit: SEC-1/P5-security CLEAN; found AN-001 (idempotency unasserted), AN-002 (HIGH: dash-guard no negative control), AN-003 (RT-1b: `- \|` rewritten — empirically confirmed real bug). AN-004 (CRLF) refuted/deferred. |
| iter-1 (AN-003 fix) | energy 3 → **1** | PR-1 (#56, shipped 0.9.43): rewrote `isTableSeparator` as a real delimiter-row check + `isDelimiterCell`; added negative controls (AN-002) + bullet/no-table tests (AN-003) + no-space-separator tests. P1 still 100% (MarkdownTidy 87/87 line, 59/59 region). **P5 gate: 2 reviewers, both approve, zero surviving CRITICAL/HIGH.** Closed AN-002+AN-003. |
| iter-2 (AN-001) | energy 1 → **0** | PR-2 (test-only): added `testTidyIsIdempotent` (RT-1a) — 8-input fixed-point assertion, passes; negative control for any non-idempotent change. Closes AN-001. |
| re-measure (read-based) | apparent 0 | After PR-1/PR-2 the read-based audit's 3 findings were closed. P1/P3/SEC-1 ✓. |
| confirm (mutation-based) | **energy = 4** (AN-005..008) | The fresh confirmation pass used **mutation testing** (delete each guard, see if a test fails) — stricter than reading — and found 4 guards with NO negative control: `~~~` fences (AN-005), front-matter first-line guard (AN-006), `prevBlank` reset on fence lines (AN-007), leading-whitespace preservation (AN-008). All were *correct-but-unpinned* (each assertion passes on current code). The apparent rise 0→4 is a **measurement-method change**, not a regression (see SF-7). Plus a deferred mixed-fence-marker parsing edge (AN-009) both confirmers declined to raise. |
| iter-3 (controls) | energy 4 → **0** | PR-3 (test-only): added 4 negative controls; **each mutation-verified to FIRE** (break the guard → its test fails). 231 tests green, P1 100%. Closes AN-005..008. |
| mechanical sweep | **energy = 1** (AN-010) | Replaced the racy multi-agent confirmation (SF-8) with a deterministic, single-actor **mechanical mutation sweep** over *every* guard/branch in `MarkdownTidy` + `HTMLDocument` (~26 mutations). It found one more uncaught guard the agent reviewers missed: the classifier's `hasPrefix("\|")` half (drop it and `--- \|` is rewritten, with no test catching it). The sweep also exposed two measurement bugs in my own harness — SF-9 (a guard mutation that *crashes* is caught, but a grep for "tests failed" misses it) and SF-10 (a mutation that fails to *compile* is inconclusive, not "uncaught") — both corrected, no real findings hidden behind them. |
| iter-4 (AN-010) | energy 1 → **0** | PR-3 amended: `testSeparatorRequiresBothBoundingPipes` pins both `--- \|` and `\| ---` unchanged; **each half mutation-verified to FIRE** (drop `hasPrefix` → leading half fails; drop `hasSuffix` → trailing half fails). 232 tests green, P1 100%. Closes AN-010. |
| re-confirm | **0 → ANNEALED** | Final mechanical sweep: **every live logic guard's mutation is caught** (assertion or crash). The only two un-caught mutations are correctly out of scope — `!cells.isEmpty` (provably dead: `split(omittingEmptySubsequences:false)` never returns empty → guard unreachable; removing it would only churn a no-op release, see SF-11) and the `baseReset` CSS constant (presentation, covered by visual-QA, not byte-pinned). P1 100% · P3 ✓ · SEC-1 ✓ · P2 energy **0**. Annealed. |

---

## PERT graph

```
AN-001 (idempotency test) ──┐  independent, test-only, no bump
AN-002 (dash-guard control)─┼─ subsumed by AN-003's tests (same root: loose classifier)
AN-003 (classifier fix) ────┘  source change → release-affecting → bump
AN-004 (CRLF) ── DEFERRED (refuted: out of instantiated rubric)
```
No prerequisites between items (independent). Critical path = AN-003 (source + gate).
Merge order (serialized): **PR-1 = AN-003 (+AN-002 controls)** → **PR-2 = AN-001**.

Energy (open rubric violations) = **3** (AN-001, AN-002, AN-003). AN-004 is not a
violation of the instantiated rubric → not counted (anti-regress).

---

## Backlog

## [AN-001] — Idempotency `tidy(tidy(x)) == tidy(x)` is never asserted
**Criterion**: P2 / RT-1(a)
**What**: RT-1(a) requires idempotency coverage; no test applies `tidy` twice.
**Where**: `Tests/OuroMDTests/MarkdownTidyTests.swift`.
**Evidence**: 2 reviewers + own grep: no nested `tidy(tidy(…))`. Verified empirically tidy IS idempotent over 7+ inputs (the assertion passes on current code) → coverage gap, not a live defect.
**Severity**: nice-to-have
**Blast radius**: self-contained (test-only)
**Fix shape**: Add a test asserting `tidy(tidy(x))==tidy(x)` over a battery (tables, blank runs, front matter, fences, plain). Negative control: a non-idempotent change fails it.
**Prerequisites**: none.
**Status**: fixed (PR-2, test-only)

## [AN-002] — `isTableSeparator`'s `contains("-")` guard has no negative control
**Criterion**: P2
**What**: Deleting the dash clause breaks zero tests; no test pins that a pipe-bearing dash-free line (`| : | : |`) is left unchanged.
**Where**: `Sources/OuroMDCore/MarkdownTidy.swift:70`; tests missing.
**Evidence**: Reviewer 2 (HIGH); empirically `tidy("| : | : |")=="| : | : |"` passes on current code (guard correct, just unpinned).
**Severity**: high-value
**Blast radius**: self-contained
**Fix shape**: Add negative-control tests; subsumed by AN-003's stricter classifier + tests.
**Prerequisites**: none (folds into AN-003).
**Status**: fixed (PR-1, gated)

## [AN-003] — `isTableSeparator` misclassifies non-table lines → silent content rewrite
**Criterion**: RT-1(b)
**What**: A bullet/line like `- |` or `- | -` (only `|:- \t` chars, has a pipe and a dash) is classified as a table separator and rewritten to `| --- |`, changing content of a non-table line on save.
**Where**: `Sources/OuroMDCore/MarkdownTidy.swift:69-71`.
**Evidence**: Empirically verified on the real function: `tidy("- |")=="| --- |"`, `tidy("- | -")=="| --- | --- |"` (test failed on current code).
**Severity**: high-value (silent content corruption, rare input)
**Blast radius**: one module
**Fix shape**: Replace the loose char-set heuristic with a real GFM delimiter-row check — require leading+trailing `|`, split on `|`, every cell matches `:?-+:?`. Verified to keep every real separator expanding and reject `- |`/`- | -`/`| : | : |`. Add tests for both directions.
**Prerequisites**: none.
**Status**: fixed (PR-1, gated by 2 reviewers, both approve)

## [AN-004] — Normalizations no-op on CRLF input — DEFERRED (refuted)
**Criterion**: (claimed RT-1) — judged NOT a violation of the instantiated rubric.
**What**: On `\r\n` input the separator/front-matter normalizations silently don't fire (trailing `\r` defeats the char checks).
**Where**: `Sources/OuroMDCore/MarkdownTidy.swift:24,29,57`.
**Evidence**: `tidy("| A |\r\n| - |\r\n| 1 |")` returns input unchanged. **But content is preserved (no data loss)**, and the declared input is the editor's `\n` output — CRLF handling is a *speculative extension*, not a violation of RT-1 as instantiated.
**Severity**: trivia
**Status**: deferred — a deliberate rubric extension if ever wanted; out of this run's energy (anti-regress §1).

## [AN-005] — `~~~` (tilde) fenced-code blocks have no negative control
**Criterion**: P2 / RT-1(c) · **Where**: `MarkdownTidy.swift:30`; tests. · **Evidence**: mutation — drop the `~~~` arm, all tests stay green. The guard is correct (tilde-fenced content is preserved); just unpinned. · **Fix shape**: add `testDoesNotTouchTildeFencedCode`. · **Status**: fixed (PR-3, mutation-verified to fire)

## [AN-006] — Front-matter first-line guard (`lines.first == "---"`) has no negative control
**Criterion**: P2 / RT-1(b) · **Where**: `MarkdownTidy.swift:57`. · **Evidence**: mutation — relax to `!= nil`, all tests stay green; the existing mid-doc test is blind because its `---` is already blank-surrounded (other guard short-circuits). · **Fix shape**: assert `tidy("# Title\n---\nMore")` unchanged. · **Status**: fixed (PR-3, mutation-verified)

## [AN-007] — `prevBlank=false` reset on a fence line has no negative control
**Criterion**: P2 / RT-1(b) · **Where**: `MarkdownTidy.swift:33`. · **Evidence**: mutation — remove the reset, all tests stay green; no test has a blank both before a fence-open and after a fence-close. · **Fix shape**: assert `tidy("a\n\n```\ncode\n```\n\nb")` unchanged. · **Status**: fixed (PR-3, mutation-verified)

## [AN-008] — Leading-whitespace preservation in `expandTableSeparator` has no negative control
**Criterion**: P2 / RT-1(b) · **Where**: `MarkdownTidy.swift:74`. · **Evidence**: mutation — set `leading=""`, all tests stay green; no indented-separator test. · **Fix shape**: assert `tidy("  | - | - |") == "  | --- | --- |"`. · **Status**: fixed (PR-3, mutation-verified)

## [AN-009] — Single-flag `inFence` mishandles mixed fence markers — DEFERRED
**Criterion**: (claimed RT-1b) — both confirmers explicitly declined to raise it. · **What**: the `inFence` toggle fires on any ```` ``` ````/`~~~` line, so an inner `~~~` line inside a ```` ``` ```` block flips fence-state off and a following `| - | - |` (still inside the code block) gets expanded. · **Evidence**: a real CommonMark parser keeps the whole block as code. · **Severity**: low (pathological input — a code block containing a bare fence marker). · **Status**: deferred — a fence-parsing-soundness edge, not a declared normalization; fixing needs marker+length matching (a separate, larger change). Recorded; out of this run's energy per the reviewers' triage + anti-regress §1.

## [AN-010] — Separator classifier's `hasPrefix("|")` / `hasSuffix("|")` halves have no negative control
**Criterion**: P2 / RT-1(b) · **Where**: `MarkdownTidy.swift:76`. · **Found by**: the final deterministic **mechanical mutation sweep** (the agent reviewers missed it — they mutated the combined guard, not each half). · **Evidence**: drop `hasPrefix("|")` → `--- |` is rewritten; drop `hasSuffix("|")` → `| ---` is rewritten; both stayed green under the existing suite. Each half is independently load-bearing. · **Fix shape**: `testSeparatorRequiresBothBoundingPipes` — assert `tidy("--- |") == "--- |"` and `tidy("| ---") == "| ---"`. · **Status**: fixed (PR-3, both halves mutation-verified to fire).

## [AN-011] — `isTableSeparator`'s `!cells.isEmpty` guard is provably dead — NOT a violation
**Criterion**: classification call (P2). · **Where**: `MarkdownTidy.swift:80`. · **What**: the mechanical sweep showed removing `!cells.isEmpty &&` leaves the suite green — no negative control. But `cells` comes from `split(omittingEmptySubsequences: false)`, which *always* returns ≥1 element, so `cells.isEmpty` is unreachable and the guard can never fire. · **Why not a violation**: P2 demands controls for *load-bearing* guards; an unreachable guard protects no behavior, so there is nothing to control. Removing it is behavior-neutral — but it touches a release-relevant source file and would cut a version bump for a pure no-op, i.e. exactly the release churn we're told to avoid. · **Status**: classified dead + documented; kept. Energy contribution **0**. (See SF-11.)

---

## Skill-friction log (dogfood feedback for the anneal author)
_proposed SKILL.md improvements found while executing the playbook — collected here
rather than editing the installed copy, to avoid colliding with live edits._

- **SF-1 (P3 measurement, §1/§2-①).** "Determinism: byte-identical output across repeated runs" is right, but a naive implementation diffs the *test runner's* output and false-positives on the wall-clock timing/summary line (`Executed N tests … in 0.006 (0.010)s`). Suggest one clarifying clause: *P3 compares the test's **asserted artifacts** (snapshot files, captured stdout under test) across runs/machines — not the runner's timing or progress lines.* Hit this on the very first measure.
- **SF-2 (code-scope rubric instantiation, §1).** The worked rubric example (P4) is snapshot-centric; "discovers no new in-scope **unit**" and the scope-specific criteria took interpretation for a *pure-logic/escaping* scope (is a "unit" a function? a behavioral invariant?). A second worked example for a code/library scope (e.g. SEC/round-trip criteria as I instantiated here) would remove that ambiguity. Non-blocking — the framework generalized fine, but a code-scope exemplar would speed instantiation.
- **SF-3 (orchestrator may implement trivial items, §4).** §4 maps trivial/mechanical items to `work-doer` → review → `work-merger`. In practice the orchestrator (holding deep scope context from the audit) implementing a small mechanical fix *directly* and then running the ≥2-reviewer gate is both faster and faithful — the load-bearing invariant is the GATE, not who typed the fix. Suggest one clause: *"the orchestrator may implement a trivial item itself instead of delegating, provided the ≥2 independent-reviewer P5 gate is still run on the resulting diff."* Otherwise §4 reads as mandating a `work-doer` hop even for a 15-line change.
- **SF-4 (audit found defects beyond 100% coverage — validates the design).** Not a friction, a confirmation: the scope was already at 100% line+region coverage and looked "thoroughly tested" (19 cases), yet the adversarial audit surfaced a real silent-content-corruption bug (AN-003) and a HIGH missing-negative-control (AN-002). This is exactly the P2-over-P1 thesis in §1/P2 ("a test that cannot fail is a defect") landing in practice — worth citing as the canonical motivating example in the skill.
- **SF-5 (P2 is best MEASURED by mutation testing — the single highest-leverage addition, §2-① / P2).** The first audit *read* the tests and found 3 issues; the confirmation pass *mutated each guard and re-ran the suite* and found 4 MORE — every guard whose deletion left the suite green. Mutation testing is the operational definition of P2 ("a negative control exists iff breaking the invariant fails a test"). Suggest the Measure step compute P2 energy as **the count of guards/branches whose mutation leaves the suite green** — it's objective, exhaustive, and machine-checkable, and it's what makes "non-vacuity" measurable rather than judgmental.
- **SF-6 (the gate for a test-only negative-control item IS its mutation, §3/§4).** §3 requires ≥2 reviewers per item. For a *source* fix that's the point (catch the masked bug). But for an item whose entire purpose is to add a negative control, the load-bearing verification is the mutation check — break the targeted guard, confirm the new test fails. That's stronger and cheaper than two agents reading the test. Suggest: *"a test-only item that adds a negative control is gated by mutation (break the invariant → the new test must fail); a reviewer panel is optional for these."*
- **SF-7 (energy must be measured by a FIXED method, or the strict-descent invariant misfires, §3).** I watched measured energy go 3 → 0 → 4 across iterations — not because fixes created violations, but because the measurement got stricter (read → mutate). Under §3's literal "energy must strictly decrease per iteration; a rise is a convergence failure," that 0→4 would wrongly trip a STOP. The fix: pin the P2 measurement method (mutation) **at the baseline** and apply it every iteration, so energy is monotone. Worth an explicit clause: *"choose the energy-measurement method up front; the strict-descent invariant is defined relative to that fixed method — a rise only counts if it's under the same method."* Caught this only because I ran a deliberately-stronger confirmation pass; a single-method run wouldn't have, but would also have silently mis-measured the baseline.
- **SF-8 (the final P2=0 termination proof must be a SINGLE-ACTOR mechanical sweep, not a multi-agent workflow, §4).** I first tried to confirm "every guard is controlled" with a parallel Workflow of mutation-reviewers. They race: each agent mutates the *same* source file in a *shared* worktree, so one agent's `git checkout` restores away another's mutation mid-run and the verdicts are unreliable. Either give each agent `isolation: 'worktree'`, or — better for the closing proof — run the mutation sweep as **one deterministic single-actor pass** (mutate → test → restore, serially). The mechanical sweep is the authoritative termination measure; a fan-out is fine for the *discovery* audit but not for the *proof*. (It also found AN-010, which the agent panel had missed.)
- **SF-9 (a guard mutation is "caught" by a CRASH too, not only an assertion failure, §2-① / P2).** My first sweep flagged the front-matter `afterClose < lines.count` guard as uncontrolled. False alarm: deleting it makes `lines[afterClose]` an out-of-range access, so the test *crashes* (`Fatal error: Index out of range`, signal 5) rather than failing an assertion — and my "is it red?" check grepped only for `Selected tests' failed`. A crash IS the suite catching the mutation. The P2 measure must count **any non-green outcome — assertion failure, fatal error, or non-zero exit — as "caught."** Worth stating explicitly, because off-by-one/bounds guards characteristically fail by crashing.
- **SF-10 (a mutation that fails to COMPILE is inconclusive, not "uncaught," §2-① / P2).** My sweep also flagged the fence-toggle mechanism as uncontrolled. False alarm again: my mutation (`inFence.toggle()` → `inFence = inFence`) is a hard compile error here ("assigning a variable to itself", warnings-as-errors), so the suite never ran — green-by-absence, not green-by-passing. The mutation harness must **distinguish build failure from a passing test run** (grep the build log; on `error:`/`fatalError`, mark the mutation *inconclusive* and rewrite it to compile — e.g. `inFence = false`). Otherwise non-compiling mutations masquerade as missing controls and inflate energy. Pair with SF-9: the only valid signals are {caught | uncaught | inconclusive-rebuild}.
- **SF-11 (energy counts uncaught LIVE guards, not uncaught LINES — dead guards and presentation constants are out of scope, §1/P2).** The final sweep left exactly two mutations un-caught, and *neither* is a P2 violation: (a) `!cells.isEmpty` is **provably dead** (`split(omittingEmptySubsequences:false)` never yields an empty array), so it guards no reachable behavior — and removing it to "clean up" the proof would cut a no-op version bump (release churn we're told to avoid); (b) the `baseReset` CSS constant is **presentation**, covered by visual-QA, intentionally not byte-pinned in unit tests (pinning it would be brittle churn on every legitimate style tweak — the same spirit as SF-1's "don't assert incidental output"). Suggest the rubric state plainly: *P2 energy = count of **reachable, behavioral** guards whose mutation the suite cannot detect; provably-unreachable guards and presentation/styling constants are out of scope, and the audit should classify-and-record them rather than force a churning change to drive the line-level mutation score to zero.*

---

## Termination — ANNEALED (2026-06-25)
**Scope S** = `OuroMDCore` `HTMLDocument` + `MarkdownTidy` (text/escaping core). **Final state:**
- **P1 (coverage)** = 100% line + region (`check-coverage.sh`, CI-gated).
- **P2 (non-vacuity)** = **energy 0**. Authoritative measure: a deterministic mechanical mutation sweep over *every* guard/branch in both files (SF-8). Every reachable, behavioral guard's mutation is **caught** (assertion failure or crash, per SF-9). The two un-caught mutations are classified out-of-scope, not violations: `!cells.isEmpty` (dead, AN-011) and `baseReset` CSS (presentation), per SF-11.
- **P3 (determinism)** ✓ · **SEC-1 (escaper soundness)** ✓ (reviewer-cleared, no findings) · **P5 (gate)** ✓ (PR-1 source change passed a 2-reviewer panel; test-only PRs gated by mutation per SF-6).
- **Shipped**: #56 (AN-003 real content-corruption fix, 0.9.43), #57 (AN-001 idempotency), #58 (AN-005..008 + AN-010 negative controls, test-only).
- **Yield**: 1 real silent-content-corruption bug + 6 load-bearing guards with no negative control, all in a scope that began at 100% coverage with 19 "thorough" tests — the P2-over-P1 thesis, demonstrated end-to-end.

One full pass now finds zero P-violations and discovers no new in-scope unit → **annealed** (anneal §-Termination).
