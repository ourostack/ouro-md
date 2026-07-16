import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class DocumentWindowControllerTests: XCTestCase {
    func testRealTitleClickEventsRouteToOpenPanelWithoutConsumingNativeChrome() throws {
        let controller = DocumentWindowController(filePath: nil, selfTest: true, useAutosave: false)
        defer { controller.window.close() }

        let window = try XCTUnwrap(controller.window as? DocumentWindow)
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
        XCTAssertTrue(opened)

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

    func testDocumentTruthAccessoryIsFixedSizeNativeGlyphWithAccessibleMenu() throws {
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        let button = try XCTUnwrap(
            controller.window.titlebarAccessoryViewControllers
                .compactMap { $0.view as? DocumentTruthTitleButton }
                .first
        )
        XCTAssertEqual(button.intrinsicContentSize, DocumentTruthTitleButton.controlSize)
        XCTAssertEqual(button.frame.width, DocumentTruthTitleButton.controlSize.width)
        XCTAssertGreaterThanOrEqual(button.frame.height, DocumentTruthTitleButton.controlSize.height)
        XCTAssertLessThanOrEqual(button.frame.height, 32)
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
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )
    }
}
