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
        XCTAssertEqual(Set(byName.keys), ["list_documents", "read_document", "append_to_document", "replace_document"])
        for (name, tool) in byName {
            XCTAssertFalse((tool["description"] as? String ?? "").isEmpty, name)
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object", name)
            let annotations = try XCTUnwrap(tool["annotations"] as? [String: Any], name)
            XCTAssertNotNil(annotations["readOnlyHint"] as? Bool, name)
            XCTAssertNotNil(annotations["destructiveHint"] as? Bool, name)
            XCTAssertEqual(annotations["openWorldHint"] as? Bool, false, name)
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
        XCTAssertEqual(Set(required ?? []), ["document", "markdown"])
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
        let docs = try XCTUnwrap(structured(result)["documents"] as? [[String: Any]])
        XCTAssertEqual(docs.compactMap { $0["name"] as? String }, ["Plan", "Harbor"])
        XCTAssertEqual(docs.first?["folder"] as? String, "notes")
        XCTAssertFalse(text(result).contains("Private"))
        let matched = try await call("list_documents", ["query": "harb"])
        XCTAssertEqual((structured(matched)["documents"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["Harbor"])
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
        let parsed = try OuroMDMCPServer.roots(from: ["--mcp", "--root", root.path, "--root", "relative"], cwd: URL(fileURLWithPath: "/work"))
        XCTAssertEqual(parsed.map(\.path), [root.standardizedFileURL.path, "/work/relative"])
        XCTAssertThrowsError(try OuroMDMCPServer.roots(from: ["--mcp"], cwd: root)) { error in
            XCTAssertTrue("\(error)".contains("Fix: ouro-md --mcp --root"), "\(error)")
        }
    }
}
