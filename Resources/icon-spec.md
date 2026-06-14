# Ouro MD app icon — spec

The icon is a lowercase serif **.md** wordmark sitting on a field of "document
text" lines, on a white macOS squircle — the Typora structure, made unmistakably
a markdown file by using the `.md` extension itself.

## Source of truth

`Resources/AppIcon.svg` — a hand-tuned, layered vector (editable in Sketch/Figma).
Layers:
- **Card** — white rounded-rect (the squircle body).
- **Lines** — gray capsule rects; solid, fully-justified rows that break only to
  wrap around the wordmark.
- **Wordmark** — the `.md` as separate `dot` / `m` / `d` vector paths, with a soft
  drop-shadow filter.

The artwork is authored on its own 1024 artboard and placed into the macOS icon
grid by the `AppIcon` group's transform: `translate(100,100) scale(0.8046875)` —
an **824×824 body in a 1024 canvas, 100px padding all round**, so the icon sits
correctly beside other dock icons and the system drop shadow has room.

## Build

`scripts/build-icon.sh`:
1. Rasterizes `AppIcon.svg` → `AppIcon.png` (1024) via `scripts/rasterize-svg.swift`.
2. `sips` → iconset → `AppIcon.icns` (all sizes).

**Rasterizer note (important):** macOS's built-in `qlmanage` silently drops `rx`
corner rounding and mis-renders SVG filters — do NOT use it. `rasterize-svg.swift`
uses WebKit (transparent web view) for faithful rendering of the rounded card +
shadow. This was the root cause of earlier "the corners are sharp" confusion.

## Editing flow

1. Open `Resources/AppIcon.svg` in Sketch; tweak the `Card` / `Lines` / `Wordmark`
   layers. Keep the artwork on the 1024 artboard (the `AppIcon` group transform
   handles the macOS padding).
2. Export / save back over `Resources/AppIcon.svg` (preserve the layer ids).
3. `./scripts/build-icon.sh` → rebuild app (`./make-app.sh` or `./install.sh`).
4. **Always view the render at full + dock size before shipping** — render →
   view → compare, never assume.

## History

An earlier algorithmic generator (`scripts/make-icon.swift`) produced the icon
parametrically. It's retained for reference, but the **SVG is now the source of
truth** — the shipped design is the operator's hand-tuned `.md` artwork, not the
generated one.
