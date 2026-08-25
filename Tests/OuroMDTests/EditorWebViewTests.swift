import XCTest
@testable import OuroMD

final class EditorWebViewTests: XCTestCase {
    func testInitialThemeBootstrapSeedsDarkThemeBeforeEditorReady() {
        let script = EditorWebView.initialThemeBootstrapScript(for: ThemeStore.shared.theme(id: "graphite"))

        XCTAssertTrue(script.contains("__ouroInitialTheme"))
        XCTAssertTrue(script.contains("github-dark"))
        XCTAssertTrue(script.contains("#2c2c2e"))
        XCTAssertTrue(script.contains("ouro-theme"))
        XCTAssertTrue(script.contains("ouro-initial-background"))
        XCTAssertTrue(script.contains("background-color"))
        XCTAssertTrue(script.contains("important"))
    }

    func testEditorDropWebViewAcceptsOnlyOpenableMarkdownFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let markdown = root.appendingPathComponent("dropped.md")
        let image = root.appendingPathComponent("image.png")
        try "# dropped".write(to: markdown, atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
        defer { try? FileManager.default.removeItem(at: root) }

        let accepted = NSPasteboard(name: NSPasteboard.Name("ouro-drop-\(UUID().uuidString)"))
        accepted.clearContents()
        XCTAssertTrue(accepted.writeObjects([markdown as NSURL]))
        XCTAssertEqual(EditorDropWebView.openableMarkdownURL(from: accepted), markdown)

        let ignored = NSPasteboard(name: NSPasteboard.Name("ouro-drop-\(UUID().uuidString)"))
        ignored.clearContents()
        XCTAssertTrue(ignored.writeObjects([image as NSURL]))
        XCTAssertNil(EditorDropWebView.openableMarkdownURL(from: ignored))
    }

    func testCoordinatorRoutesExternalAndRelativeMarkdownLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-link-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let current = root.appendingPathComponent("current.md")
        let linked = root.appendingPathComponent("linked.md")
        try "# Current".write(to: current, atomically: true, encoding: .utf8)
        try "# Linked".write(to: linked, atomically: true, encoding: .utf8)

        let model = AppModel()
        XCTAssertTrue(model.loadInitialFile(current.path))
        var external: URL?
        var local: URL?
        var anchor: String?
        var errors: [(String, String)] = []
        model.openLinkedDocumentHandler = { url, _ in local = url }
        model.presentErrorHandler = { message, error in
            errors.append((message, error.localizedDescription))
        }
        let coordinator = EditorWebView.Coordinator(
            model: model,
            externalURLOpener: { external = $0 },
            anchorScroller: { anchor = $0 }
        )

        coordinator.handleOpenURL("https://ouro.bot/docs")
        XCTAssertEqual(external, URL(string: "https://ouro.bot/docs"))

        coordinator.handleOpenURL("linked.md")
        XCTAssertEqual(local, linked.standardizedFileURL)
        XCTAssertTrue(errors.isEmpty)

        local = nil
        coordinator.handleOpenURL("missing.md")
        XCTAssertEqual(local, root.appendingPathComponent("missing.md").standardizedFileURL)
        XCTAssertTrue(errors.isEmpty)

        model.openLinkedDocumentHandler = nil
        coordinator.handleOpenURL("linked.md")
        XCTAssertEqual(errors.map { $0.0 }, ["Could not open linked.md"])
        XCTAssertTrue(errors[0].1.contains("No document window"))

        XCTAssertFalse(model.openLinkedDocument(root.appendingPathComponent("image.png")))
        XCTAssertEqual(errors.map { $0.0 }, ["Could not open linked.md", "Could not open image.png"])
        XCTAssertTrue(errors[1].1.contains("not a supported Markdown"))

        coordinator.handleOpenURL("#local-heading")
        XCTAssertEqual(anchor, "local-heading")
        coordinator.handleOpenURL("javascript:alert(1)")
        XCTAssertEqual(errors.count, 2)
    }
}
