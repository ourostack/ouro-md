import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import OuroMD

/// The document paints under the glass header, so the page's own scroll
/// indicator must start at the header's lower edge instead of under it.
///
/// The pixel check reads the web view with `cacheDisplay`, the only capture that
/// includes the page's own scrollbar (`takeSnapshot` leaves it out). GitHub's
/// macOS 27 runner never composites WebKit content into a window: `cacheDisplay`
/// and ScreenCaptureKit both come back blank there, text included, while the same
/// capture shows the indicator on a real macOS 27 Mac (ourostack/ouro-md#159).
/// So the styles that draw the indicator are checked on every host, and the
/// pixels wherever the host can capture WebKit at all.
@MainActor
final class ScrollIndicatorHeaderTests: XCTestCase {
    private let headerInset = 52.0
    private var blankCaptures: [String] = []
    private var captureCount = 0

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
        if !blankCaptures.isEmpty {
            // Only a host that captures nothing at all, on macOS 27, may skip the pixels.
            // A blank capture anywhere else is a broken check and fails.
            XCTAssertEqual(blankCaptures.count, captureCount, "some captures were blank: \(blankCaptures)")
            XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 27,
                                        "the capture came back blank: \(blankCaptures)")
            throw XCTSkip("""
            The indicator's styles were checked, but this macOS 27 host composites no WebKit content, \
            so its pixels could not be read (ourostack/ouro-md#159)
            """)
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
        // The host window is never shown, so WebKit treats the page as hidden and drops
        // what it painted a few hundred milliseconds later; keep it painting.
        let keepPainting = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if web.responds(to: keepPainting) { web.setValue(false, forKey: "windowOcclusionDetectionEnabled") }
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
            // The nudge has to land before the move back, or WebKit sees no change and fires no scroll.
            _ = try await web.callAsyncJavaScript("""
            const s = \(scroller);
            s.scrollTo(0, 10);
            await new Promise(resolve => setTimeout(resolve, 50));
            s.scrollTo(0, \(scrollTo));
            return true;
            """, contentWorld: .page)
            try await Task.sleep(for: .milliseconds(300))
            try await verifyIndicatorStyles(in: web, mode: mode, label: "\(theme)-\(mode) at \(scrollTo)")
            let bitmap = try await snapshot(of: web)
            let scale = Double(bitmap.pixelsWide) / Double(web.bounds.width)
            captureCount += 1
            guard try await captured(bitmap, of: web) else {
                blankCaptures.append("\(theme)-\(mode) at \(scrollTo)")
                continue
            }
            let top = try XCTUnwrap(indicatorTop(in: bitmap, scale: scale),
                                    "\(theme)-\(mode) at \(scrollTo): no scroll indicator was drawn")
            XCTAssertGreaterThanOrEqual(top, headerInset - 1,
                                        "\(theme)-\(mode) at \(scrollTo): the scroll indicator starts under the header")
        }
    }

    /// While the page scrolls, the scroller has the styled 12-point indicator, its thumb
    /// is visible, and its track starts at the header's lower edge.
    private func verifyIndicatorStyles(in web: WKWebView, mode: String, label: String) async throws {
        let element = mode == "sv" ? "document.querySelector('.vditor-preview')" : "document.documentElement"
        let json = try await web.evaluateJavaScript("""
        (() => {
          const e = \(element);
          const style = (pseudo, name) => getComputedStyle(e, pseudo).getPropertyValue(name);
          const borders = parseFloat(getComputedStyle(e).borderLeftWidth) + parseFloat(getComputedStyle(e).borderRightWidth);
          const gutter = e === document.documentElement ? window.innerWidth - e.clientWidth : e.offsetWidth - e.clientWidth - borders;
          return JSON.stringify({ scrolling: document.documentElement.classList.contains('ouro-scrolling'), gutter,
            width: style('::-webkit-scrollbar', 'width'), trackTop: style('::-webkit-scrollbar-track', 'margin-top'),
            thumb: style('::-webkit-scrollbar-thumb', 'background-color') });
        })()
        """) as? String
        let styles = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(XCTUnwrap(json).utf8)) as? [String: Any])
        XCTAssertEqual(styles["scrolling"] as? Bool, true, "\(label): the page did not mark itself as scrolling")
        // The preview pane's width can be fractional, so its rounded gutter may be off by one.
        XCTAssertEqual(try XCTUnwrap(styles["gutter"] as? Double), 12, accuracy: 1,
                       "\(label): the styled indicator is not in use (\(styles))")
        XCTAssertEqual(styles["width"] as? String, "12px", "\(label): \(styles)")
        XCTAssertEqual(styles["trackTop"] as? String, "\(Int(headerInset))px", "\(label): the track does not start below the header")
        let thumb = try XCTUnwrap(styles["thumb"] as? String)
        XCTAssertFalse(thumb == "rgba(0, 0, 0, 0)" || thumb.hasSuffix("/ 0)"), "\(label): the thumb is transparent while scrolling (\(thumb))")
    }

    /// Whether the capture holds the page at all. `takeSnapshot` paints the page in the
    /// web process, so its text proves there was something to capture; a capture with
    /// none of it means the host composites no WebKit content, not that the page is blank.
    private func captured(_ bitmap: NSBitmapImageRep, of web: WKWebView) async throws -> Bool {
        if contentSamples(in: bitmap) > 0 { return true }
        let image = try await web.takeSnapshot(configuration: WKSnapshotConfiguration())
        let painted = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertGreaterThan(contentSamples(in: painted), 0, "the page painted nothing")
        return false
    }

    /// Sampled pixels left of the indicator's gutter that differ from the page background.
    private func contentSamples(in bitmap: NSBitmapImageRep) -> Int {
        let background = rgb(bitmap, x: 2, y: bitmap.pixelsHigh / 2)
        let gutter = Int(24 * Double(bitmap.pixelsWide) / 1000)
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide - gutter, by: 4)
            where zip(rgb(bitmap, x: x, y: y), background).contains(where: { abs($0 - $1) > 24 }) { count += 1 }
        }
        return count
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
