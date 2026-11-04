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
            return ok(["tools": Self.tools.map(\.json)])
        case "tools/call":
            return ok(await call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:]))
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method). This server answers initialize, ping, tools/list and tools/call."]]
        }
    }

    // MARK: - Tools

    struct Argument {
        let name: String
        let type: String
        let description: String
        let required: Bool
    }

    struct Tool {
        let name: String
        let title: String
        let description: String
        let arguments: [Argument]
        let readOnly: Bool
        let destructive: Bool

        var json: [String: Any] {
            var properties: [String: Any] = [:]
            for a in arguments { properties[a.name] = ["type": a.type, "description": a.description] }
            return [
                "name": name, "title": title, "description": description,
                "inputSchema": ["type": "object", "properties": properties, "required": arguments.filter(\.required).map(\.name), "additionalProperties": false],
                "annotations": ["title": title, "readOnlyHint": readOnly, "destructiveHint": destructive, "openWorldHint": false],
            ]
        }
    }

    static let documentArgument = Argument(name: "document", type: "string", description: "The document: its name as list_documents shows it (\"Plan\"), or its path, absolute or relative to a served folder.", required: true)

    static let tools: [Tool] = [
        Tool(name: "list_documents", title: "List Markdown documents",
             description: "Lists the Markdown documents in the folders Ouro MD serves, with name, folder, path and when each was modified. Changes nothing.",
             arguments: [Argument(name: "query", type: "string", description: "Words to match against names and folders; leave it out to list everything.", required: false)],
             readOnly: true, destructive: false),
        Tool(name: "read_document", title: "Read a Markdown document",
             description: "Returns a document's Markdown as saved, \(pageSize) characters at a time; a longer document says where the next page starts. Changes nothing.",
             arguments: [documentArgument, Argument(name: "from", type: "integer", description: "The character (counted as a person sees letters) to start at, for the next page of a long document; 0 when left out.", required: false)],
             readOnly: true, destructive: false),
        Tool(name: "append_to_document", title: "Add to a Markdown document",
             description: "Adds Markdown to the end of a document as a new paragraph and saves it; an open Ouro MD window picks up the change. It changes only this file. Returns the outcome, checked by reading the document back.",
             arguments: [documentArgument, Argument(name: "markdown", type: "string", description: "The Markdown to add, such as \"- [ ] Call the harbor master\".", required: true)],
             readOnly: false, destructive: false),
        Tool(name: "replace_document", title: "Replace a Markdown document",
             description: "Replaces a document's whole Markdown. It overwrites every line, so it asks first: without confirmed: true it changes nothing and says what to ask the person. Send confirmed: true only after the person has said yes.",
             arguments: [documentArgument,
                         Argument(name: "markdown", type: "string", description: "The Markdown that becomes the whole document.", required: true),
                         Argument(name: "confirmed", type: "boolean", description: "true once the person has confirmed replacing this document; leave it out to ask.", required: false)],
             readOnly: false, destructive: true),
    ]

    private func call(_ name: String, _ arguments: [String: Any]) async -> [String: Any] {
        guard let tool = Self.tools.first(where: { $0.name == name }) else {
            let names = Self.tools.map(\.name)
            return Self.toolError(.init(code: "unknown-tool", exit: 2, thing: name.isEmpty ? "tools/call" : name, problem: "there is no tool \"\(name)\"",
                                        fix: Self.nearest(name, in: names) ?? names.joined(separator: ", ")))
        }
        if let problem = Self.check(arguments, against: tool) { return Self.toolError(problem) }
        switch tool.name {
        case "list_documents":
            return list(arguments["query"] as? String)
        case "read_document":
            return await read(arguments)
        case "append_to_document":
            return await edit(arguments) { url in await DocumentActions.append(arguments["markdown"] as! String, to: url, in: self.workspace) }
        default:
            let confirmed = arguments["confirmed"] as? Bool ?? false
            return await edit(arguments) { url in await DocumentActions.replace(with: arguments["markdown"] as! String, in: url, confirmed: confirmed, in: self.workspace) }
        }
    }

    /// The first argument problem, checked before anything runs.
    static func check(_ arguments: [String: Any], against tool: Tool) -> OuroAX.Problem? {
        for argument in tool.arguments where argument.required && arguments[argument.name] == nil {
            return .init(code: "missing-arg", exit: 2, thing: "\(tool.name) \(argument.name)", problem: "it is required: \(argument.description)",
                         fix: "send \(argument.name) as a \(argument.type)")
        }
        let known = Set(tool.arguments.map(\.name))
        for (key, value) in arguments {
            guard let argument = tool.arguments.first(where: { $0.name == key }) else {
                return .init(code: "unknown-arg", exit: 2, thing: "\(tool.name) \(key)", problem: "\(tool.name) takes no \(key)",
                             fix: Self.nearest(key, in: Array(known)) ?? known.sorted().joined(separator: ", "))
            }
            let fits: Bool
            switch argument.type {
            case "string": fits = value is String
            case "boolean": fits = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            default: fits = (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue == $0.doubleValue.rounded() && $0.intValue >= 0 } ?? false
            }
            if !fits {
                return .init(code: "bad-arg", exit: 2, thing: "\(tool.name) \(key)", problem: "it must be \(argument.type == "integer" ? "a whole number, 0 or more" : "a \(argument.type)")",
                             fix: "send \(key) as a \(argument.type)")
            }
        }
        return nil
    }

    private func list(_ query: String?) -> [String: Any] {
        let documents = DocumentActions.find(query, in: workspace).map { entity -> [String: Any] in
            var item: [String: Any] = ["name": entity.name, "folder": entity.folder, "path": entity.id]
            if let modified = entity.modified { item["modified"] = modified.formatted(.iso8601) }
            return item
        }
        let lines = documents.map { "\($0["name"]!)  \($0["path"]!)" }
        let text = documents.isEmpty
            ? "No Markdown documents\(query.map { " match \"\($0)\"" } ?? "") under \(roots.map(\.path).joined(separator: ", "))."
            : lines.joined(separator: "\n")
        guard text.count > Self.pageSize else {
            return ["content": [["type": "text", "text": text]], "structuredContent": ["documents": documents], "isError": false]
        }
        // Too many to show whole: the first page of names, and how to ask for fewer.
        let cut = String(text.prefix(Self.pageSize))
        let shown = cut[..<(cut.lastIndex(of: "\n") ?? cut.endIndex)]
        return ["content": [["type": "text", "text": String(shown) + "\n\n[\(documents.count) documents; not all are shown. Narrow it: list_documents {\"query\": \"<words in the name or folder>\"}]"]], "isError": false]
    }

    private func read(_ arguments: [String: Any]) async -> [String: Any] {
        let url: URL
        switch workspace.locate(arguments["document"] as! String) {
        case .failure(let problem): return Self.toolError(problem)
        case .success(let found): url = found
        }
        let (text, outcome) = await DocumentActions.read(url, in: workspace)
        guard let text else { return Self.outcomeResult(outcome) }
        let asked = (arguments["from"] as? NSNumber)?.doubleValue ?? 0
        let from = asked >= Double(text.count) ? text.count : Int(asked)
        let start = text.index(text.startIndex, offsetBy: from)
        let end = text.index(start, offsetBy: Self.pageSize, limitedBy: text.endIndex) ?? text.endIndex
        let page = String(text[start..<end])
        var structured: [String: Any] = ["document": ["name": DocumentActions.name(of: url), "path": url.path], "markdown": page, "length": text.count]
        var shown = page
        if end < text.endIndex {
            let next = from + page.count
            structured["next"] = next
            shown += "\n\n[\(text.count - next) more characters. Next: read_document {\"document\": \(Self.json(url.path)), \"from\": \(next)}]"
        }
        return ["content": [["type": "text", "text": shown]], "structuredContent": structured, "isError": false]
    }

    private func edit(_ arguments: [String: Any], _ action: (URL) async -> OuroAX.Outcome) async -> [String: Any] {
        switch workspace.locate(arguments["document"] as! String) {
        case .failure(let problem): return Self.toolError(problem)
        case .success(let url): return Self.outcomeResult(await action(url))
        }
    }

    static func outcomeResult(_ outcome: OuroAX.Outcome) -> [String: Any] {
        let structured = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(outcome))) as? [String: Any] ?? [:]
        return [
            "content": [["type": "text", "text": outcome.text(tool: "ouro-md")]],
            "structuredContent": structured,
            "isError": outcome.state == .refused || outcome.state == .failed,
        ]
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
