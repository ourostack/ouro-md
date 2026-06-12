import XCTest
@testable import OuroMD

/// Records bridge calls so we can assert the model drives the editor correctly.
private final class MockBridge: EditorBridge {
    var current = ""
    var reloads: [String] = []
    var onReload: ((String) -> Void)?

    func setMarkdown(_ markdown: String) { current = markdown }
    func reloadMarkdown(_ markdown: String) { current = markdown; reloads.append(markdown); onReload?(markdown) }
    func getMarkdown(_ completion: @escaping (String) -> Void) { completion(current) }
    func getHTML(_ completion: @escaping (String) -> Void) { completion("") }
    func applyTheme(uiMode: String, css: String, codeTheme: String) {}
    func setMode(_ mode: String) {}
    func setOutline(_ on: Bool) {}
    func setFocusMode(_ on: Bool) {}
    func setTypewriter(_ on: Bool) {}
    func scrollToHeading(_ index: Int) {}
    func find(_ query: String, backward: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {}
    func replace(_ query: String, with replacement: String, all: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool, completion: @escaping (Int) -> Void) { completion(0) }
    func clearFind() {}
    func execCommand(_ command: String) {}
    func insertText(_ text: String) {}
    func markSaved() {}
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
}
