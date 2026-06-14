# Ouro MD app icon — spec

Goal: the Typora app icon's structure, but with a serif **MD** instead of **T**.
Reference: Typora's icon (white rounded card, big black serif letter sitting on a
full field of gray "document text" lines that wrap around the letter).

Generator: `scripts/make-icon.swift` (parametric, reproducible). Render to a temp
PNG, **view it**, compare against the reference, tune params, repeat. Never ship
the icon without viewing the rendered result at both full and dock size.

## Hard requirements (from the reference + operator feedback)

1. **Card** — full-bleed rounded square (squircle). FLAT white, no gradient, no
   vignette, no bezel. iOS-style corner radius (~22% of side). Small even margin.

2. **Letters "MD"** — serif (Georgia Bold), near-black `#1A1A1A`.
   - **LARGE but width-constrained**: total ink width ≈ **74%** of inner width.
     (MD is two wide letters — sizing by *height* like Typora's single narrow T
     overflows the card horizontally; size by width instead. Cap height lands
     around 30% of inner height, which reads as substantial because it's wide.)
   - Horizontally + vertically centered (optical center, nudged up slightly).
   - Soft, subtle drop shadow: small downward offset, soft blur, low alpha — a
     gentle lift off the page, NOT a hard/muddy shadow.

3. **Document text-lines** — gray capsules `#D3D6DA`, the KEY structural element:
   - Fill the **ENTIRE card** as a full field of evenly spaced horizontal rows,
     top to bottom — NOT two small clusters on the left/right edges.
   - Each row spans the full inner width, broken into 2–4 segments with small
     gaps (like words on a line). Deterministic per-row so it's reproducible.
   - The letters **punch through** the field: lines are masked out wherever a
     letter is, leaving a clean white **gap (halo)** around each letter stroke so
     the lines appear to wrap around the letters (as in the reference).

## Render order (how the wrap-around is achieved)

1. White squircle card (clip everything below to it).
2. Full field of gray line-segments across every row.
3. White **halo**: the MD glyph path stroked thickly + filled white — erases the
   lines in a padded region around the letters (this creates the wrap gap).
4. Black MD glyphs with the soft shadow on top.

## Tunables (in make-icon.swift)

- `capHeightFraction` (letter size) · `haloPad` (wrap gap width)
- `rowCount`, `lineThickness`, `rowGap`, `lineColor`
- `shadowAlpha/Blur/Offset` · `cornerFraction`, `inset`

## Acceptance

Side-by-side with Typora at 1024px and at dock size (~64px): same visual weight
and structure — big serif letters on a full field of wrapped text-lines, flat
white card, soft lift. Verified by viewing the render, not by assumption.
