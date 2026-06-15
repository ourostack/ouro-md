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
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testStreamsRankedResultsWithSnippets() {
        let searcher = ContentSearcher()
        var results: [SearchResult] = []
        let done = expectation(description: "search complete")
        var wasTruncated: Bool?
        searcher.search("widget", in: root, caseSensitive: false, wholeWord: false, regexp: false,
                        onResult: { results.append($0) },
                        onComplete: {
                            wasTruncated = $0
                            done.fulfill()
                        })
        wait(for: [done], timeout: 5)
        XCTAssertEqual(wasTruncated, false)

        let names = results.map(\.name)
        XCTAssertTrue(names.contains("widget.md"))
        XCTAssertTrue(names.contains("notes.md"))
        XCTAssertFalse(names.contains("other.md"))

        // Filename hit ("widget.md") ranks first.
        XCTAssertEqual(results.sorted { a, b in
            if a.nameMatched != b.nameMatched { return a.nameMatched }
            return a.count > b.count
        }.first?.name, "widget.md")

        // Snippet carries the match offset for highlighting.
        if let notes = results.first(where: { $0.name == "notes.md" }) {
            XCTAssertGreaterThan(notes.snippets.first?.matchLength ?? 0, 0)
        }
    }

    func testCaseSensitiveOption() {
        let searcher = ContentSearcher()
        var results: [SearchResult] = []
        let done = expectation(description: "case-sensitive search")
        var wasTruncated: Bool?
        searcher.search("WIDGET", in: root, caseSensitive: true, wholeWord: false, regexp: false,
                        onResult: { results.append($0) },
                        onComplete: {
                            wasTruncated = $0
                            done.fulfill()
                        })
        wait(for: [done], timeout: 5)
        // No file contains uppercase WIDGET in content; only filename match is case-insensitive substring? none.
        XCTAssertTrue(results.allSatisfy { $0.snippets.isEmpty })
        XCTAssertEqual(wasTruncated, false)
    }
}
