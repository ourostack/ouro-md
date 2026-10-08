import AppIntents
import AppKit
import CoreSpotlight
import CoreTransferable
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
}

@MainActor
enum DocumentIntentsWorkspace {
    static weak var current: MarkdownDocumentWorkspace?
}

enum DocumentIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case noDocument
    case unreadable(String)
    case writingToolsActive(String)
    case needsOpenDocument(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: return "Ouro MD isn't ready yet. Try again in a moment."
        case .noDocument: return "There's no Markdown document open in Ouro MD."
        case .unreadable(let name): return "Ouro MD can't read \(name)."
        case .writingToolsActive(let name): return "Writing Tools is editing \(name). Finish or cancel it, then try again."
        case .needsOpenDocument(let name): return "\(name) isn't UTF-8 text. Open it in Ouro MD first, then try again."
        }
    }
}

/// A Markdown document Ouro MD can open, read and edit, identified by its file
/// path. It transfers as its Markdown text, so Siri and other apps can read the
/// document itself rather than pixels of the editor.
struct MarkdownDocumentEntity: AppEntity, Transferable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Markdown Document")
    static var defaultQuery = MarkdownDocumentQuery()

    let id: String
    var url: URL { URL(fileURLWithPath: id) }
    var name: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL) { id = url.standardizedFileURL.path }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(url.deletingLastPathComponent().lastPathComponent)",
            image: .init(systemName: "doc.richtext")
        )
    }

    static var transferRepresentation: some TransferRepresentation {
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
        guard let workspace = DocumentIntentsWorkspace.current else { throw DocumentIntentError.appNotReady }
        guard let text = await workspace.markdown(for: url) else { throw DocumentIntentError.unreadable(name) }
        return text
    }
}

struct MarkdownDocumentQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [MarkdownDocumentEntity.ID]) async throws -> [MarkdownDocumentEntity] {
        guard let workspace = DocumentIntentsWorkspace.current else { return [] }
        return identifiers.map { URL(fileURLWithPath: $0) }.filter(workspace.isReadable).map(MarkdownDocumentEntity.init(url:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [MarkdownDocumentEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await suggestedEntities().filter {
            needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [MarkdownDocumentEntity] {
        guard let workspace = DocumentIntentsWorkspace.current else { return [] }
        var seen = Set<String>()
        return workspace.knownDocumentURLs().map(MarkdownDocumentEntity.init(url:)).filter { seen.insert($0.id).inserted }
    }
}

@available(macOS 15, *)
extension MarkdownDocumentEntity: IndexedEntity {}

/// Resolves an optional document parameter to the document on screen.
@MainActor
private func resolve(_ document: MarkdownDocumentEntity?) throws -> (MarkdownDocumentWorkspace, URL) {
    guard let workspace = DocumentIntentsWorkspace.current else { throw DocumentIntentError.appNotReady }
    if let document { return (workspace, document.url) }
    guard let url = workspace.frontDocumentURL() else { throw DocumentIntentError.noDocument }
    return (workspace, url)
}

struct OpenMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Markdown Document"
    static var description = IntentDescription("Opens a Markdown document in Ouro MD.")
    static var openAppWhenRun = true

    @Parameter(title: "Document")
    var document: MarkdownDocumentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let workspace = DocumentIntentsWorkspace.current else { throw DocumentIntentError.appNotReady }
        workspace.open(document.url)
        return .result()
    }
}

struct GetMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Markdown Document"
    static var description = IntentDescription("Returns the Markdown of a document in Ouro MD, including unsaved edits. Without a document, uses the one on screen.")

    @Parameter(title: "Document")
    var document: MarkdownDocumentEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (workspace, url) = try resolve(document)
        guard let text = await workspace.markdown(for: url) else {
            throw DocumentIntentError.unreadable(url.lastPathComponent)
        }
        return .result(value: text)
    }
}

struct AppendToMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Markdown Document"
    static var description = IntentDescription("Adds Markdown to the end of a document in Ouro MD as one undoable edit. Without a document, uses the one on screen.")

    @Parameter(title: "Markdown", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Document")
    var document: MarkdownDocumentEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let (workspace, url) = try resolve(document)
        guard let current = await workspace.markdown(for: url) else {
            throw DocumentIntentError.unreadable(url.lastPathComponent)
        }
        try await workspace.replaceMarkdown(Self.appending(text, to: current), in: url)
        return .result()
    }

    /// Joins with one blank line, as a new paragraph, and ends with a newline.
    static func appending(_ addition: String, to markdown: String) -> String {
        let body = markdown.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        let extra = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return markdown }
        return body.isEmpty ? extra + "\n" : body + "\n\n" + extra + "\n"
    }
}

struct ReplaceMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Replace Markdown Document"
    static var description = IntentDescription("Replaces the Markdown of a document in Ouro MD as one undoable edit. Without a document, uses the one on screen.")

    @Parameter(title: "Markdown", inputOptions: String.IntentInputOptions(multiline: true))
    var markdown: String

    @Parameter(title: "Document")
    var document: MarkdownDocumentEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let (workspace, url) = try resolve(document)
        try await workspace.replaceMarkdown(markdown, in: url)
        return .result()
    }
}

struct OuroMDShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenMarkdownDocumentIntent(),
            phrases: ["Open a document in \(.applicationName)", "Open \(\.$document) in \(.applicationName)"],
            shortTitle: "Open Document",
            systemImageName: "doc.richtext"
        )
        AppShortcut(
            intent: GetMarkdownDocumentIntent(),
            phrases: ["Read my document in \(.applicationName)", "Get the Markdown from \(.applicationName)"],
            shortTitle: "Get Markdown",
            systemImageName: "doc.plaintext"
        )
        AppShortcut(
            intent: AppendToMarkdownDocumentIntent(),
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
}
