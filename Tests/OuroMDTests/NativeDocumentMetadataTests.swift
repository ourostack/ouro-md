import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class NativeDocumentMetadataTests: XCTestCase {
    func testMovingDocumentPreservesPendingEditsAndOriginalBytes() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Plan.md")
        let destination = directory.appendingPathComponent("Moved/Plan.md")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        let bytes = Data("# Plan\r\n\r\nOriginal text.\r\n".utf8)
        try bytes.write(to: original)
        let model = AppModel()
        model.autoSaveEnabled = false
        defer { model.teardown() }
        XCTAssertTrue(model.loadInitialFile(original.path))
        model.setDirty(true)

        try model.moveCurrentFile(to: destination)

        XCTAssertEqual(model.currentURL, destination)
        XCTAssertTrue(model.isDirty)
        XCTAssertFalse(model.deletedOnDisk)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    func testMoveCollisionLeavesBothDocumentsAndIdentityUntouched() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Plan.md")
        let destination = directory.appendingPathComponent("Other.md")
        try Data("original".utf8).write(to: original)
        try Data("other".utf8).write(to: destination)
        let model = AppModel()
        defer { model.teardown() }
        XCTAssertTrue(model.loadInitialFile(original.path))

        XCTAssertThrowsError(try model.moveCurrentFile(to: destination))

        XCTAssertEqual(model.currentURL, original)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "other")
        XCTAssertFalse(model.deletedOnDisk)
    }

    func testNativeMetadataAttachesToExistingUnorderedWindowWithoutOwningBuffer() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        try Data("public plan".utf8).write(to: file)
        let controller = makeController(file: file)
        defer { controller.window.close() }
        let document = try XCTUnwrap(controller.nativeDocument)

        XCTAssertTrue(document.windowForSheet === controller.window)
        XCTAssertTrue(controller.window.delegate === controller,
                      "Native document association must not replace the app's close/teardown delegate")
        XCTAssertEqual(document.fileURL, file)
        XCTAssertEqual(document.fileType, "net.daringfireball.markdown")
        XCTAssertTrue(document.writableTypes(for: .saveOperation).contains("net.daringfireball.markdown"),
                      "The native controls require the adapter to declare the file types it can save through AppModel")
        XCTAssertFalse(document.isDocumentEdited, "AppModel alone owns content autosave and unsaved-close prompts")
        XCTAssertFalse(controller.window.isVisible)
        XCTAssertThrowsError(try document.data(ofType: "net.daringfireball.markdown"),
                            "The metadata document must never write a cached disk buffer")
    }

    func testNativeMoveRetargetsModelAndPreservesDirtyState() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        let destination = directory.appendingPathComponent("Revised.md")
        try Data("public plan".utf8).write(to: file)
        let controller = makeController(file: file)
        controller.model.autoSaveEnabled = false
        defer { controller.window.close() }
        controller.model.setDirty(true)
        let document = try XCTUnwrap(controller.nativeDocument)
        let moved = expectation(description: "native metadata move")

        document.move(to: destination) { error in
            XCTAssertNil(error)
            moved.fulfill()
        }
        wait(for: [moved], timeout: 2)
        controller.syncChrome()

        XCTAssertEqual(controller.model.currentURL, destination)
        XCTAssertEqual(document.fileURL, destination)
        XCTAssertEqual(controller.window.representedURL, destination)
        XCTAssertEqual(controller.window.title, "Revised.md")
        XCTAssertTrue(controller.model.isDirty)
        XCTAssertFalse(controller.model.deletedOnDisk)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "public plan")
        XCTAssertFalse(controller.window.isVisible)
    }

    func testSavedFilenameClickRoutesToNativeDocumentControls() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        try Data("public plan".utf8).write(to: file)
        let controller = makeController(file: file)
        defer { controller.window.close() }
        let window = try XCTUnwrap(controller.window as? DocumentWindow)

        window.layoutIfNeeded()
        XCTAssertNotNil(window.onTitleClicked,
                        "The filename text must open the document controls, not merely the small native arrow")
        XCTAssertNotNil(window.titleHitView?())
        var presented = false
        controller.renamePresentationHandler = { presented = true }
        controller.presentDocumentControlsFromTitleClick()
        XCTAssertTrue(presented)
        XCTAssertTrue(controller.nativeDocument?.windowForSheet === window)
        XCTAssertFalse(window.isVisible)
    }

    func testMetadataCannotChangeFileIdentityWhileLiveSaveIsWaiting() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        let destination = directory.appendingPathComponent("Moved.md")
        try Data("original".utf8).write(to: file)
        let model = AppModel()
        model.autoSaveEnabled = false
        let bridge = MetadataBridge()
        model.bridge = bridge
        defer { model.teardown() }
        model.editorDidBecomeReady()
        XCTAssertTrue(model.loadInitialFile(file.path))
        model.setDirty(true)
        bridge.deferRead = true
        var saved: Bool?
        model.performSave { saved = $0 }
        XCTAssertNil(saved)

        XCTAssertThrowsError(try model.moveCurrentFile(to: destination),
                            "Moving during a live save would let its callback recreate the old file")

        bridge.pendingRead?("human feedback")
        XCTAssertEqual(saved, true)
        XCTAssertEqual(model.currentURL, file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "human feedback")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSaveAsCannotReplaceIdentityWhileAnotherLiveSaveIsWaiting() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Plan.md")
        let destination = directory.appendingPathComponent("Copy.md")
        try Data("original".utf8).write(to: original)
        let model = AppModel()
        model.autoSaveEnabled = false
        model.presentErrorHandler = { _, _ in }
        let bridge = MetadataBridge()
        model.bridge = bridge
        defer { model.teardown() }
        model.editorDidBecomeReady()
        XCTAssertTrue(model.loadInitialFile(original.path))
        model.setDirty(true)
        bridge.deferRead = true
        model.performSave { _ in }
        var copied: Bool?

        model.performSaveAs(to: destination) { copied = $0 }

        XCTAssertEqual(copied, false)
        XCTAssertEqual(model.currentURL, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        bridge.pendingRead?("human feedback")
    }

    func testNativeLockPreventsAssistantEditsAndUnlockRestoresEditing() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        try Data("public plan".utf8).write(to: file)
        let controller = makeController(file: file)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
            controller.window.close()
        }
        let document = try XCTUnwrap(controller.nativeDocument)
        let locked = expectation(description: "locked")
        document.lock(completionHandler: { (error: Error?) in
            XCTAssertNil(error)
            locked.fulfill()
        })
        wait(for: [locked], timeout: 3)

        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.immutable] as? Bool, true)
        XCTAssertTrue(controller.model.isFileLocked)
        XCTAssertFalse(controller.model.applyAssistantEdit("must not replace locked text"))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "public plan")

        let unlocked = expectation(description: "unlocked")
        document.unlock(completionHandler: { (error: Error?) in
            XCTAssertNil(error)
            unlocked.fulfill()
        })
        wait(for: [unlocked], timeout: 3)
        XCTAssertFalse(controller.model.isFileLocked)
        XCTAssertTrue(controller.model.applyAssistantEdit("allowed after unlock"))
        XCTAssertFalse(controller.window.isVisible)
    }

    func testNativeSaveFailsWithoutLiveEditorAndPreservesFileBytes() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        try Data("original bytes".utf8).write(to: file)
        let controller = makeController(file: file)
        controller.model.autoSaveEnabled = false
        defer { controller.window.close() }
        controller.model.setDirty(true)
        let document = try XCTUnwrap(controller.nativeDocument)
        var saveError: Error?
        document.save(to: file, ofType: "net.daringfireball.markdown", for: .saveOperation) {
            saveError = $0
        }
        XCTAssertNotNil(saveError)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original bytes")
        XCTAssertTrue(controller.model.isDirty)
        XCTAssertFalse(controller.window.isVisible)
    }

    func testNativeSaveToDoesNotSilentlyAdoptAnotherFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        let copy = directory.appendingPathComponent("Copy.md")
        try Data("original bytes".utf8).write(to: file)
        let controller = makeController(file: file)
        defer { controller.window.close() }
        let document = try XCTUnwrap(controller.nativeDocument)
        var saveError: Error?
        document.save(to: copy, ofType: "net.daringfireball.markdown", for: .saveToOperation) {
            saveError = $0
        }
        XCTAssertNotNil(saveError, "Unsupported copy/version operations must not pretend to be Save As")
        XCTAssertEqual(controller.model.currentURL, file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    func testLockWritesPendingHumanFeedbackBeforeProtectingTheFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Plan.md")
        try Data("original".utf8).write(to: file)
        let controller = makeController(file: file)
        let bridge = MetadataBridge()
        controller.model.bridge = bridge
        controller.model.autoSaveEnabled = false
        controller.model.editorDidBecomeReady()
        bridge.content = "human feedback"
        controller.model.setDirty(true)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path)
            controller.window.close()
        }
        let document = try XCTUnwrap(controller.nativeDocument)
        let locked = expectation(description: "pending edit locked safely")
        document.lock(completionHandler: { (error: Error?) in
            XCTAssertNil(error)
            locked.fulfill()
        })
        wait(for: [locked], timeout: 3)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "human feedback")
        XCTAssertFalse(controller.model.isDirty)
        XCTAssertTrue(controller.model.isFileLocked)
        XCTAssertEqual(bridge.editable, false)
    }

    private func makeController(file: URL) -> DocumentWindowController {
        let controller = DocumentWindowController(filePath: file.path, selfTest: false, useAutosave: false)
        controller.model.autoSaveEnabled = false
        controller.model.presentErrorHandler = { message, error in
            XCTFail("\(message): \(error)")
        }
        return controller
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-native-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private final class MetadataBridge: EditorBridge {
        var deferRead = false
        var pendingRead: ((String?) -> Void)?
        var content = ""
        var editable = true
        func setMarkdown(_ markdown: String) { content = markdown }
        func reloadMarkdown(_ markdown: String) { content = markdown }
        func getMarkdown(_ completion: @escaping (String?) -> Void) {
            if deferRead { pendingRead = completion } else { completion(content) }
        }
        func getHTML(_ completion: @escaping (String?) -> Void) { completion("") }
        func applyTheme(uiMode: String, css: String, codeTheme: String, background: String) {}
        func setMode(_ mode: String) {}
        func setOutline(_ on: Bool) {}
        func setFocusMode(_ on: Bool) {}
        func setTypewriter(_ on: Bool) {}
        func setAutoPair(_ on: Bool) {}
        func setEditable(_ editable: Bool) { self.editable = editable }
        func scrollToHeading(_ index: Int) {}
        func find(_ query: String, backward: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {}
        func revealSearchMatch(lineNumber: Int, sourceColumn: Int, sourceLength: Int, matchOrdinal: Int,
                               matchedText: String, query: String, caseSensitive: Bool,
                               wholeWord: Bool, regexp: Bool) {}
        func replace(_ query: String, with replacement: String, all: Bool, caseSensitive: Bool,
                     wholeWord: Bool, regexp: Bool, completion: @escaping (Int) -> Void) { completion(0) }
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
}
