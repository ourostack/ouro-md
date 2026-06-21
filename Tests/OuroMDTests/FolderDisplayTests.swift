import XCTest
@testable import OuroMD

final class FolderDisplayTests: XCTestCase {
    func testRelativePathAndParentHintStayWithinMountedFolder() {
        let root = URL(fileURLWithPath: "/tmp/ouro-folder")
        let file = root.appendingPathComponent("alpha/README.md")

        XCTAssertEqual(FolderDisplay.relativePath(file, under: root), "alpha/README.md")
        XCTAssertEqual(FolderDisplay.parentHint(file, under: root), "alpha")
        XCTAssertEqual(FolderDisplay.parentHint(root.appendingPathComponent("notes.md"), under: root), "ouro-folder")
    }

    func testDuplicateFileNamesAreDetectedCaseInsensitively() {
        let root = URL(fileURLWithPath: "/tmp/ouro-folder")
        let now = Date()
        let alpha = FolderNode(url: root.appendingPathComponent("alpha/README.md"), name: "README.md", isDirectory: false, modified: now, created: now, children: nil)
        let beta = FolderNode(url: root.appendingPathComponent("beta/readme.md"), name: "readme.md", isDirectory: false, modified: now, created: now, children: nil)
        let notes = FolderNode(url: root.appendingPathComponent("notes.md"), name: "notes.md", isDirectory: false, modified: now, created: now, children: nil)

        let nodes = [alpha, beta, notes]
        let duplicateNames = FolderDisplay.duplicateNames(in: nodes)

        XCTAssertTrue(FolderDisplay.hasDuplicateName(alpha, in: nodes))
        XCTAssertTrue(FolderDisplay.hasDuplicateName(beta, in: nodes))
        XCTAssertFalse(FolderDisplay.hasDuplicateName(notes, in: nodes))
        XCTAssertTrue(FolderDisplay.hasDuplicateName(alpha, duplicateNames: duplicateNames))
        XCTAssertFalse(FolderDisplay.hasDuplicateName(notes, duplicateNames: duplicateNames))
        XCTAssertEqual(FolderDisplay.accessibilityLabel(for: alpha, under: root, includeParent: true), "README.md, alpha")
    }
}
