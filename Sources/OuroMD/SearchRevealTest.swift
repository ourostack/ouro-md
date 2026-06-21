import AppKit
import WebKit

/// Headless `--searchrevealtest`: verifies sidebar search-result reveal uses
/// the same whole-word/regex semantics as native search when it selects text in
/// the rendered WebKit editor.
final class SearchRevealTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let theme = ThemeStore.shared.defaultTheme
    private var wholeWordOK = false
    private var regexOK = false

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("searchrevealtest: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            FileHandle.standardError.write(Data("searchrevealtest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.markdown)))", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.runWholeWordProbe()
            }
        } else if type == "searchreveal" {
            let step = body["step"] as? String ?? ""
            let selection = body["selection"] as? String ?? ""
            let context = body["context"] as? String ?? ""
            let before = body["before"] as? String ?? ""
            let after = body["after"] as? String ?? ""
            let matches = body["matches"] as? String ?? ""
            if step == "wholeWord" {
                wholeWordOK = selection == "needle"
                    && before.range(of: #"^\w$"#, options: .regularExpression) == nil
                    && after.range(of: #"^\w$"#, options: .regularExpression) == nil
                print("whole-word reveal selection: \(selection) before[\(before)] after[\(after)] in \(context) \(wholeWordOK ? "✓" : "✗")")
                runRegexProbe()
            } else if step == "regex" {
                regexOK = selection == "222"
                print("regex reveal selection: \(selection) in \(context) matches[\(matches)] \(regexOK ? "✓" : "✗")")
                exit(wholeWordOK && regexOK ? 0 : 1)
            }
        }
    }

    private func runWholeWordProbe() {
        let script = """
        window.ouro.revealSearchMatch({
          query: "needle",
          matchedText: "needle",
          matchOrdinal: 0,
          caseSensitive: false,
          wholeWord: true,
          regexp: false
        });
        setTimeout(function () {
          var sel = window.getSelection();
          var range = sel && sel.rangeCount ? sel.getRangeAt(0) : null;
          var node = sel && sel.anchorNode;
          var el = node && (node.nodeType === 1 ? node : node.parentElement);
          var text = range && range.startContainer && range.startContainer.nodeType === 3 ? range.startContainer.nodeValue : "";
          var before = range && text ? text.charAt(Math.max(0, range.startOffset - 1)) : "";
          var after = range && text ? text.charAt(range.endOffset) : "";
          window.webkit.messageHandlers.ouro.postMessage({
            type: "searchreveal",
            step: "wholeWord",
            selection: String(sel),
            before: before,
            after: after,
            context: el && el.closest("[data-block]") ? el.closest("[data-block]").textContent : ""
          });
        }, 350);
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func runRegexProbe() {
        let script = """
        window.getSelection().removeAllRanges();
        window.ouro.revealSearchMatch({
          query: "\\\\d+",
          matchedText: "222",
          matchOrdinal: 1,
          caseSensitive: false,
          wholeWord: false,
          regexp: true
        });
        setTimeout(function () {
          var text = Array.prototype.slice.call(document.querySelectorAll("#editor .vditor-reset")).map(function (root) {
            return root.innerText || root.textContent || "";
          }).join("\\n");
          var sel = window.getSelection();
          var node = sel && sel.anchorNode;
          var el = node && (node.nodeType === 1 ? node : node.parentElement);
          window.webkit.messageHandlers.ouro.postMessage({
            type: "searchreveal",
            step: "regex",
            selection: String(sel),
            context: el && el.closest("[data-block]") ? el.closest("[data-block]").textContent : "",
            matches: (text.match(/\\d+/g) || []).join(",")
          });
        }, 350);
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static let markdown = """
    needlex
    needle
    111
    222
    """

    private func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
