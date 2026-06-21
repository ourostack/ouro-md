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
}
