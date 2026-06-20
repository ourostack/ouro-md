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
}
