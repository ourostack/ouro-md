import XCTest
@testable import OuroMD

/// The MCP door, end to end over its JSON-RPC handler, against a scratch folder.
@MainActor
final class MCPServerTests: XCTestCase {
    private var root: URL!
    private var outside: URL!
    private var server: OuroMDMCPServer!

    override func setUp() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-md-mcp-\(UUID().uuidString)")
        root = base.appendingPathComponent("notes")
        outside = base.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("trips"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "# Plan\n\nShip it.\n".write(to: root.appendingPathComponent("Plan.md"), atomically: true, encoding: .utf8)
        try "harbor\r\n".write(to: root.appendingPathComponent("trips/Harbor.markdown"), atomically: true, encoding: .utf8)
        try "not markdown".write(to: root.appendingPathComponent("todo.txt"), atomically: true, encoding: .utf8)
        try "secret".write(to: outside.appendingPathComponent("Private.md"), atomically: true, encoding: .utf8)
        server = OuroMDMCPServer(roots: [root], version: "9.9.9")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    // MARK: - Helpers

    private func request(_ method: String, _ params: [String: Any] = [:], id: Int = 1) async throws -> [String: Any] {
        let reply = await server.handle(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        return try XCTUnwrap(reply)
    }

    private func call(_ tool: String, _ arguments: [String: Any] = [:]) async throws -> [String: Any] {
        let reply = try await request("tools/call", ["name": tool, "arguments": arguments])
        return try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
    }

    private func text(_ result: [String: Any]) -> String {
        ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
    }

    private func structured(_ result: [String: Any]) -> [String: Any] {
        result["structuredContent"] as? [String: Any] ?? [:]
    }

    private func errorCode(_ result: [String: Any]) -> String? {
        (structured(result)["error"] as? [String: Any])?["code"] as? String
    }

    private func disk(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: - The protocol

    func testInitializeNamesTheServerAndAgreesAVersion() async throws {
        let reply = try await request("initialize", ["protocolVersion": "2025-03-26"])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "ouro-md")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["version"] as? String, "9.9.9")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertTrue((result["instructions"] as? String ?? "").contains(root.path))

        let later = try await request("initialize", ["protocolVersion": "2099-01-01"])
        XCTAssertEqual((later["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
    }

    func testNotificationsGetNoReplyAndUnknownMethodsSayWhatIsAnswered() async throws {
        let none = await server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(none)
        let ping = try await request("ping")
        XCTAssertNotNil(ping["result"])
        let unknown = try await request("resources/list")
        let error = try XCTUnwrap(unknown["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
        XCTAssertTrue((error["message"] as? String ?? "").contains("tools/call"))
        let bad = await server.handle(["id": 3, "method": 7])
        XCTAssertEqual((bad?["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testToolsListDescribesEveryToolWithSchemaAndEffect() async throws {
        let reply = try await request("tools/list")
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0["name"] as! String, $0) })
        XCTAssertEqual(Set(byName.keys), ["list_documents", "read_document", "append_to_document", "replace_document", "open_document"])
        for (name, tool) in byName {
            XCTAssertFalse((tool["description"] as? String ?? "").isEmpty, name)
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object", name)
            let annotations = try XCTUnwrap(tool["annotations"] as? [String: Any], name)
            XCTAssertNotNil(annotations["readOnlyHint"] as? Bool, name)
            XCTAssertNotNil(annotations["destructiveHint"] as? Bool, name)
            // A consequential action is the one declared open-world; every other tool stays inside the documents.
            XCTAssertEqual(annotations["openWorldHint"] as? Bool, name == "replace_document", name)
        }
        func hints(_ name: String) -> (Bool, Bool) {
            let a = byName[name]!["annotations"] as! [String: Any]
            return (a["readOnlyHint"] as! Bool, a["destructiveHint"] as! Bool)
        }
        XCTAssertTrue(hints("list_documents") == (true, false))
        XCTAssertTrue(hints("read_document") == (true, false))
        XCTAssertTrue(hints("append_to_document") == (false, false))
        XCTAssertTrue(hints("replace_document") == (false, true))
        let required = (byName["append_to_document"]!["inputSchema"] as! [String: Any])["required"] as? [String]
        XCTAssertEqual(Set(required ?? []), ["markdown"], "the document defaults to the one in front")
        let served = (reply["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let file = try XCTUnwrap(OuroResources.actions("mcp"))
        let declared = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(served?.compactMap { $0["name"] as? String } ?? []), Set(declared.compactMap { $0["name"] as? String }), "served tools are the generated tools")
    }

    func testAnUnknownToolIsRefusedWithTheNearestName() async throws {
        let result = try await call("read_documents", ["document": "Plan"])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual(errorCode(result), "unknown-tool")
        XCTAssertTrue(text(result).contains("Fix: read_document"), text(result))
    }

    func testAMissingArgumentIsNamed() async throws {
        let result = try await call("append_to_document", ["document": "Plan"])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual(errorCode(result), "missing-arg")
        XCTAssertTrue(text(result).contains("markdown"), text(result))
        let wrong = try await call("append_to_document", ["document": "Plan", "markdown": 4])
        XCTAssertEqual(errorCode(wrong), "bad-arg")
        XCTAssertEqual(try disk("Plan.md"), "# Plan\n\nShip it.\n")
    }

    // MARK: - Documents

    func testListFindsMarkdownUnderTheRootsOnly() async throws {
        let result = try await call("list_documents")
        XCTAssertEqual(result["isError"] as? Bool, false)
        let listing = try XCTUnwrap(structured(result)["documents"] as? String)
        XCTAssertEqual(listing.split(separator: "\n").map { $0.components(separatedBy: "  ")[0] }, ["Plan", "Harbor"])
        XCTAssertEqual(structured(result)["count"] as? Int, 2)
        XCTAssertFalse(text(result).contains("Private"))
        let matched = try await call("list_documents", ["query": "harb"])
        XCTAssertEqual((structured(matched)["documents"] as? String)?.components(separatedBy: "  ").first, "Harbor")
    }

    func testReadByNameOrPathButNeverOutsideTheRoots() async throws {
        let byName = try await call("read_document", ["document": "plan"])
        XCTAssertEqual(text(byName), "# Plan\n\nShip it.\n")
        XCTAssertEqual(structured(byName)["markdown"] as? String, "# Plan\n\nShip it.\n")
        let byPath = try await call("read_document", ["document": "trips/Harbor.markdown"])
        XCTAssertEqual(text(byPath), "harbor\r\n")
        let escape = try await call("read_document", ["document": outside.appendingPathComponent("Private.md").path])
        XCTAssertEqual(escape["isError"] as? Bool, true)
        XCTAssertEqual(errorCode(escape), "outside-roots")
        XCTAssertFalse(text(escape).contains("secret"))
        let climb = try await call("read_document", ["document": "../elsewhere/Private.md"])
        XCTAssertEqual(errorCode(climb), "outside-roots")
        let missing = try await call("read_document", ["document": "Nope"])
        XCTAssertEqual(errorCode(missing), "not-found")
        XCTAssertTrue(text(missing).contains("list_documents"), text(missing))
    }

    func testASymlinkOutOfTheRootsIsNeitherListedNorRead() async throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Link.md"), withDestinationURL: outside.appendingPathComponent("Private.md"))
        let listed = try await call("list_documents")
        XCTAssertFalse(text(listed).contains("Link"), text(listed))
        let read = try await call("read_document", ["document": "Link.md"])
        XCTAssertEqual(errorCode(read), "outside-roots")
        XCTAssertFalse(text(read).contains("secret"))
        let append = try await call("append_to_document", ["document": "Link.md", "markdown": "x"])
        XCTAssertEqual(errorCode(append), "outside-roots")
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("Private.md"), encoding: .utf8), "secret")
    }

    func testReadingALongDocumentComesInPages() async throws {
        let long = String(repeating: "word ", count: 6_000)
        try long.write(to: root.appendingPathComponent("Long.md"), atomically: true, encoding: .utf8)
        let first = try await call("read_document", ["document": "Long"])
        XCTAssertEqual((structured(first)["markdown"] as? String)?.count, OuroMDMCPServer.pageSize)
        let next = try XCTUnwrap(structured(first)["next"] as? Int)
        XCTAssertEqual(next, OuroMDMCPServer.pageSize)
        XCTAssertTrue(text(first).contains("\"from\": \(next)"), String(text(first).suffix(200)))
        let second = try await call("read_document", ["document": "Long", "from": next])
        XCTAssertEqual((structured(second)["markdown"] as? String)?.count, long.count - next)
        XCTAssertNil(structured(second)["next"] as? Int)
    }

    func testAppendWritesTheFileThroughTheIntentsPath() async throws {
        let result = try await call("append_to_document", ["document": "Plan", "markdown": "- [ ] Tell the crew"])
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertEqual(structured(result)["state"] as? String, "done")
        XCTAssertEqual(try disk("Plan.md"), "# Plan\n\nShip it.\n\n- [ ] Tell the crew\n")
        XCTAssertTrue(text(result).hasPrefix("Added to Plan."), text(result))

        _ = try await call("append_to_document", ["document": "trips/Harbor.markdown", "markdown": "dock"])
        XCTAssertEqual(try disk("trips/Harbor.markdown"), "harbor\r\n\r\ndock\r\n", "keeps CRLF")
    }

    func testReplaceNeedsThePersonsConfirmation() async throws {
        let asked = try await call("replace_document", ["document": "Plan", "markdown": "# Gone\n"])
        XCTAssertEqual(asked["isError"] as? Bool, false)
        XCTAssertEqual(structured(asked)["state"] as? String, "needs-human")
        XCTAssertTrue(text(asked).contains("\"confirmed\": true"), text(asked))
        XCTAssertEqual(try disk("Plan.md"), "# Plan\n\nShip it.\n")

        let done = try await call("replace_document", ["document": "Plan", "markdown": "# New plan\n", "confirmed": true])
        XCTAssertEqual(structured(done)["state"] as? String, "done")
        XCTAssertEqual(try disk("Plan.md"), "# New plan\n")
    }

    func testServeAnswersOneLinePerRequest() async throws {
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            "not json",
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_document","arguments":{"document":"Plan"}}}"#,
        ]
        var out: [String] = []
        await server.serve(lines: lines) { out.append($0) }
        XCTAssertEqual(out.count, 3)
        XCTAssertFalse(out.contains { $0.contains("\n") }, "one reply per line")
        let replies = try out.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(replies[0]["id"] as? Int, 1)
        XCTAssertEqual((replies[1]["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertEqual(replies[2]["id"] as? Int, 2)
    }

    func testArgumentsParseRootsAndRefuseNone() throws {
        let parsed = try OuroMDMCPServer.roots(from: ["--mcp", "--root", root.path, "--root", "elsewhere"], cwd: root.deletingLastPathComponent())
        XCTAssertEqual(parsed.map(\.path), [root.standardizedFileURL.path, outside.standardizedFileURL.path])
        XCTAssertThrowsError(try OuroMDMCPServer.roots(from: ["--mcp"], cwd: root)) { error in
            XCTAssertTrue("\(error)".contains("Fix: ouro-md --mcp --root"), "\(error)")
        }
    }

    func testTheResumeCallFromNeedsHumanWorksAsSent() async throws {
        let asked = try await call("replace_document", ["document": "Plan", "markdown": "# Kept\n"])
        let command = try XCTUnwrap(structured(asked)["next"] as? String)
        XCTAssertTrue(command.hasPrefix("replace_document "), command)
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(command.dropFirst("replace_document ".count).utf8)) as? [String: Any])
        let done = try await call("replace_document", arguments)
        XCTAssertEqual(structured(done)["state"] as? String, "done", text(done))
        XCTAssertEqual(try disk("Plan.md"), "# Kept\n")
    }

    func testLinesSplitOnlyAtNewlineBytes() async throws {
        let message = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"append_to_document","arguments":{"document":"Plan","markdown":"a\#u{2028}b"}}}"# + "\n"
        let stream = AsyncStream<UInt8> { continuation in
            for byte in Data(message.utf8) { continuation.yield(byte) }
            continuation.finish()
        }
        var out: [String] = []
        await server.serve(lines: NewlineFramedLines(bytes: stream)) { out.append($0) }
        XCTAssertEqual(out.count, 1, "\(out)")
        XCTAssertTrue(out.first?.contains(#""id":7"#) ?? false)
        XCTAssertTrue(try disk("Plan.md").hasSuffix("a\u{2028}b\n"))
    }

    func testTheBoundaryHoldsForLookalikesFoldersAndLinkedNonMarkdown() async throws {
        let sibling = root.deletingLastPathComponent().appendingPathComponent("notes-private")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try "hidden".write(to: sibling.appendingPathComponent("Diary.md"), atomically: true, encoding: .utf8)
        let escape = try await call("read_document", ["document": sibling.appendingPathComponent("Diary.md").path])
        XCTAssertEqual(errorCode(escape), "outside-roots")

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder.md"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Todo.md"), withDestinationURL: root.appendingPathComponent("todo.txt"))
        let listed = try await call("list_documents")
        XCTAssertFalse(text(listed).contains("Folder"), text(listed))
        XCTAssertFalse(text(listed).contains("Todo"), text(listed))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.md"), withDestinationURL: root.appendingPathComponent("Plan.md"))
        let relisted = try await call("list_documents")
        XCTAssertTrue(text(relisted).contains("Alias"), "a link to Markdown inside the folder is listed: \(text(relisted))")
        _ = try await call("append_to_document", ["document": "Todo.md", "markdown": "x"])
        XCTAssertEqual(try disk("todo.txt"), "not markdown")
    }

    func testAHugeFromReadsNothingAndBadRootsAreRefused() async throws {
        let read = try await call("read_document", ["document": "Plan", "from": 1e30])
        XCTAssertEqual(structured(read)["markdown"] as? String, "")
        XCTAssertThrowsError(try OuroMDMCPServer.roots(from: ["--mcp", "--root", root.appendingPathComponent("Plan.md").path], cwd: root))
        XCTAssertThrowsError(try OuroMDMCPServer.roots(from: ["--mcp", "--root", root.path, "--root"], cwd: root))
    }

    func testAVeryLongListIsCutWithAWayToNarrowIt() async throws {
        let many = root.appendingPathComponent("many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: true)
        for i in 0..<400 {
            try "x".write(to: many.appendingPathComponent("A long document name to fill the list \(i).md"), atomically: false, encoding: .utf8)
        }
        let listed = try await call("list_documents")
        XCTAssertLessThanOrEqual(text(listed).count, OuroMDMCPServer.pageSize + 200)
        XCTAssertTrue(text(listed).contains("list_documents {\"query\""), String(text(listed).suffix(200)))
        XCTAssertEqual(structured(listed)["count"] as? Int, 402)
    }
}
