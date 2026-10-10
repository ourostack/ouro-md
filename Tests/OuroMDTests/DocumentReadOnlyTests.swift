import WebKit
import XCTest
@testable import OuroMD

@MainActor
final class DocumentReadOnlyTests: XCTestCase {
    func testLockedEditorStaysReadOnlyAcrossSourceModeAndUnlock() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-readonly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Plan.md")
        try "# Public plan\n\nKeep this document readable.\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = DocumentWindowController(filePath: file.path, selfTest: false, useAutosave: false)
        controller.model.autoSaveEnabled = false
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
            controller.model.teardown()
            controller.window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        func findEditor(in view: NSView) -> WKWebView? {
            if let editor = view as? WKWebView { return editor }
            return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
        }
        let content = try XCTUnwrap(controller.window.contentView)
        for _ in 0..<100 {
            if controller.model.isReady, findEditor(in: content) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let editor = try XCTUnwrap(findEditor(in: content))
        XCTAssertTrue(controller.model.isReady)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
        controller.syncChrome()
        try await Task.sleep(for: .milliseconds(100))
        let richEditable = try await editor.evaluateJavaScript("""
            document.querySelector('.vditor-ir .vditor-reset').getAttribute('contenteditable')
            """) as? String
        XCTAssertEqual(richEditable, "false")
        let lockedReplacement = try await editor.evaluateJavaScript("""
            window.ouro.replaceAll("Public plan", "Changed while locked", {})
            """) as? Int
        XCTAssertEqual(lockedReplacement, 0)
        let lockedText = try await editor.evaluateJavaScript("window.ouro.getValue()") as? String
        XCTAssertTrue(lockedText?.contains("Public plan") == true)
        XCTAssertFalse(lockedText?.contains("Changed while locked") == true)
        controller.model.setMode("sv")
        for _ in 0..<100 {
            let readOnly = try await editor.evaluateJavaScript("""
                document.querySelector('.vditor-sv')?.getAttribute('contenteditable') === 'false'
                """) as? Bool
            if readOnly == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let sourceEditable = try await editor.evaluateJavaScript("""
            document.querySelector('.vditor-sv')?.getAttribute('contenteditable')
            """) as? String
        XCTAssertEqual(sourceEditable, "false")
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
        controller.syncChrome()
        try await Task.sleep(for: .milliseconds(100))
        let unlockedEditable = try await editor.evaluateJavaScript("""
            document.querySelector('.vditor-sv')?.getAttribute('contenteditable')
            """) as? String
        XCTAssertEqual(unlockedEditable, "true")
        let unlockedReplacement = try await editor.evaluateJavaScript("""
            window.ouro.replaceAll("Public plan", "Allowed after unlock", {})
            """) as? Int
        XCTAssertEqual(unlockedReplacement, 1)
        XCTAssertFalse(controller.window.isVisible)
    }

    func testMovingFoldersRetargetsRenderedRelativeImagesWithoutRewritingMarkdown() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-image-move-\(UUID().uuidString)")
        let originalFolder = directory.appendingPathComponent("original", isDirectory: true)
        let destinationFolder = directory.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: originalFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let original = originalFolder.appendingPathComponent("Plan.md")
        let destination = destinationFolder.appendingPathComponent("Plan.md")
        let markdown = "# Public plan\n\n![Map](map.svg)\n"
        try markdown.write(to: original, atomically: true, encoding: .utf8)
        for (folder, color) in [(originalFolder, "red"), (destinationFolder, "blue")] {
            try """
                <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><rect width="40" height="40" fill="\(color)"/></svg>
                """.write(to: folder.appendingPathComponent("map.svg"), atomically: true, encoding: .utf8)
        }
        let controller = DocumentWindowController(filePath: original.path, selfTest: false, useAutosave: false)
        controller.model.autoSaveEnabled = false
        defer {
            controller.model.teardown()
            controller.window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        func findEditor(in view: NSView) -> WKWebView? {
            if let editor = view as? WKWebView { return editor }
            return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
        }
        let content = try XCTUnwrap(controller.window.contentView)
        for _ in 0..<100 {
            if controller.model.isReady, findEditor(in: content) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let editor = try XCTUnwrap(findEditor(in: content))
        for _ in 0..<100 {
            let loaded = try await editor.evaluateJavaScript("""
                Array.from(document.querySelectorAll('.vditor-reset img')).some(img => img.complete && img.naturalWidth > 0)
                """) as? Bool
            if loaded == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let before = try await editor.evaluateJavaScript("document.querySelector('.vditor-reset img')?.src") as? String
        XCTAssertTrue(before?.contains("/original/map.svg") == true)

        try controller.model.moveCurrentFile(to: destination)
        try await Task.sleep(for: .milliseconds(200))

        let after = try await editor.evaluateJavaScript("document.querySelector('.vditor-reset img')?.src") as? String
        XCTAssertTrue(after?.contains("/destination/map.svg") == true,
                      "Where moves must resolve document-relative assets in the new folder")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), markdown)
        let liveMarkdown = try await editor.evaluateJavaScript("window.ouro.getValue()") as? String
        XCTAssertTrue(liveMarkdown?.contains("](map.svg)") == true,
                      "Retargeting the rendered image must preserve its authored relative Markdown link")
        XCTAssertFalse(controller.model.isDirty)
        XCTAssertFalse(controller.window.isVisible)
    }
}
