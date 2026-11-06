import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import OuroMD

/// The document paints under the glass header, so the page's own scroll
/// indicator must start at the header's lower edge instead of under it.
@MainActor
final class ScrollIndicatorHeaderTests: XCTestCase {
    private let headerInset = 52.0

    func testScrollIndicatorStartsBelowTheHeaderAtTopAndMidScroll() async throws {
        try XCTSkipUnless(SystemDesign.usesGlass)
        guard #available(macOS 26, *) else { return }
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.prohibited)
        defer { app.setActivationPolicy(previousPolicy) }
        for (theme, mode) in [("quartz", "ir"), ("graphite", "ir"), ("manuscript", "ir"),
                              ("quartz", "sv"), ("graphite", "sv")] {
            try await verifyIndicator(theme: theme, mode: mode)
        }
    }

    /// A fresh host per theme keeps each capture independent of an earlier repaint.
    @available(macOS 26, *)
    private func verifyIndicator(theme: String, mode: String) async throws {
        let model = AppModel()
        model.setMode(mode)
        model.setTheme(id: theme)
        let host = NSHostingView(rootView: EditorWebView(model: model, headerInset: headerInset))
        let window = NonActivatingHeadlessHostWindow(
            contentRect: NSRect(x: -30_000, y: -30_000, width: 1000, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = host
        defer { window.close() }
        func editor(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<200 {
            if model.isReady { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.isReady)
        let web = try XCTUnwrap(editor(in: host))
        XCTAssertEqual(web.obscuredContentInsets.top, 0, "the native inset would make the header glass opaque")
        model.bridge?.setMarkdown((1...120).map { "Paragraph \($0) of the scroll indicator fixture." }.joined(separator: "\n\n"))
        // Source mode scrolls its preview pane; the page itself does not scroll.
        let scroller = mode == "sv" ? "document.querySelector('.vditor-preview')" : "window"
        let scrollHeight = mode == "sv" ? "document.querySelector('.vditor-preview').scrollHeight" : "document.documentElement.scrollHeight"
        for _ in 0..<100 {
            let height = try await web.evaluateJavaScript("(\(scrollHeight)) || 0")
            if (height as? Double ?? 0) > 3000 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        for scrollTo in [0.0, 1200.0] {
            // Nudge first so the page reports a scroll even when it is already at the target.
            _ = try await web.evaluateJavaScript("(() => { const s = \(scroller); s.scrollTo(0, 10); s.scrollTo(0, \(scrollTo)); return true; })()")
            try await Task.sleep(for: .milliseconds(300))
            let bitmap = try await snapshot(of: web)
            let scale = Double(bitmap.pixelsWide) / Double(web.bounds.width)
            let top = try XCTUnwrap(indicatorTop(in: bitmap, scale: scale),
                                    "\(theme)-\(mode) at \(scrollTo): no scroll indicator was drawn")
            XCTAssertGreaterThanOrEqual(top, headerInset - 1,
                                        "\(theme)-\(mode) at \(scrollTo): the scroll indicator starts under the header")
        }
    }

    private func snapshot(of web: WKWebView) async throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(web.bitmapImageRepForCachingDisplay(in: web.bounds))
        web.cacheDisplay(in: web.bounds, to: bitmap)
        return bitmap
    }

    /// Top edge, in points, of the first indicator pixels in the right gutter. The
    /// header band is the page's own backdrop, so anything that differs from the
    /// page background there is the indicator.
    private func indicatorTop(in bitmap: NSBitmapImageRep, scale: Double) -> Double? {
        let background = rgb(bitmap, x: 2, y: Int(Double(bitmap.pixelsHigh) / 2))
        let firstColumn = bitmap.pixelsWide - Int(12 * scale)
        for y in 0..<bitmap.pixelsHigh {
            for x in firstColumn..<bitmap.pixelsWide {
                let pixel = rgb(bitmap, x: x, y: y)
                if zip(pixel, background).contains(where: { abs($0 - $1) > 24 }) { return Double(y) / scale }
            }
        }
        return nil
    }

    private func rgb(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> [Double] {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return [0, 0, 0] }
        return [color.redComponent * 255, color.greenComponent * 255, color.blueComponent * 255]
    }
}
