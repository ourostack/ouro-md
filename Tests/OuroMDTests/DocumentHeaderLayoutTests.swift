import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import OuroMD

@MainActor
final class DocumentHeaderLayoutTests: XCTestCase {
    func testEditorPaintsBehindHeaderWithoutReplicatingItsTopEdge() throws {
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
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
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
    }
}
