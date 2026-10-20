import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import OuroMD

@MainActor
final class DocumentHeaderLayoutTests: XCTestCase {
    func testEditorPaintsBehindHeaderWithoutReplicatingItsTopEdge() async throws {
        try XCTSkipUnless(SystemDesign.usesGlass)
        guard #available(macOS 26, *) else { return }
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.prohibited)
        XCTAssertEqual(app.activationPolicy(), .prohibited)
        defer { app.setActivationPolicy(previousPolicy) }
        let model = AppModel()
        let host = NSHostingView(rootView: EditorWebView(model: model, headerInset: 52))
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
        for (size, inset) in [(NSSize(width: 1000, height: 700), 52.0),
                              (NSSize(width: 600, height: 420), 0.0),
                              (NSSize(width: 1000, height: 700), 52.0)] {
            host.rootView = EditorWebView(model: model, headerInset: inset)
            window.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let web = try XCTUnwrap(editor(in: host))
            let painted = web.convert(web.bounds, to: host)
            XCTAssertEqual(painted.minY, host.bounds.minY, accuracy: 1)
            XCTAssertEqual(painted.maxY, host.bounds.maxY, accuracy: 1,
                           "the real editor must paint the header band, not synthesize it from text below")
            XCTAssertEqual(painted.width, host.bounds.width, accuracy: 1)
            XCTAssertEqual(web.obscuredContentInsets.top, inset,
                           "native viewport insets keep editing clear of the toolbar without mirroring text")
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.canBecomeKey)
            XCTAssertFalse(window.canBecomeMain)
            XCTAssertEqual(app.activationPolicy(), .prohibited)
        }
        let web = try XCTUnwrap(editor(in: host))
        web.loadHTMLString("""
        <!doctype html><style>body{margin:0}#flow{height:4000px}#fixed{position:fixed;top:0}</style>
        <div id="flow">SYNTHETIC VIEWPORT FIXTURE</div><div id="fixed">FIXED CUE</div>
        """, baseURL: nil)
        for zoom in [0.75, 1.0, 2.0] {
            EditorZoom.apply(zoom, to: web)
            let expectedHeight = (web.bounds.height - 52) / zoom
            var coordinates: [String: Double]?
            for _ in 0..<100 {
                coordinates = try await web.evaluateJavaScript("""
                (() => {
                  const flow = document.getElementById("flow"), fixed = document.getElementById("fixed");
                  if (!flow || !fixed) { return null; }
                  return {height:innerHeight, flow:flow.getBoundingClientRect().top,
                    fixed:fixed.getBoundingClientRect().top, scroll:scrollY};
                })()
                """) as? [String: Double]
                if abs((coordinates?["height"] ?? 0) - expectedHeight) <= 1 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let values = try XCTUnwrap(coordinates)
            print("HEADER_VIEWPORT zoom=\(zoom) \(values)")
            XCTAssertEqual(try XCTUnwrap(values["height"]), expectedHeight, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(values["flow"]), 0, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(values["fixed"]), 0, accuracy: 1,
                           "WebKit must avoid chrome itself; CSS must not double-inset fixed editing cues")
            XCTAssertEqual(try XCTUnwrap(values["scroll"]), 0, accuracy: 1)
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.isKeyWindow)
            XCTAssertFalse(window.isMainWindow)
            XCTAssertEqual(app.activationPolicy(), .prohibited)
        }
    }
}
