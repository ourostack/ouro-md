import Foundation
import Markdown
import OuroAX

/// What Ouro MD does with a document, once, for every door: the App Intents (Siri, Shortcuts, Spotlight) and the MCP
/// server both call these. Each action returns an `OuroAX.Outcome` (`ax-outcome`'s `outcome/1`), so a person hears and
/// an agent reads the same result, and a refusal carries an `OuroAX.Problem` whose fix says what to do next.
@MainActor
enum DocumentActions {
    /// Who the receipts name as acting.
    static let actor = "ouro-md"

    /// The documents the workspace knows, once each in its order; with words, those whose name or folder match, best
    /// match first.
    static func find(_ words: String?, in workspace: MarkdownDocumentWorkspace) -> [MarkdownDocumentEntity] {
        var seen = Set<String>()
        let known = workspace.knownDocumentURLs().map(MarkdownDocumentEntity.init(url:)).filter { seen.insert($0.id).inserted }
        let needle = (words ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return known }
        return known.enumerated()
            .compactMap { offset, entity in OuroAX.EntityMatch.score(needle, in: [entity.name, entity.folder]).map { ($0, offset, entity) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map(\.2)
    }

    /// The document's Markdown, including unsaved edits when it is open, and the outcome of reading it.
    static func read(_ url: URL?, in workspace: MarkdownDocumentWorkspace) async -> (String?, OuroAX.Outcome) {
        let target: URL
        switch resolve(url, in: workspace) {
        case .failure(let error): return (nil, refused("read", error))
        case .success(let found): target = found
        }
        guard let text = await workspace.markdown(for: target) else {
            return (nil, refused("read", .unreadable(target.lastPathComponent), target: target))
        }
        let outcome = OuroAX.Outcome(
            action: "read",
            state: .done,
            summary: "Read \(name(of: target)): \(text.count) characters.",
            target: ref(target),
            postcondition: .init(checked: true, holds: true, how: "the text came from \(name(of: target)) as it is now")
        )
        return (text, outcome)
    }

    /// Adds Markdown to the end of the document as a new paragraph, as one undoable edit.
    static func append(_ addition: String, to url: URL?, in workspace: MarkdownDocumentWorkspace) async -> OuroAX.Outcome {
        guard !addition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return refused("append", problem: .init(code: "empty-markdown", exit: 2, thing: "markdown", problem: "there is nothing to add", fix: "Give the Markdown to add"))
        }
        let target: URL
        switch resolve(url, in: workspace) {
        case .failure(let error): return refused("append", error)
        case .success(let found): target = found
        }
        guard let current = await workspace.markdown(for: target) else {
            return refused("append", .unreadable(target.lastPathComponent), target: target)
        }
        return await write(appending(addition, to: current), to: target, action: "append", verb: "Added to", in: workspace)
    }

    /// Replaces the document's whole Markdown, as one undoable edit when it is open. Until `confirmed`, it only asks:
    /// the outcome is `needs-human`, because replacing discards text the person may want.
    static func replace(with markdown: String, in url: URL?, confirmed: Bool, in workspace: MarkdownDocumentWorkspace) async -> OuroAX.Outcome {
        let target: URL
        switch resolve(url, in: workspace) {
        case .failure(let error): return refused("replace", error)
        case .success(let found): target = found
        }
        guard confirmed else {
            // Ask only about a document that can be replaced, so the person isn't asked and then refused.
            guard await workspace.markdown(for: target) != nil else {
                return refused("replace", .unreadable(target.lastPathComponent), target: target)
            }
            return OuroAX.Outcome(
                action: "replace",
                state: .needsHuman,
                summary: "Replacing \(name(of: target)) discards its current text, so the person confirms first.",
                target: ref(target),
                human: .init(
                    reason: "Replace overwrites all of \(name(of: target)); only the person can say that is what they want",
                    resume: .init("replace_document {\"document\": \(json(target.path)), \"confirmed\": true}", why: "run it again once the person has confirmed")
                )
            )
        }
        return await write(markdown, to: target, action: "replace", verb: "Replaced", in: workspace)
    }

    /// Joins with one blank line, as a new paragraph, and ends with a newline.
    nonisolated static func appending(_ addition: String, to markdown: String) -> String {
        let body = markdown.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        let extra = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return markdown }
        return body.isEmpty ? extra + "\n" : body + "\n\n" + extra + "\n"
    }

    // MARK: - Shared steps

    private static func write(_ text: String, to target: URL, action: String, verb: String, in workspace: MarkdownDocumentWorkspace) async -> OuroAX.Outcome {
        do {
            try await workspace.replaceMarkdown(text, in: target)
        } catch let error as DocumentIntentError {
            return refused(action, error, target: target)
        } catch {
            return OuroAX.Outcome(
                action: action, state: .failed, summary: "\(name(of: target)) was not changed.", target: ref(target),
                error: .init(code: "write-failed", exit: 1, thing: target.lastPathComponent, problem: error.localizedDescription, fix: "Check that the file is writable, then try again")
            )
        }
        let receipt = OuroAX.Receipt(id: UUID().uuidString, at: Date(), by: actor, why: nil)
        let readBack = await workspace.markdown(for: target)
        if let readBack, sameMarkdown(readBack, text) {
            return OuroAX.Outcome(
                action: action, state: .done, summary: "\(verb) \(name(of: target)).", target: ref(target),
                postcondition: .init(checked: true, holds: true, how: "read \(name(of: target)) back after the edit"),
                receipt: receipt
            )
        }
        // Formatting is compared away (the editor writes `*` lists, `_` emphasis), so a difference left is real text the
        // agent should look at before it edits again. The person hears only the summary.
        return OuroAX.Outcome(
            action: action, state: .uncertain,
            summary: "\(verb) \(name(of: target)).",
            target: ref(target),
            postcondition: .init(checked: true, holds: nil, how: "read \(name(of: target)) back after the edit; its text differs from what was sent, beyond Markdown formatting"),
            receipt: receipt,
            next: [.init("read_document {\"document\": \(json(target.path))}", why: "see the text as it is now before editing again")]
        )
    }

    private static func resolve(_ url: URL?, in workspace: MarkdownDocumentWorkspace) -> Result<URL, DocumentIntentError> {
        if let url { return .success(url.standardizedFileURL) }
        guard let front = workspace.frontDocumentURL() else { return .failure(.noDocument) }
        return .success(front)
    }

    private static func refused(_ action: String, _ error: DocumentIntentError, target: URL? = nil) -> OuroAX.Outcome {
        refused(action, problem: error.problem, target: target)
    }

    private static func refused(_ action: String, problem: OuroAX.Problem, target: URL? = nil) -> OuroAX.Outcome {
        OuroAX.Outcome(action: action, state: .refused, summary: problem.message, target: target.map(ref), error: problem)
    }

    static func name(of url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    static func ref(_ url: URL) -> OuroAX.Ref { .init(kind: "document", id: url.path, name: name(of: url)) }

    /// Whether two Markdown texts say the same thing: each is formatted the one swift-markdown way (list markers,
    /// emphasis, escaping), then compared line by line, keeping each line's indent, with inner runs of spaces and tabs as
    /// one and blank-line runs as one.
    /// Paragraphs still count: "a\n\nb" is not "a b".
    static func sameMarkdown(_ a: String, _ b: String) -> Bool {
        canonical(a) == canonical(b)
    }

    private static func canonical(_ text: String) -> [String] {
        let formatted = Document(parsing: text.replacingOccurrences(of: "\r\n", with: "\n")).format()
        var lines: [String] = []
        for raw in formatted.split(separator: "\n", omittingEmptySubsequences: false) {
            // Leading indent is kept (it nests lists and code); inner runs collapse and the end is trimmed.
            let indent = raw.prefix { $0 == " " || $0 == "\t" }
            let rest = raw.dropFirst(indent.count).replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: " +$", with: "", options: .regularExpression)
            let line = rest.isEmpty ? "" : indent + rest
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    private static func json(_ string: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? String(data: encoder.encode(string), encoding: .utf8)) ?? "\"\(string)\""
    }
}
