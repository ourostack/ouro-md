import AppKit
import CoreText

// Parametric generator for the Ouro MD app icon. See Resources/icon-spec.md.
// Output format is chosen by the file extension of arg 1 (default /tmp/icon-test.png):
//   .png  → rendered bitmap (used by build-icon.sh for AppIcon.png/.icns)
//   .svg  → layered, editable vector (card rect + "Lines" group + "Wordmark"
//           group of per-glyph paths) for tweaking in Sketch/Figma/etc.
// Structure: flat white squircle, a full field of justified gray "text" lines,
// and a lowercase ".md" wordmark that the lines wrap around, with a soft shadow.

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon-test.png"

// Compact number formatter for SVG attribute values.
func n(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }

// ---- tunables ----
let SIZE: CGFloat = 1024
let inset: CGFloat = 40
let cornerFraction: CGFloat = 0.225          // of inner side
let fontName = "Georgia-Bold"
let glyphText = ".md"                         // lowercase file-extension wordmark
let mdColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 1)
let mdWidthFraction: CGFloat = 0.56           // wordmark total width / inner width
let opticalRaise: CGFloat = 14                // nudge content up a touch
let haloPad: CGFloat = 30                     // white gap where letters meet lines
let minSegment: CGFloat = 40                  // drop only true slivers
let bodyMinInkFraction: CGFloat = 0.28        // only break a line where the letter
                                              // body is at least this wide (× md
                                              // width); thin features (d ascender,
                                              // lone dot) let the line run solid.

let lineColor = NSColor(calibratedRed: 0.827, green: 0.843, blue: 0.863, alpha: 1)
let rowCount = 8
let lineThickness: CGFloat = 30
let sideMargin: CGFloat = 84                  // line field inset from card edge (justified within)
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

// Build the wordmark path, sized so the FOCAL letters (everything after a leading
// dot — i.e. "md") have width = mdWidthFraction * inner width, and centered so the
// focal letters are centered on the card. A leading "." therefore hangs to the
// left without shifting the "md" off-center.
func buildWordmark(focalWidth targetFocalWidth: CGFloat) -> (path: CGPath, glyphs: [CGPath], focalWidth: CGFloat) {
    let hasLeadingDot = glyphText.hasPrefix(".")
    func glyphPaths(fontSize: CGFloat) -> [CGPath] {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attr = NSAttributedString(string: glyphText, attributes: [.font: font as Any])
        let lineCT = CTLineCreateWithAttributedString(attr)
        var paths: [CGPath] = []
        for run in CTLineGetGlyphRuns(lineCT) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            for i in 0..<count {
                guard let gp = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                var t = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                if let moved = gp.copy(using: &t) { paths.append(moved) }
            }
        }
        return paths
    }
    // Bounding box of just the focal letters (drop the leading dot glyph).
    func focalBox(_ paths: [CGPath]) -> CGRect {
        let focal = (hasLeadingDot && paths.count > 1) ? Array(paths.dropFirst()) : paths
        return focal.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
    }
    let probe = glyphPaths(fontSize: 100)
    let scale = targetFocalWidth / focalBox(probe).width
    let sized = glyphPaths(fontSize: 100 * scale)
    let fbox = focalBox(sized)
    let combined = CGMutablePath()
    var positioned: [CGPath] = []
    var t = CGAffineTransform(translationX: SIZE/2 - fbox.midX, y: centerY - fbox.midY)
    for p in sized {
        if let m = p.copy(using: &t) { combined.addPath(m); positioned.append(m) }
    }
    return (combined, positioned, fbox.width)
}

let (glyphPath, glyphPieces, focalInkWidth) = buildWordmark(focalWidth: inner.width * mdWidthFraction)
let glyphBox = glyphPath.boundingBoxOfPath
let bodyMinInk = focalInkWidth * bodyMinInkFraction

// Per line row, the horizontal interval the letters occupy (leftmost → rightmost
// ink + halo) — but ONLY when the letter body at that row is wide enough to be
// worth breaking the line for. Thin features (the d's ascender, the lone dot) and
// empty rows return nil, so those lines run solid all the way across.
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
    guard maxX >= minX, (maxX - minX) >= bodyMinInk else { return nil }
    return (minX - haloPad, maxX + haloPad)
}

// Field geometry + the line segments — DATA used by both PNG and SVG output.
let fieldLeft = inner.minX + sideMargin
let fieldRight = inner.maxX - sideMargin
let rowSpan = inner.height - 2*sideMargin
let rowGap = rowSpan / CGFloat(rowCount - 1)

// Each row is one SOLID, fully-justified line spanning the field edge to edge.
// The wordmark punches a clean gap: rows that meet the letter body break into a
// left + right piece hugging the silhouette; all other rows are full bars.
var lineSegments: [(x0: CGFloat, x1: CGFloat, y: CGFloat)] = []
for r in 0..<rowCount {
    let y = centerY + rowSpan/2 - CGFloat(r) * rowGap
    func add(_ x0: CGFloat, _ x1: CGFloat) {
        if (x1 - x0) >= minSegment { lineSegments.append((x0, x1, y)) }
    }
    if let (ex0, ex1) = excludedInterval(atRowY: y) {
        add(fieldLeft, ex0); add(ex1, fieldRight)
    } else {
        add(fieldLeft, fieldRight)
    }
}

// ---- SVG output: layered, editable vector for Sketch/Figma ----
if outPath.lowercased().hasSuffix(".svg") {
    func hex(_ c: NSColor) -> String {
        let r = c.usingColorSpace(.deviceRGB)!
        return String(format: "#%02X%02X%02X",
                      Int((r.redComponent*255).rounded()),
                      Int((r.greenComponent*255).rounded()),
                      Int((r.blueComponent*255).rounded()))
    }
    // CGPath → SVG path data, flipping CG's y-up to SVG's y-down.
    func svgPath(_ path: CGPath) -> String {
        var d = ""
        path.applyWithBlock { ep in
            let e = ep.pointee
            func P(_ i: Int) -> String { let p = e.points[i]; return "\(n(p.x)) \(n(SIZE - p.y))" }
            switch e.type {
            case .moveToPoint: d += "M \(P(0)) "
            case .addLineToPoint: d += "L \(P(0)) "
            case .addQuadCurveToPoint: d += "Q \(P(0)) \(P(1)) "
            case .addCurveToPoint: d += "C \(P(0)) \(P(1)) \(P(2)) "
            case .closeSubpath: d += "Z "
            @unknown default: break
            }
        }
        return d.trimmingCharacters(in: .whitespaces)
    }
    let cardAttrs = "x=\"\(n(inner.minX))\" y=\"\(n(inner.minY))\" width=\"\(n(inner.width))\" height=\"\(n(inner.height))\" rx=\"\(n(corner))\" ry=\"\(n(corner))\""
    var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(SIZE))\" height=\"\(Int(SIZE))\" viewBox=\"0 0 \(Int(SIZE)) \(Int(SIZE))\">\n"
    svg += "  <defs>\n"
    svg += "    <filter id=\"softShadow\" x=\"-25%\" y=\"-25%\" width=\"150%\" height=\"150%\">\n"
    svg += "      <feDropShadow dx=\"0\" dy=\"7\" stdDeviation=\"8\" flood-color=\"#000000\" flood-opacity=\"0.20\"/>\n"
    svg += "    </filter>\n"
    svg += "    <clipPath id=\"cardClip\"><rect \(cardAttrs)/></clipPath>\n"
    svg += "  </defs>\n"
    svg += "  <rect id=\"Card\" \(cardAttrs) fill=\"#FFFFFF\"/>\n"
    svg += "  <g id=\"Lines\" fill=\"\(hex(lineColor))\" clip-path=\"url(#cardClip)\">\n"
    for s in lineSegments {
        let yTop = SIZE - (s.y + lineThickness/2)
        svg += "    <rect x=\"\(n(s.x0))\" y=\"\(n(yTop))\" width=\"\(n(s.x1 - s.x0))\" height=\"\(n(lineThickness))\" rx=\"\(n(lineThickness/2))\" ry=\"\(n(lineThickness/2))\"/>\n"
    }
    svg += "  </g>\n"
    let names = glyphText.map { String($0) }
    svg += "  <g id=\"Wordmark\" fill=\"\(hex(mdColor))\" filter=\"url(#softShadow)\">\n"
    for (i, g) in glyphPieces.enumerated() {
        let raw = i < names.count ? names[i] : "glyph\(i)"
        let label = raw == "." ? "dot" : raw
        svg += "    <path id=\"\(label)\" d=\"\(svgPath(g))\"/>\n"
    }
    svg += "  </g>\n"
    svg += "</svg>\n"
    try! svg.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("wrote \(outPath)")
    exit(0)
}

// ---- PNG output ----
cg.saveGState()
card.setClip()
lineColor.setFill()
for s in lineSegments {
    let rect = NSRect(x: s.x0, y: s.y - lineThickness/2, width: s.x1 - s.x0, height: lineThickness)
    NSBezierPath(roundedRect: rect, xRadius: lineThickness/2, yRadius: lineThickness/2).fill()
}
cg.restoreGState()

// Black wordmark with a soft shadow.
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
