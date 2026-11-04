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
struct MarkdownDocumentEntity: AppEntity, Transferable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Markdown Document")
    static var defaultQuery = MarkdownDocumentQuery()

    let id: String
    var url: URL { URL(fileURLWithPath: id) }

    // What a person asks about a document. Descriptions need the Siri AI SDK (27.3); see README, "Siri AI".
    #if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)
    @Property(title: "Name", description: "The document's file name, without the .md extension.")
    var name: String
    @Property(title: "Folder", description: "The name of the folder the document is in.")
    var folder: String
    @Property(title: "Modified", description: "When the file was last saved.")
    var modified: Date?
    #else
    @Property(title: "Name")
    var name: String
    @Property(title: "Folder")
    var folder: String
    @Property(title: "Modified")
    var modified: Date?
    #endif

    init(url: URL) {
        let url = url.standardizedFileURL
        id = url.path
        name = url.deletingPathExtension().lastPathComponent
        folder = url.deletingLastPathComponent().lastPathComponent
        // Inside the remembered access, so the sandboxed build can read a recent file's date.
        modified = DocumentAccess.withAccess(to: url) { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(folder)",
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
        guard let workspace = DocumentIntentsWorkspace.current else { throw DocumentIntentError.appNotReady.problem }
        guard let text = await workspace.markdown(for: url) else { throw DocumentIntentError.unreadable(name).problem }
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
        guard let workspace = DocumentIntentsWorkspace.current else { return [] }
        return DocumentActions.find(string, in: workspace)
    }

    @MainActor
    func suggestedEntities() async throws -> [MarkdownDocumentEntity] {
        guard let workspace = DocumentIntentsWorkspace.current else { return [] }
        return DocumentActions.find(nil, in: workspace)
    }
}

@available(macOS 15, *)
extension MarkdownDocumentEntity: IndexedEntity {}

/// The live workspace, or the problem that says the app isn't ready.
@MainActor
private func liveWorkspace() throws -> MarkdownDocumentWorkspace {
    guard let workspace = DocumentIntentsWorkspace.current else { throw DocumentIntentError.appNotReady.problem }
    return workspace
}

/// Turns a refused or failed outcome into the problem Siri and Shortcuts show.
private func check(_ outcome: OuroAX.Outcome) throws -> OuroAX.Outcome {
    if outcome.state == .refused || outcome.state == .failed, let error = outcome.error { throw error }
    return outcome
}

struct OpenMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Markdown Document"
    static var description = IntentDescription("Opens a Markdown document in Ouro MD.")
    static var openAppWhenRun = true

    @Parameter(title: "Document", description: "The Markdown document to open, by name.")
    var document: MarkdownDocumentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        try liveWorkspace().open(document.url)
        return .result()
    }
}

struct GetMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Markdown Document"
    static var description = IntentDescription("Returns the Markdown of a document in Ouro MD, including unsaved edits. Without a document, uses the one on screen.")

    @Parameter(title: "Document", description: "The Markdown document to read. Leave it empty for the document on screen.")
    var document: MarkdownDocumentEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (text, outcome) = await DocumentActions.read(document?.url, in: try liveWorkspace())
        _ = try check(outcome)
        return .result(value: text ?? "")
    }
}

struct AppendToMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Markdown Document"
    static var description = IntentDescription("Adds Markdown to the end of a document in Ouro MD as one undoable edit. Without a document, uses the one on screen.")

    @Parameter(title: "Markdown", description: "The Markdown to add as a new paragraph at the end.", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Document", description: "The Markdown document to add to. Leave it empty for the document on screen.")
    var document: MarkdownDocumentEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try check(await DocumentActions.append(text, to: document?.url, in: try liveWorkspace()))
        return .result(dialog: outcome.dialog)
    }

    /// Joins with one blank line, as a new paragraph, and ends with a newline.
    static func appending(_ addition: String, to markdown: String) -> String {
        DocumentActions.appending(addition, to: markdown)
    }
}

struct ReplaceMarkdownDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Replace Markdown Document"
    static var description = IntentDescription("Replaces the Markdown of a document in Ouro MD as one undoable edit, after you confirm. Without a document, uses the one on screen.")

    @Parameter(title: "Markdown", description: "The Markdown that becomes the document's whole text.", inputOptions: String.IntentInputOptions(multiline: true))
    var markdown: String

    @Parameter(title: "Document", description: "The Markdown document to replace. Leave it empty for the document on screen.")
    var document: MarkdownDocumentEntity?

    /// Asks the person before the document's text is replaced; throwing stops the intent. Tests swap it.
    @MainActor static var confirm: (ReplaceMarkdownDocumentIntent, String) async throws -> Void = askThePerson
    @MainActor static let askThePerson: (ReplaceMarkdownDocumentIntent, String) async throws -> Void = { intent, prompt in
        try await intent.requestConfirmation(dialog: IntentDialog(stringLiteral: prompt))
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let workspace = try liveWorkspace()
        // The same rule as every door: Replace asks the person first. The confirmed edit goes to the document the
        // person was asked about, even if another window comes to the front while they answer.
        let asking = try check(await DocumentActions.replace(with: markdown, in: document?.url, confirmed: false, in: workspace))
        guard asking.state == .needsHuman, let target = asking.target else {
            throw OuroAX.Problem(code: "not-confirmed", exit: 1, thing: "Replace", problem: "Ouro MD couldn't ask before replacing, so nothing was changed", fix: "Try again")
        }
        try await Self.confirm(self, "Replace all of \(target.name ?? target.id) with the new Markdown?")
        let outcome = try check(await DocumentActions.replace(with: markdown, in: URL(fileURLWithPath: target.id), confirmed: true, in: workspace))
        return .result(dialog: outcome.dialog)
    }
}

// Siri AI Developer Preview: the intents become tools Siri can call. `ToolIntent` exists only in the 27.3 beta SDK
// (AppIntents newer than 301.1), so this compiles to nothing with Xcode 27.2; see README, "Siri AI".
#if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)
@available(macOS 27.3, *) extension OpenMarkdownDocumentIntent: ToolIntent {}
@available(macOS 27.3, *) extension GetMarkdownDocumentIntent: ToolIntent {}
@available(macOS 27.3, *) extension AppendToMarkdownDocumentIntent: ToolIntent {}
@available(macOS 27.3, *) extension ReplaceMarkdownDocumentIntent: ToolIntent {}
#endif

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
