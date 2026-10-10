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
        XCTAssertFalse(controller.window.isVisible)
    }
}
