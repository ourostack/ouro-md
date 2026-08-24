import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class AppDelegateWindowRoutingTests: XCTestCase {
    func testSidebarAndThemeCommandsTargetKeyWindowOnly() {
        let delegate = AppDelegate()
        delegate.newWindow(nil)
        let first = try! XCTUnwrap(delegate.frontController)
        first.model.editorDidBecomeReady()
        first.model.setTheme(id: "quartz")
        first.model.setSidebarMode(.outline)

        delegate.newWindow(nil)
        let second = try! XCTUnwrap(delegate.frontController)
        second.model.editorDidBecomeReady()
        second.model.setTheme(id: "quartz")
        second.model.setSidebarMode(.outline)
        defer {
            second.window.close()
            first.window.close()
        }

        first.window.makeKeyAndOrderFront(nil)
        first.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: first.window))
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        delegate.showSearchSidebar(nil)
        delegate.selectTheme(menuItem(representedObject: "graphite"))

        XCTAssertEqual(first.model.sidebarMode, .search)
        XCTAssertEqual(first.model.themeID, "graphite")
        XCTAssertNotEqual(second.model.sidebarMode, .search)
        XCTAssertNotEqual(second.model.themeID, "graphite")

        second.window.makeKeyAndOrderFront(nil)
        second.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: second.window))
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        delegate.showFileTreeSidebar(nil)
        delegate.selectTheme(menuItem(representedObject: "quartz"))

        XCTAssertEqual(second.model.sidebarMode, .files)
        XCTAssertEqual(second.model.themeID, "quartz")
        XCTAssertEqual(first.model.sidebarMode, .search)
        XCTAssertEqual(first.model.themeID, "graphite")
    }

    func testApplicationOpenReusesCleanUntitledFrontWindowThenOpensNewWindows() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-open-routing-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let firstURL = dir.appendingPathComponent("first.md")
        let secondURL = dir.appendingPathComponent("second.md")
        try? "# First\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try? "# Second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let delegate = AppDelegate()
        delegate.newWindow(nil)
        let initial = try! XCTUnwrap(delegate.frontController)
        defer {
            delegate.frontController?.window.close()
            initial.window.close()
        }

        delegate.application(NSApplication.shared, open: [firstURL])
        XCTAssertEqual(initial.model.currentURL, firstURL)

        delegate.application(NSApplication.shared, open: [secondURL])
        XCTAssertEqual(initial.model.currentURL, firstURL)
        XCTAssertEqual(delegate.frontController?.model.currentURL, secondURL)
    }

    func testLinkedMarkdownDocumentOpensInAnotherWindowAndReusesIt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-linked-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let currentURL = dir.appendingPathComponent("current.md")
        let linkedURL = dir.appendingPathComponent("linked.md")
        try "# Current\n".write(to: currentURL, atomically: true, encoding: .utf8)
        try "# Linked\n".write(to: linkedURL, atomically: true, encoding: .utf8)

        let delegate = AppDelegate()
        delegate.newWindow(nil)
        let current = try XCTUnwrap(delegate.frontController)
        XCTAssertTrue(current.model.loadInitialFile(currentURL.path))
        defer { current.window.close() }

        XCTAssertTrue(current.model.openLinkedDocument(linkedURL, fragment: "linked-section"))
        let linked = try XCTUnwrap(delegate.frontController)
        defer { linked.window.close() }
        XCTAssertFalse(linked === current)
        XCTAssertEqual(current.model.currentURL, currentURL)
        XCTAssertEqual(linked.model.currentURL, linkedURL)
        let linkedBridge = RecordingEditorBridge(markdown: "")
        linked.model.bridge = linkedBridge
        linked.model.editorDidBecomeReady()
        XCTAssertEqual(linkedBridge.anchors, ["linked-section"])

        XCTAssertTrue(current.model.openLinkedDocument(linkedURL, fragment: "second-section"))
        XCTAssertTrue(delegate.frontController === linked)
        XCTAssertEqual(linkedBridge.anchors, ["linked-section", "second-section"])
    }

    func testLinkedMarkdownRequestsSandboxAccessBeforeOpening() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-linked-sandbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let currentURL = dir.appendingPathComponent("current.md")
        let linkedURL = dir.appendingPathComponent("linked.md")
        try "# Current\n".write(to: currentURL, atomically: true, encoding: .utf8)
        try "# Linked\n".write(to: linkedURL, atomically: true, encoding: .utf8)

        let delegate = AppDelegate()
        delegate.newWindow(nil)
        let current = try XCTUnwrap(delegate.frontController)
        XCTAssertTrue(current.model.loadInitialFile(currentURL.path))
        defer { current.window.close() }

        var granted = false
        var requestedURL: URL?
        delegate.linkedDocumentReadable = { granted && $0 == linkedURL.standardizedFileURL }
        delegate.linkedDocumentAccessRequester = { target, _, completion in
            requestedURL = target
            granted = true
            completion(target)
        }

        XCTAssertTrue(current.model.openLinkedDocument(linkedURL))
        XCTAssertEqual(requestedURL, linkedURL.standardizedFileURL)
        let linked = try XCTUnwrap(delegate.frontController)
        defer { linked.window.close() }
        XCTAssertEqual(linked.model.currentURL, linkedURL.standardizedFileURL)
    }

    func testLinkedMarkdownReportsUnreadableAfterSandboxGrant() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-linked-unreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let currentURL = dir.appendingPathComponent("current.md")
        let linkedURL = dir.appendingPathComponent("linked.md")
        try "# Current\n".write(to: currentURL, atomically: true, encoding: .utf8)
        try "# Linked\n".write(to: linkedURL, atomically: true, encoding: .utf8)

        let delegate = AppDelegate()
        delegate.newWindow(nil)
        let current = try XCTUnwrap(delegate.frontController)
        XCTAssertTrue(current.model.loadInitialFile(currentURL.path))
        defer { current.window.close() }

        var errorDescription = ""
        current.model.presentErrorHandler = { _, error in
            errorDescription = error.localizedDescription
        }
        delegate.linkedDocumentReadable = { _ in false }
        delegate.linkedDocumentAccessRequester = { target, _, completion in completion(target) }

        XCTAssertTrue(current.model.openLinkedDocument(linkedURL))
        XCTAssertTrue(errorDescription.contains("does not exist or is not readable"))
        XCTAssertTrue(delegate.frontController === current)
    }

    func testSaveAndRenameCommandsTargetKeyWindowOnly() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-save-routing-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let firstURL = dir.appendingPathComponent("first.md")
        let secondURL = dir.appendingPathComponent("second.md")
        try? "# First\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try? "# Second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let delegate = AppDelegate()
        delegate.openInNewWindow(firstURL)
        let first = try! XCTUnwrap(delegate.frontController)
        delegate.openInNewWindow(secondURL)
        let second = try! XCTUnwrap(delegate.frontController)
        defer {
            second.window.close()
            first.window.close()
        }

        let firstBridge = RecordingEditorBridge(markdown: "")
        let secondBridge = RecordingEditorBridge(markdown: "")
        first.model.setAutoSave(false)
        second.model.setAutoSave(false)
        first.model.bridge = firstBridge
        second.model.bridge = secondBridge
        first.model.editorDidBecomeReady()
        second.model.editorDidBecomeReady()
        firstBridge.markdown = "# First edited\n"
        secondBridge.markdown = "# Second edited\n"
        first.model.setDirty(true)
        second.model.setDirty(true)

        var renameTarget = ""
        first.renamePresentationHandler = { renameTarget = "first" }
        second.renamePresentationHandler = { renameTarget = "second" }

        first.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: first.window))
        XCTAssertTrue(delegate.frontController === first)
        XCTAssertTrue(first.model.isDirty)
        XCTAssertTrue(first.model.isReady)
        XCTAssertEqual(first.model.currentURL, firstURL)
        delegate.saveDocument(nil)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        delegate.renameDocument(nil)
        XCTAssertEqual(try? String(contentsOf: firstURL, encoding: .utf8), "# First edited\n")
        XCTAssertEqual(try? String(contentsOf: secondURL, encoding: .utf8), "# Second\n")
        XCTAssertEqual(renameTarget, "first")

        second.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: second.window))
        XCTAssertTrue(delegate.frontController === second)
        XCTAssertTrue(second.model.isDirty)
        XCTAssertTrue(second.model.isReady)
        XCTAssertEqual(second.model.currentURL, secondURL)
        delegate.saveDocument(nil)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        delegate.renameDocument(nil)
        XCTAssertEqual(try? String(contentsOf: secondURL, encoding: .utf8), "# Second edited\n")
        XCTAssertEqual(renameTarget, "second")
    }
}

private func menuItem(representedObject: Any?) -> NSMenuItem {
    let item = NSMenuItem()
    item.representedObject = representedObject
    return item
}

private final class RecordingEditorBridge: EditorBridge {
    var markdown: String
    var anchors: [String] = []

    init(markdown: String) {
        self.markdown = markdown
    }

    func setMarkdown(_ markdown: String) { self.markdown = markdown }
    func reloadMarkdown(_ markdown: String) { self.markdown = markdown }
    func getMarkdown(_ completion: @escaping (String?) -> Void) { completion(markdown) }
    func getHTML(_ completion: @escaping (String?) -> Void) { completion("<p>ok</p>") }
    func applyTheme(uiMode: String, css: String, codeTheme: String, background: String) {}
    func setMode(_ mode: String) {}
    func setOutline(_ on: Bool) {}
    func setFocusMode(_ on: Bool) {}
    func setTypewriter(_ on: Bool) {}
    func setAutoPair(_ on: Bool) {}
    func scrollToHeading(_ index: Int) {}
    func scrollToAnchor(_ fragment: String) { anchors.append(fragment) }
    func find(_ query: String, backward: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {}
    func revealSearchMatch(lineNumber: Int, sourceColumn: Int, sourceLength: Int, matchOrdinal: Int, matchedText: String, query: String, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {}
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
