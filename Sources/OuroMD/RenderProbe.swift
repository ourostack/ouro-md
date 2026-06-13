import AppKit
import WebKit

/// Headless `--renderprobe`: loads the live editor with a document that exercises
/// every rich feature (mermaid, math, footnote, alert, table, task list, code)
/// and reports which ones actually rendered, so rendering gaps surface without a
/// GUI. A reusable regression harness for the rendering surface.
final class RenderProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
            FileHandle.standardError.write(Data("renderprobe: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
            FileHandle.standardError.write(Data("renderprobe: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            webView.evaluateJavaScript(Self.script, completionHandler: nil)
        } else if type == "renderprobe" {
            let features = ["heading", "bold", "inlineCode", "codeBlock", "table",
                            "taskList", "math", "footnote", "alert", "mermaid"]
            var allCore = true
            for key in features {
                let ok = (body[key] as? Bool) ?? false
                // mermaid + footnote are "nice to have"; the rest are core.
                let core = !["mermaid"].contains(key)
                if core && !ok { allCore = false }
                print("\(key.padding(toLength: 12, withPad: " ", startingAt: 0)): \(ok ? "rendered ✓" : "MISSING ✗")")
            }
            exit(allCore ? 0 : 1)
        }
    }

    private static let script = #"""
    (function () {
      var doc = [
        "# Heading",
        "",
        "Body **bold** and `code` with a footnote[^1].",
        "",
        "[^1]: Footnote text.",
        "",
        "> [!NOTE]",
        "> An alert.",
        "",
        "- [x] done",
        "- [ ] todo",
        "",
        "| A | B |",
        "| - | - |",
        "| 1 | 2 |",
        "",
        "$$E = mc^2$$",
        "",
        "```mermaid",
        "graph TD; A-->B;",
        "```",
        ""
      ].join("\n");
      window.ouro.setValue(doc);
      setTimeout(function () {
        var root = document.querySelector("#editor");
        function has(sel) { return !!root.querySelector(sel); }
        var result = {
          heading: has("h1"),
          bold: has("strong"),
          inlineCode: has("code"),
          codeBlock: has("pre") || has(".vditor-ir__marker--pre") || has("code.language-mermaid"),
          table: has("table"),
          taskList: has('input[type="checkbox"]'),
          math: has(".katex") || has(".language-math svg") || has(".vditor-math"),
          footnote: has("sup") || has('[data-type="footnotes-ref"]') || has(".vditor-footnotes__ref"),
          alert: has(".ouro-alert"),
          mermaid: has(".language-mermaid svg") || has('[data-type="mermaid"] svg') || has(".vditor-ir__preview svg")
        };
        window.webkit.messageHandlers.ouro.postMessage(Object.assign({ type: "renderprobe" }, result));
      }, 2500);
    })();
    """#
}
