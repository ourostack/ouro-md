import AppKit
import WebKit

/// Headless `--copyflavortest`: proves that copying from Ouro MD puts BOTH a
/// rendered-HTML flavor and a Markdown flavor on the system clipboard, so rich
/// targets (Teams, Word, mail) paste formatted while plain targets get clean
/// Markdown. Renders a doc with bold/list/table/inline-code, selects it in the
/// real editor, triggers a real `copy`, and reads the actual `NSPasteboard` —
/// failing unless the plain flavor reads as Markdown and the HTML flavor reads
/// as rendered HTML. (execCommand copy needs a focused editable, so the view is
/// hosted in an off-screen key window, like --undotest.)
final class CopyFlavorTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private let theme = ThemeStore.shared.defaultTheme

    private static let doc = [
        "# Copy flavor check",
        "",
        "A paragraph with **bold copy** and `inline code` to copy.",
        "",
        "- first item",
        "- second item",
        "",
        "| Stage | Owner |",
        "| - | - |",
        "| Extract | TaskMgmtV2 |",
        ""
    ].joined(separator: "\n")

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("copyflavortest: index.html not found\n".utf8)); exit(1)
        }
        // Off-screen KEY window so the editable can focus and execCommand("copy") works.
        window = DocumentWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
            FileHandle.standardError.write(Data("copyflavortest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.doc)));window.ouro.focus();", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.copyStep() }
        } else if type == "copied" {
            pendingSelectedLen = (body["selectedLen"] as? Int) ?? 0
            // Give the copy a beat to land on NSPasteboard, then read it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.readClipboard() }
        }
    }

    private func copyStep() {
        // Clear the pasteboard so we read only what this copy writes.
        NSPasteboard.general.clearContents()
        let js = #"""
        (function () {
          window.ouro.focus();
          document.execCommand("selectAll");
          var sel = window.getSelection();
          var len = sel.toString().length;
          document.execCommand("copy");
          window.webkit.messageHandlers.ouro.postMessage({ type: "copied", selectedLen: len });
        })();
        """#
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private var pendingSelectedLen = 0
    private func readClipboard() {
        let pb = NSPasteboard.general
        let plain = pb.string(forType: .string) ?? ""
        let html = pb.string(forType: .html) ?? ""
        evaluate(selectedLen: pendingSelectedLen, plain: plain, html: html)
    }

    private func evaluate(selectedLen: Int, plain: String, html: String) {
        // Markdown flavor: bold + table + list markers present.
        let plainIsMarkdown = plain.contains("**bold copy**") && plain.contains("|") && plain.contains("`inline code`")
        // Rich flavor: rendered HTML tags present.
        let lowerHTML = html.lowercased()
        let htmlIsRendered = lowerHTML.contains("<strong>") && lowerHTML.contains("<table") && (lowerHTML.contains("<li>") || lowerHTML.contains("<ul>"))
        func mark(_ ok: Bool) -> String { ok ? "✓" : "✗" }
        print("selection non-empty:        \(mark(selectedLen > 0)) (\(selectedLen) chars)")
        print("plain flavor is Markdown:   \(mark(plainIsMarkdown))")
        print("html flavor is rendered:    \(mark(htmlIsRendered))")
        if !plainIsMarkdown { print("  plain head: \(String(plain.prefix(80)))") }
        if !htmlIsRendered { print("  html head:  \(String(html.prefix(80)))") }
        let ok = selectedLen > 0 && plainIsMarkdown && htmlIsRendered
        exit(ok ? 0 : 1)
    }
}

private func jsLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value]),
       let json = String(data: data, encoding: .utf8) {
        return String(json.dropFirst().dropLast())
    }
    return "\"\""
}
