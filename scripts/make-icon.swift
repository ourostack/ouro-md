import AppKit
import CoreText

// Parametric generator for the Ouro MD app icon. See Resources/icon-spec.md.
// Renders to the path given as arg 1 (default /tmp/icon-test.png).
// Structure: flat white squircle, a full field of gray "text" lines, and a large
// serif "MD" that punches through the lines (white halo gap) with a soft shadow.

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon-test.png"

// ---- tunables ----
let SIZE: CGFloat = 1024
let inset: CGFloat = 40
let cornerFraction: CGFloat = 0.225          // of inner side
let fontName = "Georgia-Bold"
let mdColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 1)
let mdWidthFraction: CGFloat = 0.64           // "MD" total width / inner width
let opticalRaise: CGFloat = 14                // nudge content up a touch
let haloPad: CGFloat = 34                     // white gap around letters
let minSegment: CGFloat = 44                  // drop line stubs shorter than this

let lineColor = NSColor(calibratedRed: 0.827, green: 0.843, blue: 0.863, alpha: 1)
let rowCount = 8
let lineThickness: CGFloat = 30
let sideMargin: CGFloat = 66                  // line field inset from card edge
let wordGap: CGFloat = 34
// ----------------

let inner = NSRect(x: inset, y: inset, width: SIZE - 2*inset, height: SIZE - 2*inset)
let corner = inner.width * cornerFraction
let centerY = SIZE/2 + opticalRaise

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(SIZE), pixelsHigh: Int(SIZE),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let cg = nsctx.cgContext
cg.interpolationQuality = .high
cg.setShouldAntialias(true)

NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: SIZE, height: SIZE).fill()

// 1. White squircle card.
let card = NSBezierPath(roundedRect: inner, xRadius: corner, yRadius: corner)
NSColor.white.setFill(); card.fill()

// Build the "MD" glyph path, sized so its total width = mdWidthFraction * inner
// width (two wide letters must be width-constrained), centered at (SIZE/2, centerY).
func mdPath(forWidth targetWidth: CGFloat) -> CGPath {
    func buildPath(fontSize: CGFloat) -> CGPath {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attr = NSAttributedString(string: "MD", attributes: [.font: font as Any])
        let lineCT = CTLineCreateWithAttributedString(attr)
        let combined = CGMutablePath()
        for run in CTLineGetGlyphRuns(lineCT) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            for i in 0..<count {
                guard let gp = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                var t = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                if let moved = gp.copy(using: &t) { combined.addPath(moved) }
            }
        }
        return combined
    }
    // Size at 100pt, then scale so the ink width matches the target.
    let probe = buildPath(fontSize: 100)
    let scale = targetWidth / probe.boundingBoxOfPath.width
    let sized = buildPath(fontSize: 100 * scale)
    let b = sized.boundingBoxOfPath
    var center = CGAffineTransform(translationX: SIZE/2 - b.midX, y: centerY - b.midY)
    return sized.copy(using: &center) ?? sized
}

let glyphPath = mdPath(forWidth: inner.width * mdWidthFraction)
let glyphBox = glyphPath.boundingBoxOfPath

// Precompute, per line row, the horizontal interval the letters occupy (leftmost
// → rightmost ink + halo) so lines can be clipped to wrap around the outer
// silhouette — never leaving fragments in counters, the M's valley, or the gap
// between letters.
func excludedInterval(atRowY y: CGFloat) -> (CGFloat, CGFloat)? {
    let yTop = y + lineThickness/2 + haloPad
    let yBot = y - lineThickness/2 - haloPad
    if yTop < glyphBox.minY || yBot > glyphBox.maxY { return nil }
    var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
    var x = glyphBox.minX - haloPad
    while x <= glyphBox.maxX + haloPad {
        for yy in stride(from: yBot, through: yTop, by: 5) {
            if glyphPath.contains(CGPoint(x: x, y: yy), using: .winding) {
                minX = min(minX, x); maxX = max(maxX, x); break
            }
        }
        x += 3
    }
    return maxX >= minX ? (minX - haloPad, maxX + haloPad) : nil
}

// 2. Full field of gray text-lines, clipped to the card.
cg.saveGState()
card.setClip()
let fieldLeft = inner.minX + sideMargin
let fieldRight = inner.maxX - sideMargin
let fieldWidth = fieldRight - fieldLeft
let rowSpan = inner.height - 2*sideMargin
let rowGap = rowSpan / CGFloat(rowCount - 1)
lineColor.setFill()

// Deterministic per-row segmentation (like words on a line).
func segments(forRow r: Int) -> [(CGFloat, CGFloat)] {
    let patterns: [[CGFloat]] = [
        [0.22, 0.30, 0.40],
        [0.46, 0.48],
        [0.18, 0.50, 0.24],
        [0.34, 0.58],
        [0.26, 0.36, 0.30],
        [0.52, 0.40],
        [0.20, 0.44, 0.28],
        [0.40, 0.30, 0.22],
        [0.30, 0.62],
    ]
    let frac = patterns[r % patterns.count]
    var out: [(CGFloat, CGFloat)] = []
    var x = fieldLeft
    for (i, f) in frac.enumerated() {
        let w = f * fieldWidth - (i > 0 ? wordGap : 0)
        if w <= 0 { continue }
        out.append((x, w)); x += w + wordGap
    }
    return out
}

for r in 0..<rowCount {
    let y = centerY + rowSpan/2 - CGFloat(r) * rowGap
    let excl = excludedInterval(atRowY: y)
    func bar(_ x0: CGFloat, _ x1: CGFloat) {
        guard (x1 - x0) >= minSegment else { return }
        let rect = NSRect(x: x0, y: y - lineThickness/2, width: x1 - x0, height: lineThickness)
        NSBezierPath(roundedRect: rect, xRadius: lineThickness/2, yRadius: lineThickness/2).fill()
    }
    if let (ex0, ex1) = excl {
        // Letter-band row: clean symmetric side-bars flanking the letters, so the
        // text field appears to wrap around them on every side (Typora-style).
        bar(fieldLeft, ex0)
        bar(ex1, fieldRight)
    } else {
        // Free row: the natural broken-into-words line.
        for (sx, sw) in segments(forRow: r) { bar(sx, min(sx + sw, fieldRight)) }
    }
}
cg.restoreGState()

// 4. Black MD with a soft shadow.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -7), blur: 16,
             color: NSColor.black.withAlphaComponent(0.20).cgColor)
cg.addPath(glyphPath)
cg.setFillColor(mdColor.cgColor)
cg.fillPath()
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
