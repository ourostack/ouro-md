import XCTest
@testable import OuroMDAppSupport

final class DocumentAccessBookmarksTests: XCTestCase {
    private var stored: Data?
    private var unresolvable: Set<Data> = []

    private func bookmarks(makeBookmark: ((URL) -> Data?)? = nil) -> DocumentAccessBookmarks {
        DocumentAccessBookmarks(
            load: { self.stored },
            save: { self.stored = $0 },
            makeBookmark: makeBookmark ?? { Data($0.path.utf8) },
            resolveBookmark: { data in
                self.unresolvable.contains(data) ? nil : URL(fileURLWithPath: "/scoped" + String(decoding: data, as: UTF8.self))
            }
        )
    }

    func testRecordsADocumentAndGrantsAccessToIt() {
        let store = bookmarks()
        store.record(URL(fileURLWithPath: "/Users/a/notes/plan.md"))
        XCTAssertEqual(store.grantingURL(for: URL(fileURLWithPath: "/Users/a/notes/plan.md"))?.path, "/scoped/Users/a/notes/plan.md")
        XCTAssertNil(store.grantingURL(for: URL(fileURLWithPath: "/Users/a/notes/other.md")))
    }

    func testAFolderGrantsAccessToFilesInsideItButNotToSiblingsWithTheSamePrefix() {
        let store = bookmarks()
        store.record(URL(fileURLWithPath: "/Users/a/notes", isDirectory: true))
        XCTAssertEqual(store.grantingURL(for: URL(fileURLWithPath: "/Users/a/notes/deep/plan.md"))?.path, "/scoped/Users/a/notes")
        XCTAssertNil(store.grantingURL(for: URL(fileURLWithPath: "/Users/a/notes-old/plan.md")))
    }

    func testTheRootFolderGrantsEverything() {
        let store = bookmarks()
        store.record(URL(fileURLWithPath: "/", isDirectory: true))
        XCTAssertNotNil(store.grantingURL(for: URL(fileURLWithPath: "/Users/a/plan.md")))
    }

    func testPrefersTheNearestGrantAndFallsBackWhenItNoLongerResolves() {
        let store = bookmarks()
        store.record(URL(fileURLWithPath: "/Users/a", isDirectory: true))
        store.record(URL(fileURLWithPath: "/Users/a/notes/plan.md"))
        let file = URL(fileURLWithPath: "/Users/a/notes/plan.md")
        XCTAssertEqual(store.grantingURL(for: file)?.path, "/scoped/Users/a/notes/plan.md")
        unresolvable.insert(Data("/Users/a/notes/plan.md".utf8))
        XCTAssertEqual(store.grantingURL(for: file)?.path, "/scoped/Users/a")
        unresolvable.insert(Data("/Users/a".utf8))
        XCTAssertNil(store.grantingURL(for: file))
    }

    func testReRecordingMovesToTheFrontWithoutDuplicatesAndTheListIsCapped() {
        let store = bookmarks()
        for i in 0..<(DocumentAccessBookmarks.limit + 5) {
            store.record(URL(fileURLWithPath: "/docs/\(i).md"))
        }
        store.record(URL(fileURLWithPath: "/docs/20.md"))
        let paths = store.entries.map(\.path)
        XCTAssertEqual(paths.count, DocumentAccessBookmarks.limit)
        XCTAssertEqual(paths.first, "/docs/20.md")
        XCTAssertEqual(paths.filter { $0 == "/docs/20.md" }.count, 1)
        XCTAssertFalse(paths.contains("/docs/0.md"), "the oldest entries drop off")
    }

    func testPathsAreStandardized() {
        let store = bookmarks()
        store.record(URL(fileURLWithPath: "/Users/a/./notes/../notes/plan.md"))
        XCTAssertNotNil(store.grantingURL(for: URL(fileURLWithPath: "/Users/a/notes/plan.md")))
    }

    func testNothingIsRecordedWhenNoBookmarkCanBeMade() {
        let store = bookmarks(makeBookmark: { _ in nil })
        store.record(URL(fileURLWithPath: "/Users/a/plan.md"))
        XCTAssertNil(stored)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testUnreadableStoredDataIsTreatedAsEmpty() {
        stored = Data("not json".utf8)
        XCTAssertTrue(bookmarks().entries.isEmpty)
        XCTAssertNil(bookmarks().grantingURL(for: URL(fileURLWithPath: "/a.md")))
    }
}
