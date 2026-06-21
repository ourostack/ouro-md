import XCTest
@testable import OuroMD

/// Records bridge calls so we can assert the model drives the editor correctly.
private final class MockBridge: EditorBridge {
    var current = ""
    var reloads: [String] = []
    var getMarkdownCalls = 0
    var onReload: ((String) -> Void)?
    var returnsNilMarkdown = false
    struct RevealedMatch: Equatable {
        var lineNumber: Int
        var sourceColumn: Int
        var sourceLength: Int
        var matchOrdinal: Int
        var matchedText: String
        var query: String
        var caseSensitive: Bool
        var wholeWord: Bool
        var regexp: Bool
    }
    var revealedMatches: [RevealedMatch] = []

    func setMarkdown(_ markdown: String) { current = markdown }
    func reloadMarkdown(_ markdown: String) { current = markdown; reloads.append(markdown); onReload?(markdown) }
    func getMarkdown(_ completion: @escaping (String?) -> Void) {
        getMarkdownCalls += 1
        completion(returnsNilMarkdown ? nil : current)
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
    func revealSearchMatch(
        lineNumber: Int,
        sourceColumn: Int,
        sourceLength: Int,
        matchOrdinal: Int,
        matchedText: String,
        query: String,
        caseSensitive: Bool,
        wholeWord: Bool,
        regexp: Bool
    ) {
        revealedMatches.append(RevealedMatch(
            lineNumber: lineNumber,
            sourceColumn: sourceColumn,
            sourceLength: sourceLength,
            matchOrdinal: matchOrdinal,
            matchedText: matchedText,
            query: query,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            regexp: regexp
        ))
    }
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
    typealias TelemetryEvent = (event: String, properties: [String: OuroMDTelemetryValue])

    private final class TelemetryRecorder {
        var events: [TelemetryEvent] = []
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-reload-\(UUID().uuidString).md")
    }

    private func recordTelemetry(on model: AppModel) -> TelemetryRecorder {
        let recorder = TelemetryRecorder()
        model.telemetryHandler = { event, properties in
            recorder.events.append((event, properties))
        }
        return recorder
    }

    private func telemetryStrings(_ events: [TelemetryEvent]) -> [String] {
        events.flatMap { event, properties in
            [event] + properties.flatMap { key, value -> [String] in
                switch value {
                case let .string(value):
                    return [key, value]
                case let .int(value):
                    return [key, String(value)]
                case let .double(value):
                    return [key, String(value)]
                case let .bool(value):
                    return [key, String(value)]
                }
            }
        }
    }

    private func assertTelemetry(
        _ events: [TelemetryEvent],
        contains event: String,
        properties expected: [String: OuroMDTelemetryValue],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let match = events.first { candidate in
            candidate.event == event && expected.allSatisfy { candidate.properties[$0.key] == $0.value }
        }
        XCTAssertNotNil(match, "Missing telemetry event \(event) with \(expected); got \(events)", file: file, line: line)
    }

    private func assertTelemetryDoesNotLeak(
        _ events: [TelemetryEvent],
        forbidden values: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let strings = telemetryStrings(events)
        for value in values where !value.isEmpty {
            XCTAssertFalse(
                strings.contains { $0.contains(value) },
                "Telemetry leaked forbidden value \(value) in \(strings)",
                file: file,
                line: line
            )
        }
    }

    /// The core agent↔human loop: an agent rewrites the open file; ouro-md must
    /// push the new content into the editor without a relaunch.
    func testExternalEditTriggersLiveReload() {
        let url = tempFile()
        try? "# Original\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
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
        assertTelemetry(recorder.events, contains: "ouro_md_document_external_reload_completed", properties: [:])
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent, "Updated by agent"])
    }

    func testExternalEditBeforeEditorReadyQueuesReloadWithoutFalseCompletion() {
        let url = tempFile()
        try? "# Original\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.loadInitialFile(url.path)

        let queued = expectation(description: "external edit queued before editor ready")
        queued.assertForOverFulfill = false
        model.telemetryHandler = { event, properties in
            recorder.events.append((event, properties))
            if event == "ouro_md_document_external_reload_queued" { queued.fulfill() }
        }

        try? "# Updated before ready\n".write(to: url, atomically: true, encoding: .utf8)
        wait(for: [queued], timeout: 6)

        XCTAssertTrue(bridge.reloads.isEmpty, "not-ready editor should not receive a completed reload")
        XCTAssertFalse(recorder.events.contains { $0.event == "ouro_md_document_external_reload_completed" })

        model.editorDidBecomeReady()
        XCTAssertEqual(bridge.current, "# Updated before ready\n")
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_external_reload_queued",
            properties: ["reason": .string("editor_not_ready")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent, "Updated before ready"])
    }

    func testEditorCrashRecoveryEmitsCompletionAfterRecoveredContentReachesBridge() {
        let url = tempFile()
        try? "# Disk recovery\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        bridge.current = ""
        model.editorCrashed()
        XCTAssertFalse(recorder.events.contains { $0.event == "ouro_md_editor_webview_recovery_completed" })

        model.editorDidBecomeReady()

        XCTAssertEqual(bridge.current, "# Disk recovery\n")
        assertTelemetry(recorder.events, contains: "ouro_md_editor_webview_crashed", properties: [:])
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_editor_webview_recovery_completed",
            properties: ["source": .string("disk")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent, "Disk recovery"])
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
        let unexpectedReload = expectation(description: "own save reloaded")
        unexpectedReload.isInverted = true
        bridge.onReload = { _ in unexpectedReload.fulfill() }

        let saved = expectation(description: "own save completed")
        model.performSave { ok in
            XCTAssertTrue(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)
        wait(for: [unexpectedReload], timeout: 1)
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
        let recorder = recordTelemetry(on: model)
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

        let done = expectation(description: "save settled")
        model.performSave { ok in
            XCTAssertTrue(ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), dirtyEditorOutput)
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_completed",
            properties: ["source": .string("manual"), "result": .string("written")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent, "Quartz"])
    }

    func testCleanSaveDoesNotRoundTripThroughEditor() {
        let url = tempFile()
        let original = "# Original\n\n"
        try? original.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        bridge.current = "# Unexpected editor normalization\n"
        let saved = expectation(description: "save completed")
        model.performSave { ok in
            XCTAssertTrue(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 3)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
        XCTAssertEqual(bridge.getMarkdownCalls, 0)
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_completed",
            properties: ["source": .string("manual"), "result": .string("clean_noop")]
        )
    }

    func testCleanPerformSaveCompletesWithoutRoundTripThroughEditor() {
        let url = tempFile()
        let original = "# Original\n\n"
        try? original.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        let saved = expectation(description: "clean save completed")
        model.performSave { ok in
            XCTAssertTrue(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 1)

        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
        XCTAssertEqual(bridge.getMarkdownCalls, 0)
    }

    func testSaveAsCleanDocumentWritesNewDestination() {
        let source = tempFile()
        let destination = tempFile()
        let original = "# Original\n\n"
        try? original.write(to: source, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(source.path)

        let saved = expectation(description: "save as completed")
        model.performSaveAs(to: destination) { ok in
            XCTAssertTrue(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(try? String(contentsOf: destination, encoding: .utf8), original)
        XCTAssertEqual(model.currentURL, destination)
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_completed",
            properties: ["source": .string("save_as_copy"), "result": .string("written")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [source.path, destination.path, "Original"])
    }

    func testSaveAsCleanNonUTF8DocumentCopiesOriginalBytes() {
        let source = tempFile()
        let destination = tempFile()
        let original = "# Cafe\n\nresume"
        let data = original.data(using: .utf16)!
        try? data.write(to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(source.path)

        let saved = expectation(description: "save as completed")
        model.performSaveAs(to: destination) { ok in
            XCTAssertTrue(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(try? Data(contentsOf: destination), data)
        XCTAssertEqual(try? String(contentsOf: destination, encoding: .utf16), original)
    }

    func testInvalidFolderRegexSetsVisibleSearchError() {
        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()

        model.searchQuery = "("
        model.searchRegexp = true
        model.openFolder(FileManager.default.temporaryDirectory)
        model.runFolderSearch()

        XCTAssertFalse(model.searching)
        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertTrue(model.searchError?.contains("Invalid regular expression") == true)
    }

    func testSearchSnippetClickRevealsCurrentFileMatch() {
        let url = tempFile()
        try? "alpha\nneedle here\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)
        model.searchQuery = "needle"

        let snippet = SearchSnippet(
            lineNumber: 2,
            text: "needle here",
            matchStart: 0,
            matchLength: 6,
            sourceMatchStart: 0,
            sourceMatchLength: 6,
            matchedText: "needle",
            matchOrdinal: 0
        )
        let result = SearchResult(
            id: url,
            url: url,
            name: url.lastPathComponent,
            parent: url.deletingLastPathComponent().lastPathComponent,
            nameMatched: false,
            snippets: [snippet]
        )

        model.openSearchResult(result, snippet: snippet)

        XCTAssertEqual(bridge.revealedMatches.last?.lineNumber, 2)
        XCTAssertEqual(bridge.revealedMatches.last?.matchedText, "needle")
        XCTAssertEqual(bridge.revealedMatches.last?.query, "needle")
        XCTAssertTrue(model.findVisible)
        XCTAssertEqual(model.findStatus, "Line 2")
    }

    func testSearchSnippetRevealUsesTrimmedQueryForPaddedFolderSearch() {
        let url = tempFile()
        try? "first needle\nsecond needle\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)
        model.searchQuery = " needle "

        let snippet = SearchSnippet(
            lineNumber: 2,
            text: "second needle",
            matchStart: 7,
            matchLength: 6,
            sourceMatchStart: 7,
            sourceMatchLength: 6,
            matchedText: "needle",
            matchOrdinal: 1
        )
        let result = SearchResult(
            id: url,
            url: url,
            name: url.lastPathComponent,
            parent: url.deletingLastPathComponent().lastPathComponent,
            nameMatched: false,
            snippets: [snippet]
        )

        model.openSearchResult(result, snippet: snippet)

        XCTAssertEqual(bridge.revealedMatches.last?.query, "needle")
        XCTAssertEqual(bridge.revealedMatches.last?.matchedText, "needle")
        XCTAssertEqual(bridge.revealedMatches.last?.matchOrdinal, 1)
        XCTAssertEqual(model.findQuery, "needle")
    }

    func testAppearanceSelectionRemembersLightThemeAcrossModelRecreation() {
        let defaults = UserDefaults.standard
        let keys = ["ouro.theme", "ouro.theme.lastLight", "ouro.theme.lastDark"]
        var saved: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) { saved[key] = value }
            defaults.removeObject(forKey: key)
        }
        defer {
            for key in keys {
                if let value = saved[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set("newsprint", forKey: "ouro.theme")

        let model = AppModel()
        XCTAssertEqual(model.themeID, "newsprint")
        model.setAppearance("dark")
        XCTAssertEqual(model.themeID, "graphite")

        let reopened = AppModel()
        XCTAssertEqual(reopened.themeID, "graphite")
        reopened.setAppearance("light")
        XCTAssertEqual(reopened.themeID, "newsprint")
    }

    func testSaveAsDirtyDocumentWritesEditorBuffer() {
        let source = tempFile()
        let destination = tempFile()
        try? "# Original\n".write(to: source, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(source.path)

        bridge.current = "# Dirty edit\n\n| A |\n| - |\n| 1 |\n"
        model.setDirty(true)

        let saved = expectation(description: "save as completed")
        model.performSaveAs(to: destination) { ok in
            XCTAssertTrue(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(
            try? String(contentsOf: destination, encoding: .utf8),
            "# Dirty edit\n\n| A |\n| --- |\n| 1 |\n"
        )
        XCTAssertEqual(model.currentURL, destination)
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_completed",
            properties: ["source": .string("save_as"), "result": .string("written")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [source.path, destination.path, "Dirty edit"])
    }

    func testFailedSaveAsRestoresPreviousURL() {
        let source = tempFile()
        let missingDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-missing-\(UUID().uuidString)")
            .appendingPathComponent("copy.md")
        try? "# Original\n".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.presentErrorHandler = { _, _ in }
        model.editorDidBecomeReady()
        model.loadInitialFile(source.path)

        let saved = expectation(description: "save as failed")
        model.performSaveAs(to: missingDestination) { ok in
            XCTAssertFalse(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(model.currentURL, source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDestination.path))
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_failed",
            properties: ["source": .string("save_as_copy"), "code": .string("write_failed")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [source.path, missingDestination.path, "Original"])
    }

    func testFailedDirtySaveAsRestoresPreviousURL() {
        let source = tempFile()
        let missingDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-missing-\(UUID().uuidString)")
            .appendingPathComponent("copy.md")
        try? "# Original\n".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.presentErrorHandler = { _, _ in }
        model.editorDidBecomeReady()
        model.loadInitialFile(source.path)
        bridge.current = "# Dirty edit\n"
        model.setDirty(true)

        let saved = expectation(description: "save as failed")
        model.performSaveAs(to: missingDestination) { ok in
            XCTAssertFalse(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(model.currentURL, source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDestination.path))
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_failed",
            properties: ["source": .string("save_as"), "code": .string("write_failed")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [source.path, missingDestination.path, "Dirty edit"])
    }

    /// Saving before the editor has loaded must NOT overwrite the file with "".
    func testSaveBeforeEditorReadyDoesNotEmptyFile() {
        let url = tempFile()
        try? "# Important content the user must not lose".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge                // bridge present...
        model.loadInitialFile(url.path)      // ...but editorDidBecomeReady NOT called → not ready
        model.setDirty(true)

        let saved = expectation(description: "save failed")
        model.performSave { ok in
            XCTAssertFalse(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 1)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8),
                       "# Important content the user must not lose",
                       "save before the editor is ready must not clobber the file")
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_failed",
            properties: ["source": .string("manual"), "code": .string("editor_not_ready")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent, "Important content"])
    }

    func testSaveWithoutBridgeEmitsCoarseTelemetry() {
        let url = tempFile()
        try? "# Important content\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        model.loadInitialFile(url.path)
        model.editorDidBecomeReady()
        model.setDirty(true)

        let saved = expectation(description: "save failed")
        model.performSave { ok in
            XCTAssertFalse(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 1)

        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_failed",
            properties: ["source": .string("manual"), "code": .string("bridge_unavailable")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent, "Important content"])
    }

    func testSaveWhenEditorValueUnavailableEmitsCoarseTelemetry() {
        let url = tempFile()
        try? "# Important content\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        bridge.returnsNilMarkdown = true
        model.bridge = bridge
        model.loadInitialFile(url.path)
        model.editorDidBecomeReady()
        model.setDirty(true)

        let saved = expectation(description: "save failed")
        model.performSave { ok in
            XCTAssertFalse(ok)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 1)

        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_save_failed",
            properties: ["source": .string("manual"), "code": .string("editor_value_unavailable")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent, "Important content"])
    }

    func testOpenFailureTelemetryIsCoarse() {
        let url = tempFile()
        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        model.presentErrorHandler = { _, _ in }

        model.open(url: url)

        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_open_failed",
            properties: [
                "source": .string("open"),
                "code": .string("unreadable"),
                "markdown_type": .bool(true),
            ]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, url.lastPathComponent])
    }

    func testInitialUnreadableFileShowsErrorAndLoadsWelcome() {
        let url = tempFile()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppModel()
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        var errorMessage = ""
        model.bridge = bridge
        model.presentErrorHandler = { message, _ in errorMessage = message }
        model.editorDidBecomeReady()

        XCTAssertFalse(model.loadInitialFile(url.path))

        XCTAssertEqual(errorMessage, "Could not open \(url.lastPathComponent)")
        XCTAssertNil(model.currentURL)
        XCTAssertEqual(model.windowTitle, "Untitled")
        XCTAssertTrue(bridge.current.contains("# Welcome to Ouro MD"))
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_open_failed",
            properties: [
                "source": .string("launch"),
                "code": .string("unreadable"),
                "markdown_type": .bool(true),
            ]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path])
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
        let recorder = recordTelemetry(on: model)
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
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_renamed",
            properties: ["markdown_type": .bool(true)]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, renamed.path, "before.md", "after.md"])
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
        let recorder = recordTelemetry(on: model)
        let bridge = MockBridge()
        model.bridge = bridge
        model.editorDidBecomeReady()
        model.loadInitialFile(url.path)

        XCTAssertNotNil(model.renameCurrentFile(to: "b.md"), "collision should be refused")
        XCTAssertEqual(try? String(contentsOf: other, encoding: .utf8), "b", "existing file must be untouched")
        XCTAssertEqual(model.currentURL?.lastPathComponent, "a.md", "model should keep the original URL")
        assertTelemetry(
            recorder.events,
            contains: "ouro_md_document_rename_failed",
            properties: ["code": .string("collision")]
        )
        assertTelemetryDoesNotLeak(recorder.events, forbidden: [url.path, other.path, "a.md", "b.md"])
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
