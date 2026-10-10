import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class FullscreenBackdropTests: XCTestCase {
    func testDetachedToolbarHostReceivesBehindWindowGlassWithoutCoveringNativeControls() throws {
        try XCTSkipUnless(SystemDesign.usesGlass)
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        let document = controller.window
        document.layoutIfNeeded()
        document.contentView?.layoutSubtreeIfNeeded()
        defer { document.close() }
        let control = try XCTUnwrap(controller.truthToolbarItem?.view)
        let originalParent = try XCTUnwrap(control.superview)
        let originalFrame = control.frame
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 52),
                            styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer {
            control.removeFromSuperview()
            originalParent.addSubview(control)
            control.frame = originalFrame
            host.close()
        }
        let backdropParent = try XCTUnwrap(host.contentView)
        let background = NSView(frame: backdropParent.bounds)
        let foreground = NSView(frame: backdropParent.bounds)
        backdropParent.addSubview(background)
        backdropParent.addSubview(foreground)
        control.removeFromSuperview()
        foreground.addSubview(control)
        control.frame = NSRect(x: 850, y: 8, width: 140, height: 36)
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: document)
        let panel = try XCTUnwrap(backdropParent.subviews.first {
            $0.identifier?.rawValue == "OuroMDFullscreenHeaderBackdrop"
        }, "AppKit detaches toolbar controls into another window; its backdrop must sample behind that window")
        XCTAssertEqual(panel.frame, backdropParent.bounds)
        XCTAssertTrue(backdropParent.subviews.first === background)
        XCTAssertTrue(backdropParent.subviews.last === foreground, "native controls remain above glass, not blurred by it")
        XCTAssertNil(panel.hitTest(NSPoint(x: 900, y: 25)))
        if #available(macOS 26, *) {
            let material = try XCTUnwrap(panel.subviews.compactMap { $0 as? NSVisualEffectView }.first)
            XCTAssertEqual(material.blendingMode, .behindWindow)
            XCTAssertEqual(material.material, .titlebar)
            let glass = try XCTUnwrap(panel.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            XCTAssertEqual(glass.style, .regular)
            XCTAssertEqual(glass.cornerRadius, 0)
            XCTAssertNil(glass.tintColor)
            XCTAssertEqual(glass.frame, panel.bounds)
        }
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: document)
        XCTAssertEqual(backdropParent.subviews.filter {
            $0.identifier?.rawValue == "OuroMDFullscreenHeaderBackdrop"
        }.count, 1, "repeated native callbacks must not stack glass")
        let replacement = NSView(frame: backdropParent.bounds)
        backdropParent.addSubview(replacement)
        foreground.removeFromSuperview()
        replacement.addSubview(foreground)
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: host)
        XCTAssertNil(panel.superview, "native toolbar reparenting must remove its stale backdrop")
        let replacementPanel = try XCTUnwrap(replacement.subviews.first {
            $0.identifier?.rawValue == "OuroMDFullscreenHeaderBackdrop"
        })
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: document)
        XCTAssertNil(replacementPanel.superview)
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: document)
        XCTAssertNotNil(replacement.subviews.first {
            $0.identifier?.rawValue == "OuroMDFullscreenHeaderBackdrop"
        })
        document.close()
        XCTAssertNil(replacement.subviews.first {
            $0.identifier?.rawValue == "OuroMDFullscreenHeaderBackdrop"
        }, "closing a retained document must not leave a detached fullscreen backdrop")
        XCTAssertFalse(document.isVisible)
        XCTAssertFalse(host.isVisible, "composition tests never present a local window")
    }
}
