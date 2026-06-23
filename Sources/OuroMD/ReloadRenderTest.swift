import AppKit
import WebKit

/// Headless `--reloadrendertest`: proves the core agent↔human loop renders rich
/// content correctly across a live-reload. Loads a doc whose Mermaid diagram
/// carries a sentinel label (ALPHANODE), waits for the SVG to render, then
/// live-reloads — via the same `window.ouro.reloadValue` the FileWatcher uses on
/// an external rewrite — to a doc whose diagram carries a different sentinel
/// (BETANODE). It fails unless the new diagram actually rendered (SVG present),
/// the new label is visible, the old label is gone (no stale frame from
/// Mermaid's `data-processed` cache), and the reader's scroll position is
/// preserved. Theme is applied via `setTheme`, exactly as the app does.
final class ReloadRenderTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let theme = ThemeStore.shared.defaultTheme

    private static let docAlpha = [
        "# Live-reload render check",
        "",
        String(repeating: "Filler paragraph to give the document scroll height.\n\n", count: 40),
        "```mermaid",
        "flowchart LR",
        "  A[\"ALPHANODE source<br/>first line<br/>second line\"] --> B[\"ALPHANODE sink\"]",
        "```",
        ""
    ].joined(separator: "\n")

    private static let docBeta = [
        "# Live-reload render check",
        "",
        String(repeating: "Filler paragraph to give the document scroll height.\n\n", count: 40),
        "```mermaid",
        "flowchart LR",
        "  X[\"BETANODE source<br/>first line<br/>second line\"] --> Y[\"BETANODE sink\"]",
        "```",
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
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("reloadrendertest: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            FileHandle.standardError.write(Data("reloadrendertest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.docAlpha)))", completionHandler: nil)
            waitForRender(expect: "ALPHANODE", stage: "alpha")
        case "rendered":
            let stage = body["stage"] as? String ?? ""
            if stage == "alpha" {
                // Scroll to a fixed offset inside the filler ABOVE the diagram, so
                // the scroll anchor sits in content whose height can't change when
                // the diagram below reflows on reload. Then live-reload to BETA and
                // assert the swap + that the reader's place is preserved.
                webView.evaluateJavaScript("(function(){var s=document.scrollingElement||document.documentElement;s.scrollTop=150;return s.scrollTop;})()") { [weak self] result, _ in
                    let y = (result as? Double) ?? (result as? Int).map(Double.init) ?? 0
                    self?.scrollBefore = y
                    self?.webView.evaluateJavaScript("window.ouro.reloadValue(\(Self.jsLiteralStatic(Self.docBeta)))", completionHandler: nil)
                    self?.waitForRender(expect: "BETANODE", stage: "beta")
                }
            } else {
                finish(body: body)
            }
        default:
            break
        }
    }

    private var scrollBefore: Double = 0

    private func waitForRender(expect: String, stage: String) {
        let js = #"""
        (function(){
          var expect = "__EXPECT__", stage = "__STAGE__";
          var tries = 0, max = 90;
          function svgText(){
            var nodes = document.querySelectorAll(".vditor-ir__preview svg, .language-mermaid svg, [data-type='mermaid'] svg, .vditor-reset .language-mermaid foreignObject");
            var t = "";
            nodes.forEach(function(n){ t += " " + (n.textContent || ""); });
            return t;
          }
          function svgPresent(){
            return !!document.querySelector(".vditor-ir__preview svg, .language-mermaid svg, [data-type='mermaid'] svg");
          }
          function poll(){
            var t = svgText();
            if ((!svgPresent() || t.indexOf(expect) === -1) && tries < max){ tries++; return void setTimeout(poll, 100); }
            var s = document.scrollingElement || document.documentElement;
            window.webkit.messageHandlers.ouro.postMessage({
              type: "rendered", stage: stage,
              hasSvg: svgPresent(),
              hasAlpha: t.indexOf("ALPHANODE") !== -1,
              hasBeta: t.indexOf("BETANODE") !== -1,
              scrollTop: s.scrollTop
            });
          }
          poll();
        })();
        """#
        .replacingOccurrences(of: "__EXPECT__", with: expect)
        .replacingOccurrences(of: "__STAGE__", with: stage)
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func finish(body: [String: Any]) {
        let hasSvg = body["hasSvg"] as? Bool ?? false
        let hasAlpha = body["hasAlpha"] as? Bool ?? true
        let hasBeta = body["hasBeta"] as? Bool ?? false
        let scrollAfter = body["scrollTop"] as? Double ?? (body["scrollTop"] as? Int).map(Double.init) ?? -1
        let renderedOK = hasSvg && hasBeta
        let noStaleOK = !hasAlpha
        // Scroll preserved within a tolerance (reflow can shift a few px).
        let scrollOK = abs(scrollAfter - scrollBefore) <= 8
        print("new diagram rendered: \(renderedOK ? "yes ✓" : "NO ✗") (svg=\(hasSvg) beta=\(hasBeta))")
        print("stale diagram cleared: \(noStaleOK ? "yes ✓" : "NO ✗ (old ALPHANODE label still present)")")
        print(String(format: "scroll preserved: %@ (before=%.0f after=%.0f)", scrollOK ? "yes ✓" : "NO ✗", scrollBefore, scrollAfter))
        exit(renderedOK && noStaleOK && scrollOK ? 0 : 1)
    }
}

private func jsLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value]),
       let json = String(data: data, encoding: .utf8) {
        return String(json.dropFirst().dropLast())
    }
    return "\"\""
}

extension ReloadRenderTester {
    static func jsLiteralStatic(_ value: String) -> String { jsLiteral(value) }
}
