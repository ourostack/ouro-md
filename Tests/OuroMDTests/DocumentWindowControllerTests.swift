import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class DocumentWindowControllerTests: XCTestCase {
    func testWindowUsesNativeDocumentChromeInsteadOfCustomTitleClickRouting() {
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        XCTAssertFalse(controller.window is DocumentWindow)
        XCTAssertTrue(controller.window.isMovableByWindowBackground)
        XCTAssertNil(controller.window.representedURL)
        XCTAssertFalse(controller.window.isDocumentEdited)
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

        controller.model.markDeletedOnDiskForTesting()
        controller.syncChrome()

        XCTAssertEqual(controller.window.subtitle, "deleted")
        XCTAssertEqual(controller.window.representedURL, renamed)
    }
}
