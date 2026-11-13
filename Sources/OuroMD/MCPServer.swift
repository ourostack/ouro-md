import AppKit
import Foundation
import OuroAX
import OuroMDCore

/// Ouro MD's MCP door: `ouro-md --mcp --root <folder>` serves the Model Context Protocol on stdin and stdout
/// (newline-delimited JSON-RPC 2.0), so agents can list, read, add to and replace the Markdown documents under the
/// folders it was given. The tools call `DocumentActions`, the same code the App Intents run, so Siri and an agent get
/// the same results and the same confirmation rule. It follows Ouro AX for web's `ax-mcp`: a description, schema and
/// effect annotations on every tool, calls checked before they run, errors as `OuroAX.Problem`, and results cut to a
/// size an agent's context can hold.
@MainActor
final class OuroMDMCPServer {
    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    /// The most characters one read returns; longer documents come in pages.
    static let pageSize = 20_000

    let roots: [URL]
    let version: String
    let workspace: FolderMarkdownWorkspace

    init(roots: [URL], version: String = OuroMDRelease.version) {
        self.roots = roots.map(\.standardizedFileURL)
        self.version = version
        workspace = FolderMarkdownWorkspace(roots: self.roots)
    }

    // MARK: - Running

    /// The roots `--root` names, relative ones against `cwd`; throws the usage problem when there are none.
    nonisolated static func roots(from arguments: [String], cwd: URL) throws -> [URL] {
        var roots: [URL] = []
        var i = 0
        while i < arguments.count {
            if arguments[i] == "--root", i + 1 < arguments.count {
                let path = (arguments[i + 1] as NSString).expandingTildeInPath
                roots.append((path.hasPrefix("/") ? URL(fileURLWithPath: path) : cwd.appendingPathComponent(path)).standardizedFileURL)
                i += 2
            } else {
                i += 1
            }
        }
        for root in roots {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder), isFolder.boolValue else {
                throw OuroAX.Problem(code: "bad-root", exit: 2, thing: root.path, problem: "it isn't a folder",
                                     fix: "give --root an existing folder of Markdown documents")
            }
        }
        if arguments.last == "--root" {
            throw OuroAX.Problem(code: "missing-arg", exit: 2, thing: "--root", problem: "it needs a folder after it", fix: "ouro-md --mcp --root ~/Documents/notes")
        }
        guard !roots.isEmpty else {
            throw OuroAX.Problem(code: "missing-arg", exit: 2, thing: "--mcp", problem: "it needs at least one folder of documents to serve",
                                 fix: "ouro-md --mcp --root ~/Documents/notes")
        }
        return roots
    }

    /// Serves stdin until it closes, then exits. Nothing else may write to stdout.
    static func run(arguments: [String]) -> Never {
        let roots: [URL]
        do {
            roots = try Self.roots(from: arguments, cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        } catch let problem as OuroAX.Problem {
            FileHandle.standardError.write(Data((problem.line(tool: "ouro-md") + "\n").utf8))
            exit(Int32(problem.exit))
        } catch {
            exit(1)
        }
        Task { @MainActor in
            let server = OuroMDMCPServer(roots: roots)
            await server.serve(lines: NewlineFramedLines(bytes: FileHandle.standardInput.bytes)) { line in
                FileHandle.standardOutput.write(Data((line + "\n").utf8))
            }
            exit(0)
        }
        RunLoop.main.run()
        exit(0)
    }

    /// Answers each line in turn, one at a time in the order they came, one reply per line; a notification gets none.
    func serve<Lines: AsyncSequence>(lines: Lines, write: (String) -> Void) async where Lines.Element == String {
        do {
            for try await line in lines { await answer(line, write: write) }
        } catch {
            FileHandle.standardError.write(Data("ouro-md: stdin: \(error.localizedDescription)\n".utf8))
        }
    }

    func serve(lines: [String], write: (String) -> Void) async {
        for line in lines { await answer(line, write: write) }
    }

    private func answer(_ line: String, write: (String) -> Void) async {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let data = line.data(using: .utf8), let message = try? JSONSerialization.jsonObject(with: data) else {
            write(Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error: each line must be one JSON-RPC message."]]))
            return
        }
        if let reply = await handle(message) { write(Self.encode(reply)) }
    }

    static func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes, .sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - JSON-RPC

    /// Answers one JSON-RPC message; nil for a notification.
    func handle(_ raw: Any) async -> [String: Any]? {
        let message = raw as? [String: Any] ?? [:]
        let id = message["id"]
        let isRequest = id != nil && !(id is NSNull)
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            return ["jsonrpc": "2.0", "id": isRequest ? id! : NSNull(), "error": ["code": -32600, "message": "Invalid Request: expected a JSON-RPC 2.0 message with a method."]]
        }
        guard isRequest, let id else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        func ok(_ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            return ok([
                "protocolVersion": Self.protocolVersions.first { $0 == asked } ?? Self.protocolVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "ouro-md", "version": version],
                "instructions": "Ouro MD's Markdown documents under \(roots.map(\.path).joined(separator: ", ")), and nothing else. List and read freely. append_to_document adds to the end of a file. replace_document overwrites a whole file, so it needs the person's yes first (confirmed: true). An open Ouro MD window picks up each change. Every error has a fix: what to send instead.",
            ])
        case "ping":
            return ok([:])
        case "tools/list":
            return ok(["tools": Self.tools])
        case "tools/call":
            return ok(await call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:]))
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method). This server answers initialize, ping, tools/list and tools/call."]]
        }
    }

    // MARK: - Tools

    /// The tools, exactly as `actions/document.actions.mts` declares them: `Generated/mcp.json` is the one MCP door, so
    /// what `tools/list` says can't drift from the App Intents, and CI compares the running server to the declarations.
    static let tools: [[String: Any]] = {
        guard let url = OuroResources.actions("mcp"), let data = try? Data(contentsOf: url),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tools = file["tools"] as? [[String: Any]] else {
            preconditionFailure("Generated/mcp.json is missing from the resource bundle. Fix: run scripts/ouro-actions.sh generate and rebuild.")
        }
        return tools
    }()

    static func tool(named name: String) -> [String: Any]? { tools.first { $0["name"] as? String == name } }

    private func call(_ name: String, _ arguments: [String: Any]) async -> [String: Any] {
        guard let tool = Self.tool(named: name) else {
            let names = Self.tools.compactMap { $0["name"] as? String }
            return Self.toolError(.init(code: "unknown-tool", exit: 2, thing: name.isEmpty ? "tools/call" : name, problem: "there is no tool \"\(name)\"",
                                        fix: Self.nearest(name, in: names) ?? names.joined(separator: ", ")))
        }
        if let problem = Self.check(arguments, against: tool) { return Self.toolError(problem) }
        // Every door runs the handlers the declarations bind; this server's workspace is the one they act on.
        DocumentActionHandlers.install()
        DocumentIntentsWorkspace.current = workspace
        do {
            switch name {
            case "list_documents": return try await list(arguments["query"] as? String)
            case "read_document": return try await read(arguments)
            case "append_to_document":
                let output = try await AppendToDocumentAction.run(.init(markdown: arguments["markdown"] as! String, document: arguments["document"] as? String))
                return Self.outcomeResult(state: output.state, summary: output.summary, checked: output.checked, next: output.next, fields: output)
            case "replace_document": return try await replace(arguments)
            default:
                let output = try await OpenDocumentAction.run(.init(document: arguments["document"] as! String))
                return Self.outcomeResult(state: "done", summary: output.summary, checked: nil, next: nil, fields: output)
            }
        } catch let problem as OuroAX.Problem {
            return Self.toolError(problem)
        } catch let error as OuroActionNotBound {
            return Self.toolError(.init(code: "not-ready", exit: 1, thing: error.action, problem: "it isn't ready yet", fix: "Try again in a moment"))
        } catch {
            return Self.toolError(.init(code: "failed", exit: 1, thing: name, problem: error.localizedDescription, fix: "Try again"))
        }
    }

    /// The first argument problem, checked before anything runs, against the tool's input schema.
    static func check(_ arguments: [String: Any], against tool: [String: Any]) -> OuroAX.Problem? {
        let name = tool["name"] as? String ?? ""
        let schema = tool["inputSchema"] as? [String: Any] ?? [:]
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        for required in schema["required"] as? [String] ?? [] where arguments[required] == nil {
            return .init(code: "missing-arg", exit: 2, thing: "\(name) \(required)", problem: "it is required: \(properties[required]?["description"] as? String ?? required)",
                         fix: "send \(required) as a \(properties[required]?["type"] as? String ?? "value")")
        }
        for (key, value) in arguments {
            guard let property = properties[key] else {
                return .init(code: "unknown-arg", exit: 2, thing: "\(name) \(key)", problem: "\(name) takes no \(key)",
                             fix: Self.nearest(key, in: Array(properties.keys)) ?? properties.keys.sorted().joined(separator: ", "))
            }
            let type = property["type"] as? String ?? "string"
            let fits: Bool
            switch type {
            case "string": fits = value is String
            case "boolean": fits = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            case "integer": fits = (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue == $0.doubleValue.rounded() && $0.intValue >= 0 } ?? false
            default: fits = (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } ?? false
            }
            if !fits {
                return .init(code: "bad-arg", exit: 2, thing: "\(name) \(key)", problem: "it must be \(type == "integer" ? "a whole number, 0 or more" : "a \(type)")",
                             fix: "send \(key) as a \(type)")
            }
        }
        return nil
    }

    private func list(_ query: String?) async throws -> [String: Any] {
        let output = try await ListDocumentsAction.run(.init(query: query))
        let text = output.count == 0
            ? "No Markdown documents\(query.map { " match \"\($0)\"" } ?? "") under \(roots.map(\.path).joined(separator: ", "))."
            : output.documents
        let structured = Self.structured(output)
        guard text.count > Self.pageSize else {
            return ["content": [["type": "text", "text": text]], "structuredContent": structured, "isError": false]
        }
        // Too many to show whole: the first page of names, and how to ask for fewer.
        let cut = String(text.prefix(Self.pageSize))
        let shown = cut[..<(cut.lastIndex(of: "\n") ?? cut.endIndex)]
        let lines = shown.split(separator: "\n", omittingEmptySubsequences: false).count
        return ["content": [["type": "text", "text": String(shown) + "\n\n[\(output.count) documents; \(lines) shown. Narrow it: list_documents {\"query\": \"<words in the name or folder>\"}]"]],
                "structuredContent": ["documents": String(shown), "count": output.count], "isError": false]
    }

    private func read(_ arguments: [String: Any]) async throws -> [String: Any] {
        let whole = try await ReadDocumentAction.run(.init(document: arguments["document"] as? String, from: nil))
        // The handler returns the whole text, which Shortcuts wants; an agent gets it a page at a time.
        let text = whole.markdown
        let asked = (arguments["from"] as? NSNumber)?.doubleValue ?? 0
        let from = asked >= Double(text.count) ? text.count : Int(asked)
        let start = text.index(text.startIndex, offsetBy: from)
        let end = text.index(start, offsetBy: Self.pageSize, limitedBy: text.endIndex) ?? text.endIndex
        let page = String(text[start..<end])
        var output = ReadDocumentOutput(markdown: page, name: whole.name, path: whole.path, length: text.count, next: nil)
        var shown = page
        if end < text.endIndex {
            let next = from + page.count
            output.next = next
            shown += "\n\n[\(text.count - next) more characters. Next: read_document {\"document\": \(Self.json(whole.path)), \"from\": \(next)}]"
        }
        return ["content": [["type": "text", "text": shown]], "structuredContent": Self.structured(output), "isError": false]
    }

    /// Replace overwrites every line, so an agent only prepares it: until `confirmed` is true, nothing changes and the
    /// answer says what to ask the person.
    private func replace(_ arguments: [String: Any]) async throws -> [String: Any] {
        let markdown = arguments["markdown"] as! String
        let reference = arguments["document"] as! String
        guard arguments["confirmed"] as? Bool == true else {
            let url = try DocumentActionHandlers.locate(reference, in: workspace)
            let asking = await DocumentActions.replace(with: markdown, in: url, confirmed: false, in: workspace)
            if asking.state == .refused || asking.state == .failed { throw asking.error ?? OuroAX.Problem(code: "failed", exit: 1, thing: "replace_document", problem: asking.summary, fix: "Try again") }
            let output = ReplaceDocumentOutput(state: asking.state.rawValue, summary: asking.summary, checked: nil, next: asking.human?.resume.command)
            return Self.outcomeResult(state: output.state, summary: output.summary, checked: nil, next: output.next, fields: output, why: asking.human?.reason)
        }
        let output = try await ReplaceDocumentAction.run(.init(markdown: markdown, document: reference, confirmed: true))
        return Self.outcomeResult(state: output.state, summary: output.summary, checked: output.checked, next: output.next, fields: output)
    }

    static func structured<Output: Encodable>(_ output: Output) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(output))) as? [String: Any] ?? [:]
    }

    /// An action's result for an agent: the sentence, how it was checked, and what to call next.
    static func outcomeResult<Output: Encodable>(state: String, summary: String, checked: String?, next: String?, fields: Output, why: String? = nil) -> [String: Any] {
        var lines = [summary]
        if let why { lines.append(why + ".") }
        if let checked { lines.append("Checked: \(checked).") }
        if let next { lines.append("Next: \(next)") }
        return ["content": [["type": "text", "text": lines.joined(separator: "\n")]], "structuredContent": structured(fields), "isError": false]
    }

    static func toolError(_ problem: OuroAX.Problem) -> [String: Any] {
        let structured = (try? JSONSerialization.jsonObject(with: problem.errorJSON())) as? [String: Any] ?? [:]
        return ["content": [["type": "text", "text": problem.line(tool: "ouro-md")]], "structuredContent": structured, "isError": true]
    }

    /// The name closest to a mistyped one, when it is close enough to be what was meant.
    static func nearest(_ name: String, in names: [String]) -> String? {
        func distance(_ a: [Character], _ b: [Character]) -> Int {
            var row = Array(0...b.count)
            for (i, x) in a.enumerated() {
                var previous = row[0]
                row[0] = i + 1
                for (j, y) in b.enumerated() {
                    let current = row[j + 1]
                    row[j + 1] = min(row[j + 1] + 1, row[j] + 1, previous + (x == y ? 0 : 1))
                    previous = current
                }
            }
            return row[b.count]
        }
        let typed = Array(name.lowercased())
        let best = names.map { ($0, distance(typed, Array($0.lowercased()))) }.min { $0.1 < $1.1 }
        guard let best, best.1 <= max(2, typed.count / 3) else { return nil }
        return best.0
    }

    static func json(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}

/// The documents under the folders the MCP door serves. Nothing outside them is listed, read or written.
@MainActor
final class FolderMarkdownWorkspace: MarkdownDocumentWorkspace {
    let roots: [URL]
    /// The roots with symlinks resolved, once.
    private let resolvedRoots: [String]
    /// Enough for a notes folder: a walk returns at most this many documents.
    static let limit = 2_000
    /// A walk looks at no more than this many files and folders, so a home folder can't stall a call.
    static let visitLimit = 50_000

    init(roots: [URL]) {
        self.roots = roots
        resolvedRoots = roots.map { root in
            let base = root.resolvingSymlinksInPath().path
            return base.hasSuffix("/") ? base : base + "/"
        }
    }

    func knownDocumentURLs() -> [URL] {
        var found: [URL] = []
        for root in roots {
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var here: [URL] = []
            var visited = 0
            for case let url as URL in walk {
                visited += 1
                if visited > Self.visitLimit { break }
                guard AppModel.isMarkdownDocumentURL(url), isReadable(url),
                      (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                here.append(url.standardizedFileURL)
                if found.count + here.count >= Self.limit { break }
            }
            found += here.sorted { relative($0, to: root).localizedStandardCompare(relative($1, to: root)) == .orderedAscending }
            if found.count >= Self.limit { break }
        }
        return found
    }

    private func relative(_ url: URL, to root: URL) -> String {
        String(url.path.dropFirst(root.path.count))
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return resolvedRoots.contains { base in path + "/" == base || path.hasPrefix(base) }
    }

    func isReadable(_ url: URL) -> Bool {
        // The name and, through a symlink, what it points to must both be Markdown.
        AppModel.isMarkdownDocumentURL(url) && AppModel.isMarkdownDocumentURL(url.resolvingSymlinksInPath())
            && contains(url) && FileManager.default.isReadableFile(atPath: url.path)
    }

    func frontDocumentURL() -> URL? { nil }

    func markdown(for url: URL) async -> String? {
        guard isReadable(url) else { return nil }
        return AppModel.readText(at: url)
    }

    func replaceMarkdown(_ markdown: String, in url: URL) async throws {
        guard isReadable(url) else { throw DocumentIntentError.unreadable(url.lastPathComponent) }
        try DocumentIntentsFileText.write(markdown, to: url)
    }

    func open(_ url: URL) {
        guard isReadable(url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The document an agent named: a path (absolute, or relative to any served folder) or a name from list_documents.
    func locate(_ reference: String) -> Result<URL, OuroAX.Problem> {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikePath = trimmed.contains("/") || AppModel.isMarkdownDocumentURL(URL(fileURLWithPath: trimmed))
        if looksLikePath {
            let expanded = (trimmed as NSString).expandingTildeInPath
            let candidates = expanded.hasPrefix("/") ? [URL(fileURLWithPath: expanded)] : roots.map { $0.appendingPathComponent(expanded) }
            let urls = candidates.map(\.standardizedFileURL)
            guard let inside = urls.first(where: contains) else {
                return .failure(.init(code: "outside-roots", exit: 2, thing: trimmed, problem: "it isn't in a folder this server serves (\(roots.map(\.path).joined(separator: ", ")))",
                                      fix: "use a document from list_documents, or start the server with --root <its folder>"))
            }
            guard let url = urls.first(where: isReadable) else {
                return .failure(.notFound(kind: "document", id: inside.path, fix: "call list_documents to see the documents"))
            }
            return .success(url)
        }
        let known = DocumentActions.find(nil, in: self)
        let exact = known.filter { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        if exact.count == 1 { return .success(exact[0].url) }
        if exact.count > 1 {
            return .failure(.init(code: "ambiguous", exit: 2, thing: trimmed, problem: "\(exact.count) documents have that name",
                                  fix: "name it by path: \(exact.map(\.id).joined(separator: " or "))"))
        }
        let near = known.compactMap { entity in OuroAX.EntityMatch.score(trimmed, in: [entity.name, entity.folder]).map { ($0, entity.name) } }
            .sorted { $0.0 < $1.0 }.prefix(3).map(\.1)
        return .failure(.notFound(kind: "document", id: trimmed,
                                  fix: near.isEmpty ? "call list_documents to see the documents" : "one of \(near.joined(separator: ", ")), or call list_documents"))
    }
}

/// Lines split at "\n" bytes only, as MCP's stdio transport frames them. (`AsyncLineSequence` also splits at U+2028 and
/// U+2029, which JSON may carry unescaped inside a string.)
struct NewlineFramedLines<Bytes: AsyncSequence>: AsyncSequence where Bytes.Element == UInt8 {
    typealias Element = String
    let bytes: Bytes

    struct AsyncIterator: AsyncIteratorProtocol {
        var inner: Bytes.AsyncIterator
        var done = false

        mutating func next() async throws -> String? {
            guard !done else { return nil }
            var line: [UInt8] = []
            while let byte = try await inner.next() {
                if byte == 0x0A { return String(decoding: line, as: UTF8.self) }
                line.append(byte)
            }
            done = true
            return line.isEmpty ? nil : String(decoding: line, as: UTF8.self)
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(inner: bytes.makeAsyncIterator()) }
}
