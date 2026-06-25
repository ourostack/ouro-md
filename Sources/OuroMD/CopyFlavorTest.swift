import AppKit
import WebKit

/// Headless `--copyflavortest`: proves both the default copy and the explicit
/// Edit ▸ Copy as ▸ modes write the right clipboard flavors for the current
/// selection. It selects a bold/list/table/code document, then for each case
/// triggers a real copy (default `execCommand("copy")`, or `window.ouro.copyAs`)
/// and reads the actual `NSPasteboard`:
///   default  -> text/plain Markdown + text/html rendered.
///   markdown -> text/plain Markdown, no html.
///   plain    -> text/plain visible text (Markdown symbols stripped), no html.
///   html     -> text/html rendered + a plain-text fallback.
/// Guards both the dual-flavor default and the previously-broken Copy-as menu
/// (which used to copy the whole doc and write HTML as a plain string).
final class CopyFlavorTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private let theme = ThemeStore.shared.defaultTheme

    private struct Case { let name: String; let trigger: String }
    private let cases: [Case] = [
        Case(name: "default", trigger: "document.execCommand('copy');"),
        Case(name: "markdown", trigger: "window.ouro.copyAs('markdown');"),
        Case(name: "plain", trigger: "window.ouro.copyAs('plain');"),
        Case(name: "html", trigger: "window.ouro.copyAs('html');")
    ]
    private var caseIndex = 0
    private var allOK = true

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
        HeadlessHarness.configure()
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
        window = HeadlessHarness.offscreenHostActive(webView, size: frame.size)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 24) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.runCase() }
        } else if type == "triggered" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.readAndEvaluate() }
        }
    }

    private func runCase() {
        NSPasteboard.general.clearContents()
        let trigger = cases[caseIndex].trigger
        // Re-select all content before each copy (copyAs reads the live selection).
        let js = "(function(){window.ouro.focus();document.execCommand('selectAll');\(trigger)window.webkit.messageHandlers.ouro.postMessage({type:'triggered'});})();"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func readAndEvaluate() {
        let pb = NSPasteboard.general
        let plain = pb.string(forType: .string) ?? ""
        let html = pb.string(forType: .html) ?? ""
        let name = cases[caseIndex].name
        let lowerHTML = html.lowercased()
        let htmlRendered = lowerHTML.contains("<strong>") && lowerHTML.contains("<table")
        let plainHasMarkdown = plain.contains("**bold copy**")
        let plainHasVisible = plain.contains("bold copy")
        var ok = false
        switch name {
        case "default":
            ok = plainHasMarkdown && htmlRendered
        case "markdown":
            ok = plainHasMarkdown && html.isEmpty
        case "plain":
            // Visible text present, but the markdown bold markers stripped.
            ok = plainHasVisible && !plainHasMarkdown && html.isEmpty
        case "html":
            ok = htmlRendered && plainHasVisible && !plainHasMarkdown
        default:
            ok = false
        }
        print("\(name.padding(toLength: 9, withPad: " ", startingAt: 0)): \(ok ? "✓" : "✗")  plain[md=\(plainHasMarkdown) vis=\(plainHasVisible)] html[rendered=\(htmlRendered) empty=\(html.isEmpty)]")
        if !ok { allOK = false }
        caseIndex += 1
        if caseIndex < cases.count {
            runCase()
        } else {
            exit(allOK ? 0 : 1)
        }
    }
}

private func jsLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value]),
       let json = String(data: data, encoding: .utf8) {
        return String(json.dropFirst().dropLast())
    }
    return "\"\""
}
