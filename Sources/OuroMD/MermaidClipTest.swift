import AppKit
import WebKit

/// Headless `--mermaidcliptest`: loads the live editor, applies the real theme
/// (via `window.ouro.setTheme`, the same path the app uses), renders a Mermaid
/// flowchart with multi-line node labels, and fails if any label's text
/// overflows its node box.
///
/// Guards the regression where the theme's prose block-rhythm rule
/// (`.vditor-reset p { margin: 0.8em 0 !important }`) cascades into Mermaid's
/// `<foreignObject>` `<p>` labels. Mermaid sizes each label box with
/// `getBoundingClientRect()`, which excludes margins — and the `!important`
/// defeats Mermaid's own `margin:0` reset — so the label grows past its box and
/// the bottom line clips. The fix re-zeros that margin inside `.language-mermaid`
/// only; this harness proves the labels fit. Theme CSS is applied exactly as the
/// app does, so it exercises the shipped stylesheet, not Vditor's defaults.
final class MermaidClipTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    // Wide enough that the LR flowchart lays its labels out as authored.
    private static let viewportWidth: CGFloat = 1000
    private let theme = ThemeStore.shared.defaultTheme

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: Self.viewportWidth, height: 800)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("mermaidcliptest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHost(webView, size: frame.size)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
            FileHandle.standardError.write(Data("mermaidcliptest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.mermaidMarkdown)))", completionHandler: nil)
            // Mermaid loads its bundle and renders asynchronously; the measure
            // script polls for the labels before reading geometry.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.webView.evaluateJavaScript(Self.measureScript, completionHandler: nil)
            }
        } else if type == "mermaidclip" {
            let rendered = (body["rendered"] as? Bool) ?? false
            let labelCount = (body["labelCount"] as? Int) ?? 0
            let maxOverflow = (body["maxOverflow"] as? Double) ?? .infinity
            let worst = (body["worstLabel"] as? String) ?? ""
            // A couple of px for sub-pixel rounding.
            let tolerance = 2.0
            let overflowOK = maxOverflow <= tolerance
            print("mermaid rendered: \(rendered ? "yes ✓" : "NO ✗") (\(labelCount) labels)")
            let overflowMark = overflowOK ? "✓" : "✗ (label text clipped by node box — worst: \"\(worst)\")"
            print(String(format: "max label overflow: %.1fpx ", maxOverflow) + overflowMark)
            exit(rendered && overflowOK ? 0 : 1)
        }
    }

    // The meeting-to-tasks flowchart from the bug report: every node carries a
    // multi-line label, the case that clipped before the fix.
    private static let mermaidMarkdown = [
        "```mermaid",
        "flowchart LR",
        "  A[\"Teams channel<br/>meeting ends → recap +<br/>transcript\"] --> B[\"Meeting-end PA flow<br/>one canonical trigger per<br/>channel\"]",
        "  B --> C[\"GCB → TCA\"]",
        "  C --> D[\"AugLoop<br/>GCB Orchestrator V2\"]",
        "  D --> E[\"TaskManagementV2<br/>extract action items →<br/>write tasks\"]",
        "  E --> F[\"Planner board<br/>via Graph\"]",
        "```",
        ""
    ].joined(separator: "\n")

    private static let measureScript = #"""
    (function () {
      var tries = 0, maxTries = 80; // ~8s at 100ms intervals
      function nodeLabels() {
        var fos = document.querySelectorAll(".language-mermaid foreignObject");
        return Array.prototype.filter.call(fos, function (fo) {
          var inner = fo.firstElementChild;
          return inner && inner.querySelector("p");
        });
      }
      function measure() {
        var rows = nodeLabels().map(function (fo) {
          var foH = (fo.height && fo.height.baseVal) ? fo.height.baseVal.value : 0;
          var inner = fo.firstElementChild;
          return {
            foHeight: foH,
            overflow: inner.scrollHeight - foH,
            label: (inner.textContent || "").replace(/\s+/g, " ").slice(0, 50)
          };
        });
        var maxOverflow = rows.reduce(function (m, r) { return Math.max(m, r.overflow); }, 0);
        var worst = rows.slice().sort(function (a, b) { return b.overflow - a.overflow; })[0];
        window.webkit.messageHandlers.ouro.postMessage({
          type: "mermaidclip",
          rendered: rows.length > 0,
          labelCount: rows.length,
          maxOverflow: maxOverflow,
          worstLabel: worst ? worst.label : ""
        });
      }
      (function poll() {
        if (nodeLabels().length === 0 && tries < maxTries) { tries++; return void setTimeout(poll, 100); }
        measure();
      })();
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
