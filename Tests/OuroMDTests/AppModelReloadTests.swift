import XCTest
@testable import OuroMD

/// Records bridge calls so we can assert the model drives the editor correctly.
private final class MockBridge: EditorBridge {
    var current = ""
    var reloads: [String] = []
    var getMarkdownCalls = 0
    var onReload: ((String) -> Void)?

    func setMarkdown(_ markdown: String) { current = markdown }
    func reloadMarkdown(_ markdown: String) { current = markdown; reloads.append(markdown); onReload?(markdown) }
    func getMarkdown(_ completion: @escaping (String?) -> Void) { getMarkdownCalls += 1; completion(current) }
    func getHTML(_ completion: @escaping (String?) -> Void) { completion("") }
    func applyTheme(uiMode: String, css: String, codeTheme: String) {}
    func setMode(_ mode: String) {}
    func setOutline(_ on: Bool) {}
    func setFocusMode(_ on: Bool) {}
    func setTypewriter(_ on: Bool) {}
    func setAutoPair(_ on: Bool) {}
    func scrollToHeading(_ index: Int) {}
    func find(_ query: String, backward: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {}
    func replace(_ query: String, with replacement: String, all: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool, completion: @escaping (Int) -> Void) { completion(0) }
    func clearFind() {}
    func execCommand(_ command: String) {}
    func insertText(_ text: String) {}
    func setDocBase(_ directory: String?) {}
    func markSaved() {}
    func undo() {}
    func redo() {}
    func focusEditor() {}
    func printDocument() {}
    func setZoom(_ factor: Double) {}
}

final class AppModelReloadTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-reload-\(UUID().uuidString).md")
    }

    /// The core agent↔human loop: an agent rewrites the open file; ouro-md must
    /// push the new content into the editor without a relaunch.
    func testExternalEditTriggersLiveReload() {
        let url = tempFile()
        try? "# Original\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)
        XCTAssertEqual(bridge.current, "# Original\n", "initial load should reach the editor")

        let exp = expectation(description: "external edit live-reloaded")
        exp.assertForOverFulfill = false
        bridge.onReload = { md in if md.contains("Updated by agent") { exp.fulfill() } }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            try? "# Updated by agent\n\nNew paragraph.\n".write(to: url, atomically: true, encoding: .utf8)
        }
        wait(for: [exp], timeout: 6)
        XCTAssertTrue(bridge.current.contains("Updated by agent"), "editor should hold the agent's new content")
    }

    /// Our own save must not bounce back as an external reload.
    func testOwnSaveDoesNotSelfReload() {
        let url = tempFile()
        try? "# Original\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        // Simulate the user editing, then an autosave-style write of that content.
        bridge.current = "# Original\n\nMy edit.\n"
        model.setDirty(true)
        model.save()

        let done = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertTrue(bridge.reloads.isEmpty, "saving our own content should not trigger a reload")
    }

    func testDirtyFormattingOnlySaveDoesNotRestoreOriginalBytes() {
        let url = tempFile()
        let original = """
        ### Tables line up


        | Theme      | Mood             | Type  |
        | :--------- | :--------------- | :---- |
        | Quartz     | calm daylight    | sans  |
        """
        try? original.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        let dirtyEditorOutput = """
        ### Tables line up

        | Theme      | Mood             | Type  |
        | :--- | :--- | :--- |
        | Quartz     | calm daylight    | sans  |
        """
        bridge.current = dirtyEditorOutput
        model.setDirty(true)
        model.save()

        let done = expectation(description: "save settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), dirtyEditorOutput)
    }

    func testCleanSaveDoesNotRoundTripThroughEditor() {
        let url = tempFile()
        let original = "# Original\n\n"
        try? original.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        bridge.current = "# Unexpected editor normalization\n"
        model.save()

        let done = expectation(description: "save settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
        XCTAssertEqual(bridge.getMarkdownCalls, 0)
    }

    /// Saving before the editor has loaded must NOT overwrite the file with "".
    func testSaveBeforeEditorReadyDoesNotEmptyFile() {
        let url = tempFile()
        try? "# Important content the user must not lose".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge                // bridge present...
        model.loadInitialFile(url.path)      // ...but editorDidBecomeReady NOT called → not ready
        model.save()

        let done = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8),
                       "# Important content the user must not lose",
                       "save before the editor is ready must not clobber the file")
    }

    /// Click-to-rename renames the file on disk and re-points the model at it.
    func testRenameMovesFileAndRetargetsModel() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-rename-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("before.md")
        try? "# Hi\n".write(to: url, atomically: true, encoding: .utf8)

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        let error = model.renameCurrentFile(to: "after.md")
        XCTAssertNil(error, "rename should succeed")
        let renamed = dir.appendingPathComponent("after.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path), "new file should exist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "old file should be gone")
        XCTAssertEqual(model.currentURL?.lastPathComponent, "after.md", "model should track the new URL")
        XCTAssertEqual(model.windowTitle, "after.md", "title should follow the rename")
    }

    /// A bare new name keeps the original extension, like Finder.
    func testRenameWithoutExtensionKeepsOriginal() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-rename-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("notes.md")
        try? "x".write(to: url, atomically: true, encoding: .utf8)

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        XCTAssertNil(model.renameCurrentFile(to: "journal"))
        XCTAssertEqual(model.currentURL?.lastPathComponent, "journal.md",
                       "a name without an extension should keep the original .md")
    }

    /// Renaming onto an existing file must refuse rather than clobber it.
    func testRenameRefusesCollision() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-rename-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.md")
        try? "a".write(to: url, atomically: true, encoding: .utf8)
        let other = dir.appendingPathComponent("b.md")
        try? "b".write(to: other, atomically: true, encoding: .utf8)

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        XCTAssertNotNil(model.renameCurrentFile(to: "b.md"), "collision should be refused")
        XCTAssertEqual(try? String(contentsOf: other, encoding: .utf8), "b", "existing file must be untouched")
        XCTAssertEqual(model.currentURL?.lastPathComponent, "a.md", "model should keep the original URL")
    }

    /// A case-only rename (notes.md → Notes.md) must not be mistaken for a
    /// collision with itself on a case-insensitive volume.
    func testRenameCaseOnlyIsAllowed() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-rename-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("notes.md")
        try? "x".write(to: url, atomically: true, encoding: .utf8)

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        XCTAssertNil(model.renameCurrentFile(to: "Notes.md"), "a case-only rename should be allowed")
        XCTAssertEqual(model.currentURL?.lastPathComponent, "Notes.md", "model should track the new case")
    }
}
