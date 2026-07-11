import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class DocumentWindowControllerTests: XCTestCase {
    func testTitleClickRoutesToOpenPanelWhileKeepingNativeChrome() {
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        // Native document chrome is preserved (system-drawn title + proxy icon,
        // draggable title bar) — the subclass only adds title-click routing.
        XCTAssertTrue(controller.window is DocumentWindow)
        XCTAssertTrue(controller.window.isMovableByWindowBackground)
        XCTAssertNil(controller.window.representedURL)
        XCTAssertFalse(controller.window.isDocumentEdited)

        // A plain title click opens a document rather than renaming inline.
        var opened = false
        controller.openDocumentFromTitleClickHandler = { opened = true }
        controller.openDocumentFromTitleClick()
        XCTAssertTrue(opened)
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
}
