import XCTest
@testable import OuroMD

@MainActor
private final class FakeWorkspace: MarkdownDocumentWorkspace {
    var documents: [URL: String]
    var order: [URL]
    var front: URL?
    var opened: [URL] = []
    var replacements: [(URL, String)] = []

    init(_ docs: [(String, String)], front: Int? = 0) {
        order = docs.map { URL(fileURLWithPath: "/tmp/ouro-md-intents/\($0.0)") }
        documents = Dictionary(uniqueKeysWithValues: zip(order, docs.map(\.1)))
        self.front = front.map { order[$0] }
    }

    func knownDocumentURLs() -> [URL] { order + order }
    func isReadable(_ url: URL) -> Bool { documents[url] != nil }
    func frontDocumentURL() -> URL? { front }
    func markdown(for url: URL) async -> String? { documents[url] }
    func replaceMarkdown(_ markdown: String, in url: URL) async throws {
        replacements.append((url, markdown))
        documents[url] = markdown
    }
    func open(_ url: URL) { opened.append(url) }
}

@MainActor
final class DocumentIntentsTests: XCTestCase {
    private var workspace: FakeWorkspace!

    override func setUp() async throws {
        workspace = FakeWorkspace([("Plan.md", "# Plan\n\nShip it.\n"), ("Notes.md", "notes")])
        DocumentIntentsWorkspace.current = workspace
    }

    override func tearDown() async throws {
        DocumentIntentsWorkspace.current = nil
        workspace = nil
    }

    func testAppendingStartsANewParagraph() {
        XCTAssertEqual(AppendToMarkdownDocumentIntent.appending("- next", to: "# Plan\n\nShip it.\n\n\n"), "# Plan\n\nShip it.\n\n- next\n")
        XCTAssertEqual(AppendToMarkdownDocumentIntent.appending("  hello \n", to: ""), "hello\n")
        XCTAssertEqual(AppendToMarkdownDocumentIntent.appending("   ", to: "keep"), "keep")
    }

    func testQuerySuggestsKnownDocumentsOnceAndMatchesByName() async throws {
        let query = MarkdownDocumentQuery()
        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(suggested.map(\.name), ["Plan", "Notes"])
        let matched = try await query.entities(matching: "plan")
        XCTAssertEqual(matched.map(\.name), ["Plan"])
        let byID = try await query.entities(for: [suggested[1].id, "/tmp/ouro-md-intents/Missing.md"])
        XCTAssertEqual(byID.map(\.name), ["Notes"])
    }

    func testGetUsesTheDocumentOnScreenByDefault() async throws {
        let intent = GetMarkdownDocumentIntent()
        let result = try await intent.perform()
        XCTAssertEqual(result.value, "# Plan\n\nShip it.\n")
    }

    func testAppendWritesOneReplacementToTheNamedDocument() async throws {
        var intent = AppendToMarkdownDocumentIntent()
        intent.text = "More notes."
        intent.document = MarkdownDocumentEntity(url: workspace.order[1])
        _ = try await intent.perform()
        XCTAssertEqual(workspace.replacements.count, 1)
        XCTAssertEqual(workspace.replacements.first?.0, workspace.order[1])
        XCTAssertEqual(workspace.documents[workspace.order[1]], "notes\n\nMore notes.\n")
    }

    func testReplaceAndOpen() async throws {
        var replace = ReplaceMarkdownDocumentIntent()
        replace.markdown = "# New\n"
        _ = try await replace.perform()
        XCTAssertEqual(workspace.documents[workspace.order[0]], "# New\n")

        var open = OpenMarkdownDocumentIntent()
        open.document = MarkdownDocumentEntity(url: workspace.order[1])
        _ = try await open.perform()
        XCTAssertEqual(workspace.opened, [workspace.order[1]])
    }

    func testWithoutAFrontDocumentTheIntentExplainsItself() async {
        workspace.front = nil
        do {
            _ = try await GetMarkdownDocumentIntent().perform()
            XCTFail("expected noDocument")
        } catch DocumentIntentError.noDocument {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEntityTransfersItsMarkdownText() async throws {
        let entity = MarkdownDocumentEntity(url: workspace.order[0])
        let text = try await entity.markdown()
        XCTAssertEqual(text, "# Plan\n\nShip it.\n")
        XCTAssertEqual(entity.id, "/tmp/ouro-md-intents/Plan.md")
    }

    func testMarkdownDocumentURLRecognition() {
        XCTAssertTrue(AppModel.isMarkdownDocumentURL(URL(fileURLWithPath: "/x/a.md")))
        XCTAssertFalse(AppModel.isMarkdownDocumentURL(URL(fileURLWithPath: "/x/a.png")))
    }
}
