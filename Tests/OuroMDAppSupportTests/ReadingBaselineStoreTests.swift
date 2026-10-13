import XCTest
@testable import OuroMDAppSupport

final class ReadingBaselineStoreTests: XCTestCase {
    func testFirstReadHasNoBaselineAndAcknowledgementSurvivesNewStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("private-note.md")
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        XCTAssertNil(try store.read(for: file))
        try store.write("# Original\n", for: file)
        let reopened = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        XCTAssertEqual(try reopened.read(for: file), "# Original\n")
        try reopened.write("# Reviewed\n", for: file)
        XCTAssertEqual(try store.read(for: file), "# Reviewed\n")
    }

    func testSymlinkAndRealFileShareBaseline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("real.md")
        let link = root.appendingPathComponent("link.md")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        try store.write("reviewed", for: link)
        XCTAssertEqual(try store.read(for: file), "reviewed")
    }

    func testCorruptRecordThrowsAndStorageIsPrivate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("baselines")
        let store = ReadingBaselineStore(directory: directory)
        try store.write("secret", for: root.appendingPathComponent("private-name.md"))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].lastPathComponent.contains("private-name"))
        let permissions = try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try Data("not a baseline".utf8).write(to: files[0])
        XCTAssertThrowsError(try store.read(for: root.appendingPathComponent("private-name.md")))
    }

    func testWriteFailureThrows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root)
        let store = ReadingBaselineStore(directory: root)
        XCTAssertThrowsError(try store.write("content", for: URL(fileURLWithPath: "/example.md")))
    }
}
