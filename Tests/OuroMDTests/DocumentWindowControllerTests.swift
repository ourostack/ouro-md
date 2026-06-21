import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class DocumentWindowControllerTests: XCTestCase {
    func testTitleClickRoutesToOpenPanelInsteadOfRename() {
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        var openedFromTitle = false
        controller.openDocumentFromTitleClickHandler = {
            openedFromTitle = true
        }

        let documentWindow = try! XCTUnwrap(controller.window as? DocumentWindow)
        let titleClick = try! XCTUnwrap(documentWindow.onTitleClicked)
        titleClick()

        XCTAssertTrue(openedFromTitle)
    }

    func testTitleClickDragDecisionKeepsSmallMotionClickable() {
        XCTAssertFalse(TitleClickGesture.isDrag(deltaX: 0, deltaY: 0))
        XCTAssertFalse(TitleClickGesture.isDrag(deltaX: 1, deltaY: 1))
        XCTAssertFalse(TitleClickGesture.isDrag(deltaX: 2, deltaY: 2))
    }

    func testTitleClickDragDecisionTreatsThresholdAsDrag() {
        XCTAssertTrue(TitleClickGesture.isDrag(deltaX: 3, deltaY: 0))
        XCTAssertTrue(TitleClickGesture.isDrag(deltaX: 0, deltaY: -3))
        XCTAssertTrue(TitleClickGesture.isDrag(deltaX: 2.2, deltaY: 2.1))
    }

    func testDocumentChromeAndTitleOpenAcrossSavedRenamedAndDeletedStates() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-title-flow-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("before.md")
        try? "# Before\n".write(to: original, atomically: true, encoding: .utf8)
        let controller = DocumentWindowController(filePath: original.path, selfTest: false, useAutosave: false)
        defer { controller.window.close() }

        var titleOpens = 0
        controller.openDocumentFromTitleClickHandler = { titleOpens += 1 }

        XCTAssertEqual(controller.window.title, "before.md")
        XCTAssertEqual(controller.window.representedURL, original)
        controller.openDocumentFromTitleClick()

        XCTAssertNil(controller.model.renameCurrentFile(to: "after.md"))
        let renamed = dir.appendingPathComponent("after.md")
        controller.syncChrome()
        XCTAssertEqual(controller.window.title, "after.md")
        XCTAssertEqual(controller.window.representedURL, renamed)
        controller.openDocumentFromTitleClick()

        controller.model.markDeletedOnDiskForTesting()
        controller.syncChrome()

        XCTAssertEqual(controller.window.subtitle, "deleted")
        XCTAssertEqual(controller.window.representedURL, renamed)
        controller.openDocumentFromTitleClick()

        XCTAssertEqual(titleOpens, 3)
    }
}
