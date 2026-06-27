import AppKit
import WebKit

/// Headless `--wrapgluetest`: verifies the no-orphan glue pass. Loads a doc with
/// a leading enumerator in a table cell and inline code hugged by parentheses,
/// runs the post-render decoration, and asserts (a) each run is wrapped in an
/// `.ouro-nowrap` span and (b) the glue does not change the Markdown round-trip
/// (the span is a render-only decoration).
final class WrapGlueTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("wrapgluetest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHostActive(webView, size: NSSize(width: 800, height: 600))
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
            FileHandle.standardError.write(Data("wrapgluetest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            webView.evaluateJavaScript(Self.script, completionHandler: nil)
        } else if type == "wrapgluetest" {
            let enumGlued = body["enumGlued"] as? String ?? "?"
            let bracketGlued = body["bracketGlued"] as? String ?? "?"
            let before = body["before"] as? String ?? "?"
            let after = body["after"] as? String ?? "?"
            let checks: [(String, String, Bool)] = [
                ("leading enumerator wrapped in .ouro-nowrap", enumGlued, enumGlued.contains("3. Instructions")),
                ("bracketed inline code wrapped in .ouro-nowrap", bracketGlued, bracketGlued.contains("(") && bracketGlued.contains(")") && bracketGlued.lowercased().contains("code")),
                ("glue does not change the Markdown round-trip", "before==after: \(before == after)", before == after)
            ]
            var allOK = true
            for (label, value, ok) in checks {
                if !ok { allOK = false }
                print("\(label): \(value.replacingOccurrences(of: "\n", with: "\\n"))   \(ok ? "OK ✓" : "FAIL ✗")")
            }
            exit(allOK ? 0 : 1)
        }
    }

    private static let script = """
    (function () {
      function nowrapContaining(predicate) {
        var spans = document.querySelectorAll('#editor .ouro-nowrap');
        for (var i = 0; i < spans.length; i++) { if (predicate(spans[i])) { return spans[i]; } }
        return null;
      }
      setTimeout(function () {
        // A leading enumerator only stays literal text (not an ordered-list
        // marker) inside a table cell, which is exactly the reported case.
        window.ouro.setValue("| Step |\\n| --- |\\n| 3. Instructions |\\n\\ntraced (`abc123`) here");
        setTimeout(function () {
          var before = window.ouro.getValue();
          window.ouro.refreshDecorations();
          var after = window.ouro.getValue();
          var enumSpan = nowrapContaining(function (s) { return (s.textContent || "").indexOf("3. Instructions") !== -1; });
          var bracketSpan = nowrapContaining(function (s) { return s.querySelector("code") && (s.textContent || "").indexOf("(") !== -1; });
          window.webkit.messageHandlers.ouro.postMessage({
            type: "wrapgluetest",
            enumGlued: enumSpan ? (enumSpan.textContent || "") : "(no enumerator nowrap span)",
            bracketGlued: bracketSpan ? ("code in: " + (bracketSpan.textContent || "")) : "(no bracket nowrap span)",
            before: before,
            after: after
          });
        }, 700);
      }, 500);
    })();
    """
}
