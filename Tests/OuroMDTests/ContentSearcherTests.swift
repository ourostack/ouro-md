import XCTest
@testable import OuroMD

final class ContentSearcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "The widget renders fast.\nSecond line.".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "# Widget guide\nAll about the widget here.".write(to: root.appendingPathComponent("widget.md"), atomically: true, encoding: .utf8)
        try "Nothing relevant.".write(to: root.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)
        try "# Widget root readme\nThe widget also lives here.".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("guides"), withIntermediateDirectories: true)
        try "# Widget readme\nThe widget lives here.".write(to: root.appendingPathComponent("guides/README.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testStreamsRankedResultsWithSnippets() {
        let searcher = ContentSearcher()
        var results: [SearchResult] = []
        let done = expectation(description: "search complete")
        var completion: SearchCompletion?
        searcher.search("widget", in: root, caseSensitive: false, wholeWord: false, regexp: false,
                        onResult: { results.append($0) },
                        onComplete: {
                            completion = $0
                            done.fulfill()
                        })
        wait(for: [done], timeout: 30)
        XCTAssertEqual(completion, .empty)

        let names = results.map(\.name)
        XCTAssertTrue(names.contains("widget.md"))
        XCTAssertTrue(names.contains("notes.md"))
        XCTAssertTrue(names.contains("README.md"))
        XCTAssertFalse(names.contains("other.md"))

        // Filename hit ("widget.md") ranks first.
        XCTAssertEqual(results.sorted { a, b in
            if a.nameMatched != b.nameMatched { return a.nameMatched }
            return a.count > b.count
        }.first?.name, "widget.md")

        // Snippet carries the match offset for highlighting.
        if let notes = results.first(where: { $0.name == "notes.md" }) {
            XCTAssertGreaterThan(notes.snippets.first?.matchLength ?? 0, 0)
            XCTAssertEqual(notes.parent, root.lastPathComponent)
            XCTAssertEqual(notes.snippets.first?.sourceMatchStart, 4)
            XCTAssertEqual(notes.snippets.first?.matchedText.lowercased(), "widget")
            XCTAssertEqual(notes.snippets.first?.matchOrdinal, 0)
        }
        let readmeParents = Set(results.filter { $0.name == "README.md" }.map(\.parent))
        XCTAssertEqual(readmeParents, Set([root.lastPathComponent, "guides"]))
    }

    func testCaseSensitiveOption() {
        let lowercase = "widget" as NSString
        let uppercase = "WIDGET" as NSString

        let sensitive = ContentSearcher.makeRegex("WIDGET", caseSensitive: true, wholeWord: false, regexp: false)
        XCTAssertNil(sensitive?.firstMatch(in: lowercase as String, range: NSRange(location: 0, length: lowercase.length)))
        XCTAssertNotNil(sensitive?.firstMatch(in: uppercase as String, range: NSRange(location: 0, length: uppercase.length)))

        let insensitive = ContentSearcher.makeRegex("WIDGET", caseSensitive: false, wholeWord: false, regexp: false)
        XCTAssertNotNil(insensitive?.firstMatch(in: lowercase as String, range: NSRange(location: 0, length: lowercase.length)))
    }

    func testInvalidRegularExpressionReportsValidationError() {
        let error = ContentSearcher.regexError("(", caseSensitive: false, wholeWord: false, regexp: true)

        XCTAssertNotNil(error)
        XCTAssertNil(ContentSearcher.makeRegex("(", caseSensitive: false, wholeWord: false, regexp: true))
        XCTAssertNil(ContentSearcher.regexError("(", caseSensitive: false, wholeWord: false, regexp: false))
    }

    func testTruncatedSnippetKeepsSourceCoordinates() {
        let longPrefix = String(repeating: "a", count: 140)
        let path = root.appendingPathComponent("long.md")
        try? "\(longPrefix)needle trailing context\n".write(to: path, atomically: true, encoding: .utf8)

        let searcher = ContentSearcher()
        var results: [SearchResult] = []
        let done = expectation(description: "search complete")
        searcher.search("needle", in: root, caseSensitive: false, wholeWord: false, regexp: false,
                        onResult: { results.append($0) },
                        onComplete: { _ in done.fulfill() })
        wait(for: [done], timeout: 30)

        let snippet = results.first { $0.name == "long.md" }?.snippets.first
        XCTAssertEqual(snippet?.sourceMatchStart, 140)
        XCTAssertEqual(snippet?.sourceMatchLength, 6)
        XCTAssertEqual(snippet?.matchedText, "needle")
        XCTAssertNotEqual(snippet?.matchStart, snippet?.sourceMatchStart)
    }

    func testMatchOrdinalCountsEarlierOccurrencesOnSameLine() {
        let path = root.appendingPathComponent("ordinals.md")
        try? "needle needle\nneedle later\n".write(to: path, atomically: true, encoding: .utf8)

        let searcher = ContentSearcher()
        var results: [SearchResult] = []
        let done = expectation(description: "search complete")
        searcher.search("needle", in: root, caseSensitive: false, wholeWord: false, regexp: false,
                        onResult: { results.append($0) },
                        onComplete: { _ in done.fulfill() })
        wait(for: [done], timeout: 30)

        let snippets = results.first { $0.name == "ordinals.md" }?.snippets
        XCTAssertEqual(snippets?.map(\.lineNumber), [1, 2])
        XCTAssertEqual(snippets?.map(\.matchOrdinal), [0, 2])
    }

    func testBinaryAndUnreadableMarkdownFilesAreSkippedWithoutLeakingPaths() {
        try? Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: root.appendingPathComponent("binary.md"))
        let unreadable = root.appendingPathComponent("unreadable.md")
        try? "widget but unreadable".write(to: unreadable, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path)
        }

        let searcher = ContentSearcher()
        var results: [SearchResult] = []
        var completion: SearchCompletion?
        let done = expectation(description: "search complete")
        searcher.search("widget", in: root, caseSensitive: false, wholeWord: false, regexp: false,
                        onResult: { results.append($0) },
                        onComplete: {
                            completion = $0
                            done.fulfill()
                        })
        wait(for: [done], timeout: 30)

        XCTAssertEqual(completion?.skippedBinaryCount, 1)
        XCTAssertEqual(completion?.skippedUnreadableCount, 1)
        XCTAssertFalse(results.contains { $0.name == "binary.md" })
        XCTAssertFalse(results.contains { $0.name == "unreadable.md" })
    }

    func testSearchCanBeCancelledBeforeCompletion() {
        let searcher = ContentSearcher()
        let didComplete = expectation(description: "cancelled search completed")
        didComplete.isInverted = true

        for i in 0..<1_200 {
            let file = root.appendingPathComponent(String(format: "cancel-%04d.md", i))
            try? "needle \(i)\n".write(to: file, atomically: true, encoding: .utf8)
        }

        searcher.search("needle", in: root, caseSensitive: false, wholeWord: false, regexp: false,
                        onResult: { _ in },
                        onComplete: { _ in didComplete.fulfill() })
        searcher.cancel()

        wait(for: [didComplete], timeout: 0.5)
    }

    func testAppModelPublishesSearchCancelAndFormatsSkippedFileUXState() {
        let cancelModel = AppModel()
        cancelModel.openFolder(root)
        cancelModel.searchQuery = "widget"

        cancelModel.runFolderSearch()
        cancelModel.cancelFolderSearch()

        XCTAssertFalse(cancelModel.searching)
        XCTAssertTrue(cancelModel.searchWasCancelled)

        XCTAssertNil(AppModel.searchSkippedMessage(unreadableCount: 0, binaryCount: 0))
        XCTAssertEqual(AppModel.searchSkippedMessage(unreadableCount: 0, binaryCount: 1), "Skipped 1 binary file")
        XCTAssertEqual(AppModel.searchSkippedMessage(unreadableCount: 2, binaryCount: 1), "Skipped 2 unreadable, 1 binary files")
    }

}
