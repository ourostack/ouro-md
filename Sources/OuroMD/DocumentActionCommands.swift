import AppKit
import OuroAX

/// The menu commands that take a declared action. Each one asks the person for what the action needs, then calls the
/// action's `run`, the same call the App Intent, the MCP tool and the button make; the title is the declaration's label.
@MainActor
enum DocumentActionCommands {
    /// What a command is, so the menu and the tests name it once.
    enum Command: String, CaseIterable {
        case addToDocument, replaceFromClipboard

        /// The declared action's label, from the generated intent, so the menu can't word it differently.
        var title: String {
            switch self {
            case .addToDocument: String(localized: AppendToDocumentIntent.title)
            case .replaceFromClipboard: String(localized: ReplaceDocumentIntent.title)
            }
        }

        /// The menu item's title: the label, then an ellipsis because the command asks first.
        var menuTitle: String { title + "…" }
    }

    /// How the commands ask the person. Tests swap these; the app shows an alert.
    static let defaultAskMarkdown: @MainActor (_ title: String, _ message: String) -> String? = { presentMarkdownPrompt(title: $0, message: $1) }
    static let defaultConfirm: @MainActor (_ title: String, _ message: String, _ button: String) -> Bool = { presentConfirmation(title: $0, message: $1, button: $2) }
    static let defaultShow: @MainActor (_ problem: OuroAX.Problem) -> Void = { presentProblem($0) }
    static let defaultClipboard: @MainActor () -> String? = { NSPasteboard.general.string(forType: .string) }
    static var askMarkdown = defaultAskMarkdown
    static var confirm = defaultConfirm
    static var show = defaultShow
    static var clipboard = defaultClipboard

    /// Runs the command on the front document. Returns the outcome's summary, or nil when the person said no.
    @discardableResult
    static func run(_ command: Command, in workspace: MarkdownDocumentWorkspace?) async -> String? {
        guard let workspace = workspace ?? DocumentIntentsWorkspace.current, let front = workspace.frontDocumentURL() else {
            show(DocumentIntentError.noDocument.problem)
            return nil
        }
        let name = DocumentActions.name(of: front)
        do {
            switch command {
            case .addToDocument:
                guard let markdown = askMarkdown(command.title, "The Markdown to add to the end of \(name), as one undoable edit.") else { return nil }
                return try await AppendToDocumentAction.run(.init(markdown: markdown, document: front.path)).summary
            case .replaceFromClipboard:
                guard let markdown = clipboard(), !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    show(.init(code: "empty-clipboard", exit: 2, thing: "the clipboard", problem: "it holds no text", fix: "Copy the Markdown to use, then try again"))
                    return nil
                }
                guard confirm(command.title, "Replace all of \(name) with the Markdown on the clipboard? You can undo it.", "Replace") else { return nil }
                return try await ReplaceDocumentAction.run(.init(markdown: markdown, document: front.path)).summary
            }
        } catch let problem as OuroAX.Problem {
            show(problem)
        } catch {
            show(.init(code: "failed", exit: 1, thing: command.title, problem: error.localizedDescription, fix: "Try again"))
        }
        return nil
    }

    // MARK: - The alerts

    private static func presentMarkdownPrompt(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 120))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.autoresizingMask = [.width]
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = text
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let markdown = text.string
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : markdown
    }

    private static func presentConfirmation(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func presentProblem(_ problem: OuroAX.Problem) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = problem.thing
        alert.informativeText = problem.message
        alert.runModal()
    }
}
