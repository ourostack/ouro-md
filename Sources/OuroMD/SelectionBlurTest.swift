import AppKit
import WebKit

/// Headless `--selectionblurtest`: guards the wiring that mutes the text
/// selection when the editor isn't the active focus. The visual greying itself
/// (driven by CSS `::selection:window-inactive` + `body.ouro-editor-blurred
/// ::selection`) is a native compositing behavior that can't be read headlessly,
/// but the JS that drives it is testable: focus leaving the editor for the
/// sidebar/chrome must add `body.ouro-editor-blurred`, focus returning must
/// remove it, focus moving *within* the editor must NOT toggle it (no flicker),
/// and loading a new file must drop the prior selection so its highlight doesn't
/// strand on fresh content.
final class SelectionBlurTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let theme = ThemeStore.shared.defaultTheme

    private static let doc = [
        "# Selection blur check",
        "",
        "A selectable paragraph of text for the probe to highlight.",
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
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("selectionblurtest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHostActive(webView, size: frame.size)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
            FileHandle.standardError.write(Data("selectionblurtest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.doc)))", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.webView.evaluateJavaScript(Self.script, completionHandler: nil)
            }
        } else if type == "selectionblur" {
            let selected = (body["selected"] as? Bool) ?? false
            let blurredAdded = (body["blurredAdded"] as? Bool) ?? false
            let blurredRemoved = (body["blurredRemoved"] as? Bool) ?? false
            let stayedInside = (body["stayedInside"] as? Bool) ?? false
            let clearedOnLoad = (body["clearedOnLoad"] as? Bool) ?? false
            func mark(_ ok: Bool) -> String { ok ? "✓" : "✗" }
            print("selection made:                 \(mark(selected))")
            print("blur to chrome mutes:           \(mark(blurredAdded))")
            print("focus return un-mutes:          \(mark(blurredRemoved))")
            print("focus within editor no flicker: \(mark(stayedInside))")
            print("file switch clears selection:   \(mark(clearedOnLoad))")
            let ok = selected && blurredAdded && blurredRemoved && stayedInside && clearedOnLoad
            exit(ok ? 0 : 1)
        }
    }

    private static let script = #"""
    (function () {
      var el = document.getElementById("editor");
      var p = el.querySelector("p") || el;
      var sel = window.getSelection();
      sel.removeAllRanges();
      var r = document.createRange(); r.selectNodeContents(p); sel.addRange(r);
      var selected = sel.toString().length > 0;

      // Focus leaves the editor for the chrome (relatedTarget outside #editor).
      el.dispatchEvent(new FocusEvent("focusout", { relatedTarget: document.body, bubbles: true }));
      var blurredAdded = document.body.classList.contains("ouro-editor-blurred");

      // Focus returns to the editor.
      el.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
      var blurredRemoved = !document.body.classList.contains("ouro-editor-blurred");

      // Focus moves *within* the editor (relatedTarget inside) — must not mute.
      el.dispatchEvent(new FocusEvent("focusout", { relatedTarget: (el.querySelector("p") || el), bubbles: true }));
      var stayedInside = !document.body.classList.contains("ouro-editor-blurred");
      document.body.classList.remove("ouro-editor-blurred");

      // Re-select, then load a new file — selection must be dropped.
      sel.removeAllRanges();
      var r2 = document.createRange(); r2.selectNodeContents(p); sel.addRange(r2);
      window.ouro.setValue("# New file\n\nDifferent content.\n");
      var clearedOnLoad = window.getSelection().toString().length === 0;

      window.webkit.messageHandlers.ouro.postMessage({
        type: "selectionblur",
        selected: selected, blurredAdded: blurredAdded, blurredRemoved: blurredRemoved,
        stayedInside: stayedInside, clearedOnLoad: clearedOnLoad
      });
    })();
    """#
}

private func jsLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value]),
       let json = String(data: data, encoding: .utf8) {
        return String(json.dropFirst().dropLast())
    }
    return "\"\""
}
