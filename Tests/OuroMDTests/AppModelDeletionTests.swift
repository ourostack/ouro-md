import XCTest
@testable import OuroMD

/// The open file getting deleted/moved on disk must surface as a clear "deleted"
/// state (VSCode-style) rather than a silent unsaved edit — and must self-heal
/// when the file returns, without mistaking an atomic save's brief gap for a
/// deletion. Exercised through the real file watcher, like the reload tests.
final class AppModelDeletionTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-delete-\(UUID().uuidString).md")
    }

    func testDeletedFileSurfacesAsDeletedNotAsUnsavedEdit() {
        let url = tempFile()
        try? "# Doc\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        model.loadInitialFile(url.path)
        XCTAssertFalse(model.deletedOnDisk)

        let deleted = expectation(description: "deletion surfaced")
        deleted.assertForOverFulfill = false
        model.onChromeUpdate = { if model.deletedOnDisk { deleted.fulfill() } }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? FileManager.default.removeItem(at: url)
        }
        wait(for: [deleted], timeout: 6)
        XCTAssertTrue(model.deletedOnDisk, "a deleted open file should be flagged deleted")
        XCTAssertFalse(model.isDirty, "deletion shows as 'deleted', not as a misleading unsaved edit")
    }

    func testRecreatedFileClearsDeletedMarker() {
        let url = tempFile()
        try? "# Doc\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        model.loadInitialFile(url.path)

        let deleted = expectation(description: "deletion surfaced")
        deleted.assertForOverFulfill = false
        model.onChromeUpdate = { if model.deletedOnDisk { deleted.fulfill() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? FileManager.default.removeItem(at: url)
        }
        wait(for: [deleted], timeout: 6)
        XCTAssertTrue(model.deletedOnDisk)

        let restored = expectation(description: "deleted marker cleared on recreate")
        restored.assertForOverFulfill = false
        model.onChromeUpdate = { if !model.deletedOnDisk { restored.fulfill() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? "# Back\n".write(to: url, atomically: true, encoding: .utf8)
        }
        wait(for: [restored], timeout: 6)
        XCTAssertFalse(model.deletedOnDisk, "the marker should clear once the file returns")
    }

    func testTransientAtomicSaveGapIsNotFlaggedAsDeleted() {
        // An atomic save (write temp + rename) momentarily unlinks the file. That
        // brief gap must NOT be surfaced as a deletion.
        let url = tempFile()
        try? "# Doc\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        model.loadInitialFile(url.path)

        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(i + 1)) {
                try? "# Edit \(i)\n".write(to: url, atomically: true, encoding: .utf8)
            }
        }
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 6)
        XCTAssertFalse(model.deletedOnDisk, "atomic saves must not be mistaken for deletion")
    }
}
