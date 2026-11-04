import XCTest
import OuroAX
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
    var refuseEdits: DocumentIntentError?
    func replaceMarkdown(_ markdown: String, in url: URL) async throws {
        if let refuseEdits { throw refuseEdits }
        replacements.append((url, markdown))
        documents[url] = markdown
    }
    func open(_ url: URL) { opened.append(url) }
}

/// Writes through to the fake but reads back the text as `readBack` changes it, as an editor might.
@MainActor
private class FakeWorkspaceProxy: MarkdownDocumentWorkspace {
    let inner: FakeWorkspace
    let readBack: (String) -> String
    init(_ inner: FakeWorkspace, readBack: @escaping (String) -> String) { self.inner = inner; self.readBack = readBack }
    func knownDocumentURLs() -> [URL] { inner.knownDocumentURLs() }
    func isReadable(_ url: URL) -> Bool { inner.isReadable(url) }
    func frontDocumentURL() -> URL? { inner.frontDocumentURL() }
    func markdown(for url: URL) async -> String? {
        await inner.markdown(for: url).map(readBack)
    }
    func replaceMarkdown(_ markdown: String, in url: URL) async throws { try await inner.replaceMarkdown(markdown, in: url) }
    func open(_ url: URL) { inner.open(url) }
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
        ReplaceMarkdownDocumentIntent.confirm = ReplaceMarkdownDocumentIntent.askThePerson
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
        var asked: [String] = []
        ReplaceMarkdownDocumentIntent.confirm = { _, prompt in asked.append(prompt) }
        var replace = ReplaceMarkdownDocumentIntent()
        replace.markdown = "# New\n"
        _ = try await replace.perform()
        XCTAssertEqual(workspace.documents[workspace.order[0]], "# New\n")
        XCTAssertEqual(asked, ["Replace all of Plan with the new Markdown?"])

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
        } catch let problem as OuroAX.Problem {
            XCTAssertEqual(problem.code, "no-document")
            XCTAssertEqual(problem.message, "Ouro MD: no Markdown document is open. Fix: Open one in Ouro MD, or name the document to use.")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testReplaceWritesNothingWhenThePersonDeclines() async {
        struct Declined: Error {}
        ReplaceMarkdownDocumentIntent.confirm = { _, _ in throw Declined() }
        var replace = ReplaceMarkdownDocumentIntent()
        replace.markdown = "# Gone\n"
        do {
            _ = try await replace.perform()
            XCTFail("expected the decline to stop the intent")
        } catch is Declined {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(workspace.replacements.isEmpty)
    }

    func testConfirmedReplaceGoesToTheDocumentThePersonWasAskedAbout() async throws {
        let plan = workspace.order[0]
        let notes = workspace.order[1]
        ReplaceMarkdownDocumentIntent.confirm = { [workspace] _, prompt in
            XCTAssertTrue(prompt.contains("Plan"), prompt)
            workspace!.front = notes // another window comes forward while the person answers
        }
        var replace = ReplaceMarkdownDocumentIntent()
        replace.markdown = "# New plan\n"
        _ = try await replace.perform()
        XCTAssertEqual(workspace.replacements.map(\.0), [plan])
        XCTAssertEqual(workspace.documents[notes], "notes")
    }

    func testReplaceRefusesBeforeAskingWhenTheDocumentCantBeRead() async {
        workspace.front = URL(fileURLWithPath: "/tmp/ouro-md-intents/Gone.md")
        var asked = false
        ReplaceMarkdownDocumentIntent.confirm = { _, _ in asked = true }
        let outcome = await DocumentActions.replace(with: "x", in: nil, confirmed: false, in: workspace)
        XCTAssertEqual(outcome.state, .refused)
        XCTAssertEqual(outcome.error?.code, "unreadable")
        var replace = ReplaceMarkdownDocumentIntent()
        replace.markdown = "x"
        do {
            _ = try await replace.perform()
            XCTFail("expected a refusal")
        } catch let problem as OuroAX.Problem {
            XCTAssertEqual(problem.code, "unreadable")
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertFalse(asked)
    }

    func testEveryErrorSaysWhatToDoNext() {
        let errors: [DocumentIntentError] = [.appNotReady, .noDocument, .unreadable("Plan.md"), .writingToolsActive("Plan.md"), .locked("Plan.md"), .needsOpenDocument("Plan.md")]
        for error in errors {
            let problem = error.problem
            XCTAssertNotNil(problem.fix, "\(error)")
            XCTAssertTrue(problem.message.contains(". Fix: "), problem.message)
            XCTAssertFalse(problem.message.contains("Domain="), problem.message)
            XCTAssertEqual(String(localized: error.localizedStringResource), problem.message)
        }
        XCTAssertEqual(Set(errors.map(\.problem.code)).count, errors.count, "each error has its own code")
    }

    func testEntityExposesNameFolderAndModifiedAsProperties() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-md-entity-\(UUID().uuidString)/Harbor")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let file = dir.appendingPathComponent("Route.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let entity = MarkdownDocumentEntity(url: file)
        XCTAssertEqual(entity.name, "Route")
        XCTAssertEqual(entity.folder, "Harbor")
        XCTAssertNotNil(entity.modified)
        XCTAssertNil(MarkdownDocumentEntity(url: dir.appendingPathComponent("Missing.md")).modified)
    }

    // MARK: - One implementation for every door

    func testAppendOutcomeIsDoneAndChecked() async throws {
        let outcome = await DocumentActions.append("More notes.", to: workspace.order[1], in: workspace)
        XCTAssertEqual(outcome.state, .done)
        XCTAssertEqual(outcome.action, "append")
        XCTAssertEqual(outcome.target, OuroAX.Ref(kind: "document", id: workspace.order[1].path, name: "Notes"))
        XCTAssertEqual(outcome.postcondition.checked, true)
        XCTAssertEqual(outcome.postcondition.holds, true)
        XCTAssertNotNil(outcome.receipt)
        XCTAssertTrue(outcome.validate().ok, "\(outcome.validate())")
        XCTAssertEqual(workspace.documents[workspace.order[1]], "notes\n\nMore notes.\n")
    }

    func testEmptyAppendIsRefusedWithAFix() async {
        let outcome = await DocumentActions.append("  \n", to: nil, in: workspace)
        XCTAssertEqual(outcome.state, .refused)
        XCTAssertEqual(outcome.error?.code, "empty-markdown")
        XCTAssertNotNil(outcome.error?.fix)
        XCTAssertTrue(workspace.replacements.isEmpty)
        XCTAssertTrue(outcome.validate().ok, "\(outcome.validate())")
    }

    func testReplaceNeedsThePersonUntilConfirmed() async {
        let asked = await DocumentActions.replace(with: "# New\n", in: nil, confirmed: false, in: workspace)
        XCTAssertEqual(asked.state, .needsHuman)
        XCTAssertNotNil(asked.human)
        XCTAssertTrue(workspace.replacements.isEmpty)
        XCTAssertTrue(asked.validate().ok, "\(asked.validate())")

        let done = await DocumentActions.replace(with: "# New\n", in: nil, confirmed: true, in: workspace)
        XCTAssertEqual(done.state, .done)
        XCTAssertEqual(done.postcondition.holds, true)
        XCTAssertEqual(workspace.documents[workspace.order[0]], "# New\n")
        XCTAssertTrue(done.validate().ok, "\(done.validate())")
    }

    func testARefusedEditIsAnOutcomeWithItsProblem() async {
        workspace.refuseEdits = .writingToolsActive("Plan.md")
        let outcome = await DocumentActions.append("x", to: nil, in: workspace)
        XCTAssertEqual(outcome.state, .refused)
        XCTAssertEqual(outcome.error, DocumentIntentError.writingToolsActive("Plan.md").problem)
        XCTAssertTrue(outcome.validate().ok, "\(outcome.validate())")
    }

    func testAnEditorsOwnFormattingStillCountsAsDone() async {
        // Vditor's Lute writes `*` lists and `*` emphasis; that is the same Markdown.
        let lute = FakeWorkspaceProxy(workspace) { $0.replacingOccurrences(of: "- [ ]", with: "* [ ]").replacingOccurrences(of: "_now_", with: "*now*") }
        let outcome = await DocumentActions.append("- [ ] Ship it _now_", to: nil, in: lute)
        XCTAssertEqual(outcome.state, .done, outcome.summary)
        XCTAssertEqual(outcome.postcondition.holds, true)
    }

    func testSameMarkdownIgnoresFormattingButNotText() {
        XCTAssertTrue(DocumentActions.sameMarkdown("- a\n- b\n", "* a\n* b"))
        XCTAssertTrue(DocumentActions.sameMarkdown("_x_ and **y**", "*x* and __y__\n\n"))
        XCTAssertTrue(DocumentActions.sameMarkdown("a\r\n\r\n\r\nb", "a\n\nb"))
        XCTAssertFalse(DocumentActions.sameMarkdown("a\n\nb", "a b"), "paragraphs count")
        XCTAssertFalse(DocumentActions.sameMarkdown("- [ ] call", "- [x] call"))
        XCTAssertFalse(DocumentActions.sameMarkdown("Ship it.", "Ship it!"))
        XCTAssertFalse(DocumentActions.sameMarkdown("- a\n  - b", "- a\n- b"), "nesting counts")
    }

    func testAReadBackThatDiffersIsUncertain() async {
        let dropping = FakeWorkspaceProxy(workspace) { $0.replacingOccurrences(of: "item", with: "") }
        let outcome = await DocumentActions.append("* item", to: nil, in: dropping)
        XCTAssertEqual(outcome.state, .uncertain)
        XCTAssertEqual(outcome.summary, "Added to Plan.", "the person hears only what was done")
        XCTAssertNil(outcome.postcondition.holds)
        XCTAssertFalse(outcome.next.isEmpty)
        XCTAssertTrue(outcome.validate().ok, "\(outcome.validate())")
    }

    func testReadAndFindShareTheIntentsPaths() async throws {
        let (text, outcome) = await DocumentActions.read(nil, in: workspace)
        XCTAssertEqual(text, "# Plan\n\nShip it.\n")
        XCTAssertEqual(outcome.state, .done)
        XCTAssertTrue(outcome.validate().ok, "\(outcome.validate())")
        XCTAssertEqual(DocumentActions.find("note", in: workspace).map(\.name), ["Notes"])
        XCTAssertEqual(DocumentActions.find(nil, in: workspace).map(\.name), ["Plan", "Notes"])
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

    func testSameDocumentSeesThroughSymlinksAndCase() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-md-same-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Plan.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(AppModel.isSameDocument(file, file.resolvingSymlinksInPath()))
        XCTAssertTrue(AppModel.isSameDocument(file, dir.appendingPathComponent("sub/../Plan.md")))
        XCTAssertTrue(AppModel.isSameDocument(file, dir.appendingPathComponent("plan.md")), "APFS is case-insensitive by default")
        XCTAssertFalse(AppModel.isSameDocument(file, dir.appendingPathComponent("Other.md")))
        XCTAssertFalse(AppModel.isSameDocument(nil, file))
    }

    func testClosedDocumentEditsKeepCRLF() {
        XCTAssertEqual(DocumentIntentsFileText.matchingLineEndings("a\n\nb\n", of: "a\r\n"), "a\r\n\r\nb\r\n")
        XCTAssertEqual(DocumentIntentsFileText.matchingLineEndings("a\r\nb\n", of: "a\r\n"), "a\r\nb\r\n")
        XCTAssertEqual(DocumentIntentsFileText.matchingLineEndings("a\nb", of: "a\n"), "a\nb")
    }
}
