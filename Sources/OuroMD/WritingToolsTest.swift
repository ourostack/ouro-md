import AppKit
import WebKit

/// Headless `--writingtoolstest`: checks the editor side of a Writing Tools
/// session. It cannot drive Apple Intelligence itself, so it stands in for it:
/// marks a session active, edits the text with a DOM editing command (as
/// WebKit's Writing Tools does, through its own editing commands), then ends the
/// session. It fails unless the editor left the edited block alone during the
/// session, the result serializes to the expected Markdown afterwards, the edit
/// was reported dirty, and one undo restores the original.
final class WritingToolsTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let theme = ThemeStore.shared.defaultTheme
    private var sawDirty = false

    private static let original = "Intro **bold** text.\n\nSecond paragraph.\n"
    private static let expected = "Rewritten **bold** text.\n\nSecond paragraph.\n"

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        EditorWritingTools.enableInlineEditing(on: configuration)
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("writingtoolstest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHost(webView, size: frame.size)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            FileHandle.standardError.write(Data("writingtoolstest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "dirty", (body["dirty"] as? Bool) == true { sawDirty = true }
        guard type == "ready" else { return }
        let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
        webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
        webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.original)))", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.simulateSession() }
    }

    private func simulateSession() {
        let script = #"""
        const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
        const root = document.querySelector(".vditor-ir .vditor-reset");
        const block = root && root.querySelector("p");
        if (!block) { return { error: "no paragraph" }; }
        const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
        let text = null;
        while (walker.nextNode()) { if (walker.currentNode.data.indexOf("Intro") >= 0) { text = walker.currentNode; break; } }
        if (!text) { return { error: "no Intro text" }; }
        root.focus();
        const start = text.data.indexOf("Intro");
        const range = document.createRange();
        range.setStart(text, start);
        range.setEnd(text, start + 5);
        const selection = getSelection();
        selection.removeAllRanges();
        selection.addRange(range);

        window.ouro.setWritingToolsActive(true);
        const edited = document.execCommand("insertText", false, "Rewritten");
        await sleep(400);
        const blockUntouched = root.querySelector("p") === block && block.isConnected;
        window.ouro.setWritingToolsActive(false);
        await sleep(400);
        const markdown = window.ouro.getValue();
        window.ouro.undo();
        await sleep(400);
        const undone = window.ouro.getValue();
        return { edited, blockUntouched, markdown, undone };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else {
                FileHandle.standardError.write(Data("writingtoolstest: script failed: \(result)\n".utf8)); exit(1)
            }
            if let error = r["error"] as? String {
                FileHandle.standardError.write(Data("writingtoolstest: \(error)\n".utf8)); exit(1)
            }
            let edited = (r["edited"] as? Bool) ?? false
            let untouched = (r["blockUntouched"] as? Bool) ?? false
            let markdown = (r["markdown"] as? String) ?? ""
            let undone = (r["undone"] as? String) ?? ""
            let behavior = EditorWritingTools.behavior(of: self.webView.configuration)
            let behaviorOK: Bool
            if #available(macOS 15, *) { behaviorOK = behavior == NSWritingToolsBehavior.complete.rawValue } else { behaviorOK = true }
            let markdownOK = markdown == Self.expected
            let undoOK = undone == Self.original
            print("writing tools behavior: \(behavior.map(String.init) ?? "n/a") \(behaviorOK ? "✓" : "✗")")
            print("edit applied: \(edited) \(edited ? "✓" : "✗")")
            print("block left alone during session: \(untouched) \(untouched ? "✓" : "✗")")
            print("markdown after session: \(markdown.debugDescription) \(markdownOK ? "✓" : "✗")")
            print("reported dirty: \(self.sawDirty) \(self.sawDirty ? "✓" : "✗")")
            print("one undo restores original: \(undone.debugDescription) \(undoOK ? "✓" : "✗")")
            exit(behaviorOK && edited && untouched && markdownOK && self.sawDirty && undoOK ? 0 : 1)
        }
    }

    private func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
