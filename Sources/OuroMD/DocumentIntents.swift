import AppIntents
import AppKit
import CoreSpotlight
import CoreTransferable
import OuroAX
import UniformTypeIdentifiers

/// What Siri, Shortcuts and Spotlight can do with Ouro MD documents. The app
/// delegate is the live workspace; tests install their own.
@MainActor
protocol MarkdownDocumentWorkspace: AnyObject {
    /// Documents the app can reach right now: open windows first, then recents.
    func knownDocumentURLs() -> [URL]
    func isReadable(_ url: URL) -> Bool
    /// The document in the window the person is looking at, if any.
    func frontDocumentURL() -> URL?
    /// The document's current Markdown: the editor's text when it is open
    /// (including unsaved edits), else the file on disk.
    func markdown(for url: URL) async -> String?
    /// Replaces the document's Markdown. An open document takes it in its
    /// editor as one undoable edit that autosave persists; a closed one is
    /// written to disk.
    func replaceMarkdown(_ markdown: String, in url: URL) async throws
    func open(_ url: URL)
    /// The document a person or an agent named: a name or a path. The default finds it among the known documents.
    func locate(_ reference: String) -> Result<URL, OuroAX.Problem>
}

extension MarkdownDocumentWorkspace {
    func locate(_ reference: String) -> Result<URL, OuroAX.Problem> {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            let url = URL(fileURLWithPath: trimmed).standardizedFileURL
            return isReadable(url) ? .success(url) : .failure(DocumentIntentError.unreadable(url.lastPathComponent).problem)
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

@MainActor
enum DocumentIntentsWorkspace {
    static weak var current: MarkdownDocumentWorkspace?
}

/// Why an intent or an MCP call could not act, each as an `OuroAX.Problem` whose fix says what to do next.
enum DocumentIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case noDocument
    case unreadable(String)
    case writingToolsActive(String)
    case locked(String)
    case needsOpenDocument(String)

    var problem: OuroAX.Problem {
        switch self {
        case .appNotReady:
            return .init(code: "not-ready", exit: 1, thing: "Ouro MD", problem: "it isn't ready yet", fix: "Try again in a moment")
        case .noDocument:
            return .init(code: "no-document", exit: 2, thing: "Ouro MD", problem: "no Markdown document is open", fix: "Open one in Ouro MD, or name the document to use")
        case .unreadable(let name):
            return .init(code: "unreadable", exit: 1, thing: name, problem: "Ouro MD can't read it", fix: "Check that the file still exists and that Ouro MD may open it, then try again")
        case .writingToolsActive(let name):
            return .init(code: "writing-tools-active", exit: 1, thing: name, problem: "Writing Tools is editing it", fix: "Finish or cancel Writing Tools, then try again")
        case .locked(let name):
            return .init(code: "locked", exit: 1, thing: name, problem: "the file is locked", fix: "Unlock it in the Finder (File > Get Info), then try again")
        case .needsOpenDocument(let name):
            return .init(code: "not-utf8", exit: 1, thing: name, problem: "it isn't UTF-8 text", fix: "Open it in Ouro MD first, then try again")
        }
    }

    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: problem.message) }
}

/// A Markdown document Ouro MD can open, read and edit, identified by its file
/// path. It transfers as its Markdown text, so Siri and other apps can read the
/// document itself rather than pixels of the editor.
public struct MarkdownDocumentEntity: AppEntity, Transferable {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Markdown Document")
    public static var defaultQuery = MarkdownDocumentQuery()

    public let id: String
    var url: URL { URL(fileURLWithPath: id) }

    // What a person asks about a document. Descriptions need the Siri AI SDK (27.3); see README, "Siri AI".
    #if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)
    @Property(title: "Name", description: "The document's file name, without the .md extension.")
    public var name: String
    @Property(title: "Folder", description: "The name of the folder the document is in.")
    public var folder: String
    @Property(title: "Modified", description: "When the file was last saved.")
    public var modified: Date?
    #else
    @Property(title: "Name")
    public var name: String
    @Property(title: "Folder")
    public var folder: String
    @Property(title: "Modified")
    public var modified: Date?
    #endif

    /// The entity for the document at this path, which is what Input, MCP and the CLI call its id.
    public init(id: String) { self.init(url: URL(fileURLWithPath: id)) }

    init(url: URL) {
        let url = url.standardizedFileURL
        id = url.path
        name = url.deletingPathExtension().lastPathComponent
        folder = url.deletingLastPathComponent().lastPathComponent
        // Inside the remembered access, so the sandboxed build can read a recent file's date.
        modified = DocumentAccess.withAccess(to: url) { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(folder)",
            image: .init(systemName: "doc.richtext")
        )
    }

    public static var transferRepresentation: some TransferRepresentation {
        // Spelled inline: the App Intents metadata processor only resolves literal UTTypes.
        DataRepresentation(exportedContentType: UTType(importedAs: "net.daringfireball.markdown")) { entity in
            Data(try await entity.markdown().utf8)
        }
        DataRepresentation(exportedContentType: .plainText) { entity in
            Data(try await entity.markdown().utf8)
        }
    }

    @MainActor
    func markdown() async throws -> String {
        guard let workspace = DocumentIntentsWorkspace.current else { throw DocumentIntentError.appNotReady.problem }
        guard let text = await workspace.markdown(for: url) else { throw DocumentIntentError.unreadable(name).problem }
        return text
    }
}

public struct MarkdownDocumentQuery: EntityStringQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [MarkdownDocumentEntity.ID]) async throws -> [MarkdownDocumentEntity] {
        guard let workspace = DocumentIntentsWorkspace.current else { return [] }
        return identifiers.map { URL(fileURLWithPath: $0) }.filter(workspace.isReadable).map(MarkdownDocumentEntity.init(url:))
    }

    @MainActor
    public func entities(matching string: String) async throws -> [MarkdownDocumentEntity] {
        guard let workspace = DocumentIntentsWorkspace.current else { return [] }
        return DocumentActions.find(string, in: workspace)
    }

    @MainActor
    public func suggestedEntities() async throws -> [MarkdownDocumentEntity] {
        guard let workspace = DocumentIntentsWorkspace.current else { return [] }
        return DocumentActions.find(nil, in: workspace)
    }
}

@available(macOS 15, *)
extension MarkdownDocumentEntity: IndexedEntity {}

// The App Intents themselves are generated from actions/document.actions.mts (Generated/OuroActions.swift); what is
// written here is what a declaration can't say: the entity, the shortcut phrases and the Siri AI conformances.
//
// Siri AI Developer Preview: the intents become tools Siri can call. `ToolIntent` exists only in the 27.3 beta SDK
// (AppIntents newer than 301.1), so this compiles to nothing with Xcode 27.2; see README, "Siri AI".
#if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)
@available(macOS 27.3, *) extension OpenDocumentIntent: ToolIntent {}
@available(macOS 27.3, *) extension ReadDocumentIntent: ToolIntent {}
@available(macOS 27.3, *) extension AppendToDocumentIntent: ToolIntent {}
@available(macOS 27.3, *) extension ReplaceDocumentIntent: ToolIntent {}
@available(macOS 27.3, *) extension ListDocumentsIntent: ToolIntent {}
#endif

struct OuroMDShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDocumentIntent(),
            phrases: ["Open a document in \(.applicationName)", "Open \(\.$document) in \(.applicationName)"],
            shortTitle: "Open Document",
            systemImageName: "doc.richtext"
        )
        AppShortcut(
            intent: ReadDocumentIntent(),
            phrases: ["Read my document in \(.applicationName)", "Get the Markdown from \(.applicationName)"],
            shortTitle: "Get Markdown",
            systemImageName: "doc.plaintext"
        )
        AppShortcut(
            intent: AppendToDocumentIntent(),
            phrases: ["Add to my document in \(.applicationName)", "Append to my document in \(.applicationName)"],
            shortTitle: "Add to Document",
            systemImageName: "text.append"
        )
    }
}

/// Makes the document on screen visible to Siri and indexes known documents
/// for Spotlight and Apple Intelligence.
@MainActor
enum DocumentIntentsPresence {
    static let activityType = "bot.ouro.md.document"
    private static var indexed = Set<String>()

    static func update(window: NSWindow, documentURL: URL?) {
        guard #available(macOS 15.2, *) else { return }
        guard let documentURL else {
            window.userActivity = nil
            return
        }
        let entity = MarkdownDocumentEntity(url: documentURL)
        if indexed.insert(entity.id).inserted { index([documentURL]) }
        let activity = window.userActivity?.activityType == activityType ? window.userActivity! : NSUserActivity(activityType: activityType)
        activity.title = entity.name
        activity.appEntityIdentifier = EntityIdentifier(for: entity)
        window.userActivity = activity
        if window.isKeyWindow { activity.becomeCurrent() }
    }

    static func index(_ urls: [URL]) {
        guard #available(macOS 15, *), !urls.isEmpty else { return }
        let entities = urls.map(MarkdownDocumentEntity.init(url:))
        Task { try? await CSSearchableIndex.default().indexAppEntities(entities) }
    }
}

/// Text handling for edits to documents that aren't open in a window.
enum DocumentIntentsFileText {
    /// Keeps a CRLF file CRLF after an assistant's edit joins lines with LF.
    static func matchingLineEndings(_ text: String, of original: String) -> String {
        guard original.contains("\r\n") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
    }
    /// Rewrites a closed document's file with new Markdown, keeping its line endings. A file that isn't UTF-8 is
    /// refused: rewriting it with no window and no undo would silently change its encoding.
    static func write(_ markdown: String, to url: URL) throws {
        let file = url.resolvingSymlinksInPath()
        let data = try Data(contentsOf: file)
        guard let original = String(data: data, encoding: .utf8) else {
            throw DocumentIntentError.needsOpenDocument(url.lastPathComponent)
        }
        let text = matchingLineEndings(markdown, of: original)
        do {
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch CocoaError.fileWriteNoPermission where DocumentAccess.isSandboxed {
            // An atomic write makes a temporary file beside the original, which a grant for the file alone doesn't
            // allow; rewrite the file in place instead.
            try Data(text.utf8).write(to: file, options: [])
        }
    }
}
