import AppIntents
import Foundation
import OuroAX

/// The one handler behind each action declared in `actions/document.actions.mts`. The generated App Intents and
/// buttons, the MCP tools and the menu commands all call `<Action>.run`, which calls the handler set here, which
/// calls `DocumentActions`. Nothing else decides what an action does.
///
/// A refused or failed outcome is thrown as its `OuroAX.Problem`, whose fix says what to do next: Siri and Shortcuts
/// show it, and the MCP door answers it as a tool error.
@MainActor
enum DocumentActionHandlers {
    /// Binds every declared action. Safe to call again; the app calls it at launch and the MCP door at start.
    static func install() {
        ListDocumentsAction.perform = { input in
            let found = DocumentActions.find(input.query, in: try liveWorkspace())
            return ListDocumentsOutput(documents: found.map { "\($0.name)  \($0.id)" }.joined(separator: "\n"), count: found.count)
        }
        ReadDocumentAction.perform = { input in
            let workspace = try liveWorkspace()
            let url = try locate(input.document, in: workspace)
            let (text, outcome) = await DocumentActions.read(url, in: workspace)
            guard let text else { throw problem(of: outcome) }
            let target = url ?? workspace.frontDocumentURL() ?? URL(fileURLWithPath: outcome.target?.id ?? "")
            return ReadDocumentOutput(markdown: text, name: DocumentActions.name(of: target), path: target.path, length: text.count, next: nil)
        }
        AppendToDocumentAction.perform = { input in
            let workspace = try liveWorkspace()
            let outcome = try checked(await DocumentActions.append(input.markdown, to: try locate(input.document, in: workspace), in: workspace))
            return AppendToDocumentOutput(state: outcome.state.rawValue, summary: outcome.summary, checked: outcome.postcondition.how, next: outcome.next.first?.command)
        }
        ReplaceDocumentAction.perform = { input in
            // The door has already asked the person (the intent's confirmation, the menu's alert, the MCP call's
            // `confirmed`), so this replaces.
            let workspace = try liveWorkspace()
            let outcome = try checked(await DocumentActions.replace(with: input.markdown, in: try locate(input.document, in: workspace), confirmed: true, in: workspace))
            return ReplaceDocumentOutput(state: outcome.state.rawValue, summary: outcome.summary, checked: outcome.postcondition.how, next: outcome.next.first?.command)
        }
        OpenDocumentAction.perform = { input in
            let workspace = try liveWorkspace()
            guard let url = try locate(input.document, in: workspace) else { throw DocumentIntentError.noDocument.problem }
            guard workspace.isReadable(url) else { throw DocumentIntentError.unreadable(url.lastPathComponent).problem }
            workspace.open(url)
            return OpenDocumentOutput(summary: "Opened \(DocumentActions.name(of: url)).")
        }

        // What Siri and Shortcuts say. An error is rethrown so the system shows its fix.
        ListDocumentsAction.dialog = { _, result in
            let output = try result.get()
            return IntentDialog(stringLiteral: output.count == 1 ? "1 document." : "\(output.count) documents.")
        }
        ReadDocumentAction.dialog = { _, result in
            let output = try result.get()
            return IntentDialog(stringLiteral: "Read \(output.name): \(output.length) characters.")
        }
        AppendToDocumentAction.dialog = { _, result in IntentDialog(stringLiteral: try result.get().summary) }
        ReplaceDocumentAction.dialog = { _, result in IntentDialog(stringLiteral: try result.get().summary) }
        OpenDocumentAction.dialog = { _, result in IntentDialog(stringLiteral: try result.get().summary) }
    }

    /// The live workspace, or the problem that says the app isn't ready.
    static func liveWorkspace() throws -> MarkdownDocumentWorkspace {
        guard let workspace = DocumentIntentsWorkspace.current else { throw DocumentIntentError.appNotReady.problem }
        return workspace
    }

    /// The document the input names (a name or a path), or nil for the one on screen.
    static func locate(_ reference: String?, in workspace: MarkdownDocumentWorkspace) throws -> URL? {
        guard let reference, !reference.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        switch workspace.locate(reference) {
        case .success(let url): return url
        case .failure(let problem): throw problem
        }
    }

    /// The outcome, or its problem when it was refused or failed.
    static func checked(_ outcome: OuroAX.Outcome) throws -> OuroAX.Outcome {
        if outcome.state == .refused || outcome.state == .failed { throw problem(of: outcome) }
        return outcome
    }

    private static func problem(of outcome: OuroAX.Outcome) -> OuroAX.Problem {
        outcome.error ?? OuroAX.Problem(code: "failed", exit: 1, thing: outcome.action, problem: outcome.summary, fix: "Try again")
    }
}
