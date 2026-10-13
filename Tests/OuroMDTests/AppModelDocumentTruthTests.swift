import XCTest
import OuroMDAppSupport
@testable import OuroMD

@MainActor
final class AppModelDocumentTruthTests: XCTestCase {
    func testFirstReadIsUnmarkedAndOfflineChangesCompareWithRetainedBaseline() throws {
        let root = tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        try "# Original\n".write(to: file, atomically: true, encoding: .utf8)
        let first = AppModel(readingBaselineStore: store)
        let bridge = TruthBridge()
        first.bridge = bridge
        XCTAssertTrue(first.loadInitialFile(file.path))
        first.editorDidBecomeReady()
        XCTAssertTrue(bridge.reviewComparisons.isEmpty)
        XCTAssertEqual(try store.read(for: file), "# Original\n")

        try "# Offline update\n".write(to: file, atomically: true, encoding: .utf8)
        let reopened = AppModel(readingBaselineStore: store)
        let reopenedBridge = TruthBridge()
        reopened.bridge = reopenedBridge
        XCTAssertTrue(reopened.loadInitialFile(file.path))
        XCTAssertTrue(reopenedBridge.reviewComparisons.isEmpty)
        reopened.editorDidBecomeReady()
        XCTAssertEqual(reopenedBridge.reviewComparisons, ["# Original\n"])
        XCTAssertEqual(reopenedBridge.current, "# Offline update\n")
        XCTAssertEqual(try store.read(for: file), "# Original\n")
        reopened.markCurrentReviewed()
        XCTAssertEqual(try store.read(for: file), "# Offline update\n")
        XCTAssertEqual(reopenedBridge.reviewClears, 1)
        XCTAssertFalse(reopened.isDirty)
    }

    func testUnavailableBaselineReportsErrorWithoutTreatingWholeFileAsChanged() throws {
        let root = tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        try "Current".write(to: file, atomically: true, encoding: .utf8)
        let model = AppModel(readingBaselineStore: FailingReadingBaselineStore())
        let bridge = TruthBridge()
        model.bridge = bridge
        var errors = 0
        model.presentErrorHandler = { _, _ in errors += 1 }
        model.editorDidBecomeReady()
        XCTAssertTrue(model.loadInitialFile(file.path))
        XCTAssertEqual(errors, 1)
        XCTAssertTrue(bridge.reviewComparisons.isEmpty)
        model.markCurrentReviewed()
        XCTAssertEqual(errors, 2)
        XCTAssertEqual(bridge.reviewClears, 0)
    }

    func testExternalUpdateBeforeReadyKeepsOriginalReadingBaseline() throws {
        let root = tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        let model = AppModel(readingBaselineStore: store)
        let bridge = TruthBridge()
        model.bridge = bridge
        XCTAssertTrue(model.loadInitialFile(file.path))
        try "Agent update".write(to: file, atomically: true, encoding: .utf8)
        model.reconcileExternalChangeForTesting()
        model.markCurrentReviewed()
        XCTAssertEqual(try store.read(for: file), "Original")
        model.editorDidBecomeReady()
        XCTAssertEqual(bridge.current, "Agent update")
        XCTAssertEqual(bridge.reviewComparisons, ["Original"])
        XCTAssertEqual(model.readingReviewStatus, "Changes since last review")
    }

    func testLateAcknowledgementCannotAcknowledgeReopenedDocument() throws {
        let root = tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        let model = AppModel(readingBaselineStore: store)
        let bridge = TruthBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        XCTAssertTrue(model.loadInitialFile(file.path))
        bridge.deferMarkdown = true
        model.markCurrentReviewed()
        try "Reopened content".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(model.loadInitialFile(file.path))
        bridge.markdownCompletion?("Stale callback")
        XCTAssertEqual(try store.read(for: file), "Original")
        XCTAssertEqual(bridge.reviewClears, 0)
    }

    func testAcknowledgementKeepsNewExternalEditVisible() throws {
        let root = tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        let model = AppModel(readingBaselineStore: store)
        let bridge = TruthBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        XCTAssertTrue(model.loadInitialFile(file.path))
        bridge.deferMarkdown = true
        model.markCurrentReviewed()
        try "New unseen content".write(to: file, atomically: true, encoding: .utf8)
        model.reconcileExternalChangeForTesting()
        bridge.markdownCompletion?("Original")
        XCTAssertEqual(try store.read(for: file), "Original")
        XCTAssertEqual(bridge.reviewClears, 0)
        XCTAssertEqual(bridge.reviewComparisons.last, "Original")
        XCTAssertEqual(model.readingReviewStatus, "Changes since last review")
    }

    func testRenamePreservesReviewBaselineWithoutAcknowledgingChanges() throws {
        let root = tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        let renamed = root.appendingPathComponent("renamed.md")
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        let model = AppModel(readingBaselineStore: store)
        XCTAssertTrue(model.loadInitialFile(file.path))
        try "Unreviewed".write(to: file, atomically: true, encoding: .utf8)
        model.reconcileExternalChangeForTesting()
        XCTAssertNil(model.renameCurrentFile(to: "renamed.md"))
        XCTAssertEqual(try store.read(for: renamed), "Original")
        try "Unrelated new file".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(try store.read(for: file))
    }

    func testDelayedAcknowledgementDoesNotReviewSubsequentLocalEdits() throws {
        let root = tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        let store = ReadingBaselineStore(directory: root.appendingPathComponent("baselines"))
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        let model = AppModel(readingBaselineStore: store)
        let bridge = TruthBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        XCTAssertTrue(model.loadInitialFile(file.path))
        bridge.deferMarkdown = true
        model.markCurrentReviewed()
        model.setDirty(true)
        bridge.markdownCompletion?("Subsequent typing")
        XCTAssertEqual(try store.read(for: file), "Original")
        XCTAssertEqual(bridge.reviewClears, 0)
        XCTAssertEqual(model.readingReviewStatus, "Document changed: mark reviewed again")
    }

    func testTruthRefreshesAcrossWelcomeLoadDirtySaveRenameSaveAsAndNewDocument() {
        let repo = tempDirectory()
        let original = repo.appendingPathComponent("note.md")
        let savedAs = repo.appendingPathComponent("copy.md")
        try? "# Note\n".write(to: original, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: repo) }

        var status = ""
        let model = AppModel()
        let bridge = TruthBridge()
        bridge.current = "# Note\n"
        model.bridge = bridge
        model.documentTruthProvider = provider(repo: repo, status: { status })

        XCTAssertEqual(model.documentTruth.state, .untitled)
        XCTAssertEqual(model.documentTruthDisplayLabel, "Untitled")

        model.loadWelcome()
        XCTAssertEqual(model.documentTruth.state, .untitled)

        model.editorDidBecomeReady()
        model.loadInitialFile(original.path)
        XCTAssertEqual(model.documentTruth.state, .trackedClean)
        XCTAssertEqual(model.documentTruth.relativePath, "note.md")
        XCTAssertEqual(model.documentTruthDisplayLabel, "Tracked · Clean")

        status = " M note.md\n"
        model.setDirty(true)
        XCTAssertEqual(model.documentTruth.state, .trackedModified)
        XCTAssertEqual(model.documentTruthDisplayLabel, "Modified · visible in git diff · unsaved")

        let saved = expectation(description: "saved")
        bridge.current = "# Note\n\nHuman feedback.\n"
        model.performSave { ok in
            XCTAssertTrue(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.documentTruth.state, .trackedModified)
        XCTAssertEqual(model.documentTruthDisplayLabel, "Modified · visible in git diff")

        XCTAssertNil(model.renameCurrentFile(to: "renamed.md"))
        XCTAssertEqual(model.documentTruth.relativePath, "renamed.md")

        status = "MM copy.md\n"
        let copied = expectation(description: "saved as")
        model.setDirty(true)
        bridge.current = "# Copy\n"
        model.performSaveAs(to: savedAs) { ok in
            XCTAssertTrue(ok)
            copied.fulfill()
        }
        wait(for: [copied], timeout: 2)
        XCTAssertEqual(model.currentURL, savedAs)
        XCTAssertEqual(model.documentTruth.state, .trackedMixed)
        XCTAssertEqual(model.documentTruth.relativePath, "copy.md")

        model.newDocument()
        XCTAssertEqual(model.documentTruth.state, .untitled)
        XCTAssertEqual(model.documentTruthDisplayLabel, "Untitled")
    }

    func testDeletedAndRestoredFilesRefreshTruthWithoutMarkingGitCertainty() {
        let repo = tempDirectory()
        let file = repo.appendingPathComponent("note.md")
        try? "# Note\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: repo) }

        let model = AppModel()
        model.documentTruthProvider = provider(repo: repo, status: { "" })
        model.loadInitialFile(file.path)
        XCTAssertEqual(model.documentTruth.state, .trackedClean)

        try? FileManager.default.removeItem(at: file)
        model.markDeletedOnDiskForTesting()
        XCTAssertEqual(model.documentTruth.state, .unavailable)
        XCTAssertEqual(model.documentTruthDisplayLabel, "Deleted on disk")

        try? "# Back\n".write(to: file, atomically: true, encoding: .utf8)
        model.reconcileExternalChangeForTesting()
        XCTAssertEqual(model.documentTruth.state, .trackedClean)
        XCTAssertEqual(model.documentTruthDisplayLabel, "Tracked · Clean")
    }

    func testExternalReloadRefreshesTruthAfterAgentWritesFile() {
        let repo = tempDirectory()
        let file = repo.appendingPathComponent("note.md")
        try? "# Note\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: repo) }

        var status = ""
        let model = AppModel()
        let bridge = TruthBridge()
        model.bridge = bridge
        model.documentTruthProvider = provider(repo: repo, status: { status })
        model.editorDidBecomeReady()
        model.loadInitialFile(file.path)
        XCTAssertEqual(model.documentTruth.state, .trackedClean)

        status = " M note.md\n"
        try? "# Agent update\n".write(to: file, atomically: true, encoding: .utf8)
        model.reconcileExternalChangeForTesting()

        XCTAssertEqual(bridge.reloads.last, "# Agent update\n")
        XCTAssertEqual(model.documentTruth.state, .trackedModified)
        XCTAssertEqual(model.documentTruthDisplayLabel, "Modified · visible in git diff")
    }

    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-truth-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func provider(repo: URL, status: @escaping () -> String) -> DocumentTruthProvider {
        DocumentTruthProvider(
            gitRunner: LifecycleGitRunner { command, _ in
                switch command.arguments {
                case ["rev-parse", "--show-toplevel"]:
                    return DocumentTruthGitResult(exitCode: 0, stdout: repo.path, stderr: "")
                case let args where args.count == 4 && Array(args.prefix(3)) == ["ls-files", "--error-unmatch", "--"]:
                    return DocumentTruthGitResult(exitCode: 0, stdout: args[3], stderr: "")
                case let args where args.count == 4 && Array(args.prefix(3)) == ["status", "--porcelain=v1", "--"]:
                    return DocumentTruthGitResult(exitCode: 0, stdout: status(), stderr: "")
                default:
                    XCTFail("Unexpected command: \(command.arguments)")
                    return DocumentTruthGitResult(exitCode: 1, stdout: "", stderr: "unexpected")
                }
            },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
    }
}

private struct LifecycleGitRunner: DocumentTruthGitRunning {
    let handler: (DocumentTruthGitCommand, URL) -> DocumentTruthGitResult

    func run(_ command: DocumentTruthGitCommand, workingDirectory: URL) throws -> DocumentTruthGitResult {
        handler(command, workingDirectory)
    }
}

private final class TruthBridge: EditorBridge {
    var current = ""
    var reloads: [String] = []
    var reviewComparisons: [String] = []
    var reviewClears = 0
    var deferMarkdown = false
    var markdownCompletion: ((String?) -> Void)?

    func showChanges(since markdown: String) { reviewComparisons.append(markdown) }
    func clearChangeReview() { reviewClears += 1 }

    func setMarkdown(_ markdown: String) { current = markdown }
    func reloadMarkdown(_ markdown: String) { current = markdown; reloads.append(markdown) }
    func getMarkdown(_ completion: @escaping (String?) -> Void) {
        if deferMarkdown { markdownCompletion = completion }
        else { completion(current) }
    }
    func getHTML(_ completion: @escaping (String?) -> Void) { completion("") }
    func applyTheme(uiMode: String, css: String, codeTheme: String, background: String) {}
    func setMode(_ mode: String) {}
    func setOutline(_ on: Bool) {}
    func setFocusMode(_ on: Bool) {}
    func setTypewriter(_ on: Bool) {}
    func setAutoPair(_ on: Bool) {}
    func scrollToHeading(_ index: Int) {}
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

private struct FailingReadingBaselineStore: ReadingBaselineStoring {
    func read(for file: URL) throws -> String? { throw CocoaError(.fileReadCorruptFile) }
    func write(_ markdown: String, for file: URL) throws { throw CocoaError(.fileWriteNoPermission) }
    func remove(for file: URL) throws { throw CocoaError(.fileWriteNoPermission) }
}
