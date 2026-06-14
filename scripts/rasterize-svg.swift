import AppKit
import WebKit

// Reliable SVG → PNG rasterizer using WebKit (full SVG support: rounded rects,
// filters, gradients — unlike qlmanage, which silently drops rx rounding).
//   swift scripts/rasterize-svg.swift <in.svg> <out.png> [pixelSize=1024]
// Renders the SVG's viewBox into a square PNG of the given pixel size.

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: rasterize-svg <in.svg> <out.png> [size]\n".utf8)); exit(2)
}
let inPath = args[1], outPath = args[2]
let size = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024

guard let svg = try? String(contentsOfFile: inPath, encoding: .utf8) else {
    FileHandle.standardError.write(Data("rasterize: cannot read \(inPath)\n".utf8)); exit(1)
}

final class Rasterizer: NSObject, WKNavigationDelegate {
    let svg: String, outPath: String, px: Int
    var webView: WKWebView!
    init(svg: String, outPath: String, px: Int) { self.svg = svg; self.outPath = outPath; self.px = px }

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: px, height: px), configuration: cfg)
        // Transparent web view, so anything outside the rounded card stays
        // transparent in the snapshot (otherwise the view's opaque white fills
        // the corners and hides the squircle rounding).
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        // Inline the SVG with zero margins so it fills the snapshot exactly.
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;padding:0;background:transparent}
        svg{display:block;width:\(px)px;height:\(px)px}</style></head>
        <body>\(svg)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            FileHandle.standardError.write(Data("rasterize: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Let layout + filter rendering settle, then snapshot at exact pixel size.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = NSRect(x: 0, y: 0, width: self.px, height: self.px)
            cfg.snapshotWidth = NSNumber(value: self.px)   // force output pixel width
            self.webView.takeSnapshot(with: cfg) { image, error in
                guard let image, error == nil else {
                    FileHandle.standardError.write(Data("rasterize: snapshot failed: \(error?.localizedDescription ?? "?")\n".utf8)); exit(1)
                }
                // Normalize to an exactly px×px PNG.
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: self.px, pixelsHigh: self.px,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image.draw(in: NSRect(x: 0, y: 0, width: self.px, height: self.px))
                NSGraphicsContext.restoreGraphicsState()
                guard let data = rep.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write(Data("rasterize: png encode failed\n".utf8)); exit(1)
                }
                try? data.write(to: URL(fileURLWithPath: self.outPath))
                print("wrote \(self.outPath) (\(self.px)px)")
                exit(0)
            }
        }
    }
}

Rasterizer(svg: svg, outPath: outPath, px: size).run()
