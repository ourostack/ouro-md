import AppKit
import XCTest
import WebKit
@testable import OuroMD

@MainActor
final class DocumentWindowControllerTests: XCTestCase {
    func testPublicObscuredInsetCoordinatesForDocumentCues() throws {
        try XCTSkipUnless(SystemDesign.usesGlass)
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }
        let content = try XCTUnwrap(controller.window.contentView)
        controller.window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        func editor(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        waitUntil(timeout: 2) { editor(in: content) != nil }
        let web = try XCTUnwrap(editor(in: content))
        // This checks WebKit's viewport contract, not Vditor startup. In an
        // unordered window editor readiness need not precede viewport layout.
        for zoom in [0.75, 1.0, 2.0] {
            EditorZoom.apply(zoom, to: web)
            var height = web.bounds.height
            if #available(macOS 26, *) { height -= web.obscuredContentInsets.top }
            let expected = height / zoom
            var result: [String: Double]?
            waitUntil(timeout: 5) {
                web.evaluateJavaScript("""
                (() => {
                  const first = document.createElement("div");
                  first.style.cssText = "position:fixed;top:0;left:0;width:10px;height:10px";
                  document.documentElement.appendChild(first);
                  const result = {top:first.getBoundingClientRect().top, height:innerHeight, offset:visualViewport.offsetTop};
                  first.remove();
                  return result;
                })()
                """) { value, _ in
                    result = value as? [String: Double]
                }
                return result?["top"] != nil && abs((result?["height"] ?? 0) - expected) <= 1
            }
            let coordinates = try XCTUnwrap(result)
            print("PUBLIC_HEADER_COORDINATES \(coordinates) webHeight=\(web.bounds.height) zoom=\(zoom)")
            XCTAssertFalse(controller.window.isVisible)
            XCTAssertEqual(try XCTUnwrap(coordinates["height"]), expected, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(coordinates["top"]), 0, accuracy: 1,
                           "WebKit's layout viewport already excludes the header; adding its inset again would double-offset cues")
        }
    }

    func testDocumentBackdropUnderlapsToolbarWithMatchingPublicObscuredInsets() throws {
        try XCTSkipUnless(SystemDesign.usesGlass, "native toolbar geometry is for the system design")
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }
        let window = controller.window
        let content = try XCTUnwrap(window.contentView)

        func editor(in view: NSView) -> WKWebView? {
            if let webView = view as? WKWebView { return webView }
            for child in view.subviews {
                if let found = editor(in: child) { return found }
            }
            return nil
        }
        func nativeBackdrop(in view: NSView) -> NSView? {
            if view.identifier?.rawValue == "OuroMDDocumentHeaderBackdrop" { return view }
            return view.subviews.lazy.compactMap { nativeBackdrop(in: $0) }.first
        }

        for size in [NSSize(width: 1080, height: 800), NSSize(width: 600, height: 420)] {
            window.setContentSize(size)
            for visible in [true, false, true] {
                window.toolbar?.isVisible = visible
                window.layoutIfNeeded()
                content.layoutSubtreeIfNeeded()
                waitUntil(timeout: 1) { editor(in: content) != nil }
                let webView = try XCTUnwrap(editor(in: content))
                let frame = webView.convert(webView.bounds, to: nil)
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertEqual(frame.maxY, content.convert(content.bounds, to: nil).maxY, accuracy: 1,
                               "moving document content must reach behind the native header, not stop at contentLayoutRect")
                if #available(macOS 26, *) {
                    let occlusion = max(0, frame.maxY - window.contentLayoutRect.maxY)
                    XCTAssertEqual(webView.obscuredContentInsets.top, occlusion, accuracy: 1,
                                   "WebKit must keep the first line and caret below the same native header band")
                    if visible {
                        XCTAssertGreaterThan(occlusion, 0, "a visible toolbar needs document backdrop beneath it")
                    }
                    let backdrop = try XCTUnwrap(nativeBackdrop(in: content) as? NSGlassEffectView,
                                                 "the header needs an actual native glass panel, not raw underlap alone")
                    let glassFrame = backdrop.convert(backdrop.bounds, to: nil)
                    XCTAssertEqual(glassFrame.maxY, frame.maxY, accuracy: 1)
                    XCTAssertEqual(glassFrame.minY, window.contentLayoutRect.maxY, accuracy: 1,
                                   "glass must stop at the native header edge, never fade into readable text")
                    XCTAssertEqual(glassFrame.width, frame.width, accuracy: 1)
                    XCTAssertEqual(backdrop.style, .regular)
                    XCTAssertEqual(backdrop.cornerRadius, 0)
                    XCTAssertNil(backdrop.tintColor)
                    XCTAssertNotNil(backdrop.contentView)
                    XCTAssertNil(backdrop.hitTest(NSPoint(x: backdrop.bounds.midX, y: backdrop.bounds.midY)))
                    XCTAssertFalse(backdrop.isAccessibilityElement())
                }
                XCTAssertFalse(window.isVisible, "geometry checks must never order a window front")
            }
        }
        XCTAssertFalse(window.isVisible, "this geometry test must never order a test window front")
    }

    func testRealTitleClickEventsRouteToOpenPanelWithoutConsumingNativeChrome() throws {
        let controller = DocumentWindowController(filePath: nil, selfTest: true, useAutosave: false)
        defer { controller.window.close() }

        let window = try XCTUnwrap(controller.window as? DocumentWindow)
        window.titleClickDelay = 0.02
        XCTAssertTrue(controller.window.isMovableByWindowBackground)
        XCTAssertNil(controller.window.representedURL)
        XCTAssertFalse(controller.window.isDocumentEdited)

        // Send real NSEvents through AppKit's actual native title text field.
        // The old test only called openDocumentFromTitleClick() directly, so it
        // could not catch that NSWindow.mouseDown never receives these clicks.
        waitUntil(timeout: 1) { window.titleHitView?() != nil }
        let hitView = try XCTUnwrap(window.titleHitView?())
        let point = hitView.convert(NSPoint(x: 20, y: 12), to: nil)

        var opened = false
        controller.openDocumentFromTitleClickHandler = { opened = true }
        window.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseDown, at: point, in: window)))
        window.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseUp, at: point, in: window)))
        waitUntil(timeout: 0.2) { opened }
        XCTAssertTrue(opened)

        // The first half of a double-click must not open a modal panel before
        // AppKit receives the second click.
        opened = false
        window.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseDown, at: point, in: window)))
        window.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseUp, at: point, in: window)))
        window.sendEvent(try XCTUnwrap(mouseEvent(
            .leftMouseDown,
            at: point,
            in: window,
            clickCount: 2
        )))
        window.sendEvent(try XCTUnwrap(mouseEvent(
            .leftMouseUp,
            at: point,
            in: window,
            clickCount: 2
        )))
        waitUntil(timeout: 0.1) { opened }
        XCTAssertFalse(opened)

        // A drag remains AppKit's window-drag gesture and never opens a panel.
        opened = false
        window.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseDown, at: point, in: window)))
        let dragged = NSPoint(x: point.x + 4, y: point.y)
        window.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseDragged, at: dragged, in: window)))
        window.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseUp, at: dragged, in: window)))
        XCTAssertFalse(opened)

        // Modified clicks are preserved for native title-bar behavior.
        window.sendEvent(try XCTUnwrap(mouseEvent(
            .leftMouseDown,
            at: point,
            in: window,
            modifiers: .command
        )))
        window.sendEvent(try XCTUnwrap(mouseEvent(
            .leftMouseUp,
            at: point,
            in: window,
            modifiers: .command
        )))
        XCTAssertFalse(opened)
    }

    func testDocumentTruthIsALabeledToolbarButtonWithTheSystemDesign() throws {
        try XCTSkipUnless(SystemDesign.usesGlass, "the labeled toolbar button is for the system design")
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        XCTAssertTrue(controller.window.titlebarAccessoryViewControllers.allSatisfy { !($0.view is DocumentTruthAccessoryContainer) })
        let item = try XCTUnwrap(controller.truthToolbarItem)
        XCTAssertEqual(controller.window.toolbar?.items.last?.itemIdentifier, item.itemIdentifier, "status sits at the trailing end")
        let button = try XCTUnwrap(item.view as? DocumentTruthTitleButton)
        XCTAssertTrue(button.labeled)
        XCTAssertEqual(button.title, "Not saved")
        XCTAssertNotNil(button.image)
        XCTAssertGreaterThan(button.intrinsicContentSize.width, DocumentTruthTitleButton.controlSize.width)
        XCTAssertEqual(button.accessibilityLabel(), "File status")
        XCTAssertEqual(button.accessibilityValue() as? String, "Untitled")
        XCTAssertEqual(button.makeMenu().items.count, 4)
        XCTAssertEqual(item.menuFormRepresentation?.submenu?.items.count, 4, "the overflow menu keeps the actions")
        XCTAssertTrue(controller.toolbar(controller.window.toolbar!, itemForItemIdentifier: item.itemIdentifier, willBeInsertedIntoToolbar: false) === item, "the item is made once")

        controller.model.toggleFocusMode()
        controller.syncChrome()
        if #available(macOS 15.0, *) { XCTAssertTrue(item.isHidden, "focus mode hides the status") }
    }

    func testDocumentTruthAccessoryIsFixedSizeNativeGlyphWithAccessibleMenu() throws {
        try XCTSkipIf(SystemDesign.usesGlass, "the title-bar glyph is for systems before the system design")
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        let button = try XCTUnwrap(
            controller.window.titlebarAccessoryViewControllers
                .compactMap { ($0.view as? DocumentTruthAccessoryContainer)?.button }
                .first
        )
        XCTAssertEqual(button.intrinsicContentSize, DocumentTruthTitleButton.controlSize)
        XCTAssertEqual(button.frame.width, DocumentTruthTitleButton.controlSize.width)
        XCTAssertGreaterThanOrEqual(button.frame.height, DocumentTruthTitleButton.controlSize.height)
        XCTAssertLessThanOrEqual(button.frame.height, 32)
        controller.window.layoutIfNeeded()
        if let container = button.superview, container.frame.height > button.frame.height {
            XCTAssertEqual(button.frame.midY, container.bounds.midY, accuracy: 1, "glyph stays centred in a tall toolbar")
        }
        XCTAssertEqual(button.title, "")
        XCTAssertNotNil(button.image)
        XCTAssertFalse(button.subviews.contains { $0 is NSTextField })
        XCTAssertEqual(button.accessibilityLabel(), "File status")
        XCTAssertEqual(button.accessibilityValue() as? String, "Untitled")
        XCTAssertEqual(button.makeMenu().items.map(\.title), [
            "Reveal in Finder",
            "Copy File Path",
            "Copy Relative Path",
            "Copy Git Diff Command",
        ])
        XCTAssertTrue(button.makeMenu().items.allSatisfy { !$0.isEnabled })
    }

    func testTitleClickGestureDistinguishesClickFromDrag() {
        XCTAssertFalse(TitleClickGesture.isDrag(deltaX: 1, deltaY: 1))
        XCTAssertFalse(TitleClickGesture.isDrag(deltaX: 2, deltaY: 2))
        XCTAssertTrue(TitleClickGesture.isDrag(deltaX: 3, deltaY: 0))
        XCTAssertTrue(TitleClickGesture.isDrag(deltaX: 0, deltaY: -4))
    }

    func testDocumentChromeAcrossSavedRenamedDirtyAndDeletedStates() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-title-flow-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("before.md")
        try? "# Before\n".write(to: original, atomically: true, encoding: .utf8)
        let controller = DocumentWindowController(filePath: original.path, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        XCTAssertEqual(controller.window.title, "before.md")
        XCTAssertEqual(controller.window.representedURL, original)
        XCTAssertFalse(controller.window.isDocumentEdited)

        XCTAssertNil(controller.model.renameCurrentFile(to: "after.md"))
        let renamed = dir.appendingPathComponent("after.md")
        controller.syncChrome()
        XCTAssertEqual(controller.window.title, "after.md")
        XCTAssertEqual(controller.window.representedURL, renamed)

        controller.model.setDirty(true)
        controller.syncChrome()
        XCTAssertTrue(controller.window.isDocumentEdited)

        try? FileManager.default.removeItem(at: renamed)
        controller.model.teardown()
        controller.model.markDeletedOnDiskForTesting()
        controller.syncChrome()

        XCTAssertTrue(controller.model.deletedOnDisk)
        waitUntil(timeout: 1) { controller.window.subtitle == "deleted" }
        XCTAssertEqual(controller.window.subtitle, "deleted")
        XCTAssertEqual(controller.window.representedURL, renamed)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at point: NSPoint,
        in window: NSWindow,
        modifiers: NSEvent.ModifierFlags = [],
        clickCount: Int = 1
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: type == .leftMouseUp ? 0 : 1
        )
    }
}
