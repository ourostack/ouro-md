import AppKit
import WebKit

/// Headless `--darkdiagramtest`: proves a Mermaid diagram re-themes when the app
/// switches between a light and a dark editor theme at runtime. Mermaid bakes
/// light/dark colors into its SVG at render time and caches the block
/// (`data-processed`); `Vditor.setTheme` does NOT re-render it. Without the
/// bridge fix, a light↔dark switch strands a light diagram (white node boxes) in
/// a dark page. This loads a flowchart under the light theme, records a node's
/// fill luminance, switches to the dark theme via `window.ouro.setTheme` (exactly
/// as the app does), and fails unless the diagram actually re-rendered darker.
final class DarkDiagramTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let light = ThemeStore.shared.theme(id: "quartz")
    private let dark = ThemeStore.shared.theme(id: "graphite")
    private var lumLight: Double = -1

    private static let doc = [
        "# Dark diagram check",
        "",
        "```mermaid",
        "flowchart LR",
        "  A[\"Source node\"] --> B[\"Sink node\"]",
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
            FileHandle.standardError.write(Data("darkdiagramtest: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            FileHandle.standardError.write(Data("darkdiagramtest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    private func applyTheme(_ t: Theme) {
        let code = t.uiMode == "dark" ? "github-dark" : "github"
        webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(t.uiMode)),\(jsLiteral(t.editorCSS)),\(jsLiteral(code)),\(jsLiteral(t.backgroundHex)))", completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            applyTheme(light)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.doc)))", completionHandler: nil)
            measure(stage: "light")
        case "lum":
            let stage = body["stage"] as? String ?? ""
            let lum = body["lum"] as? Double ?? (body["lum"] as? Int).map(Double.init) ?? -1
            let fill = body["fill"] as? String ?? "?"
            let found = body["found"] as? Bool ?? false
            print("[\(stage)] nodeFillLuminance=\(String(format: "%.0f", lum)) fill=\(fill) found=\(found)")
            if stage == "light" {
                lumLight = lum
                applyTheme(dark)
                measure(stage: "dark")
            } else {
                let lumDark = lum
                // The diagram must have re-rendered darker: a clear luminance drop,
                // and the dark render's node fill must actually read as dark.
                let droppedEnough = (lumLight - lumDark) >= 40
                let darkEnough = lumDark < 140
                let ok = found && droppedEnough && darkEnough
                print(String(format: "diagram re-themed on light→dark switch: %@ (light=%.0f dark=%.0f)",
                             ok ? "yes ✓" : "NO ✗ (diagram kept its light colors)", lumLight, lumDark))
                exit(ok ? 0 : 1)
            }
        default:
            break
        }
    }

    private func measure(stage: String) {
        let js = #"""
        (function(){
          var stage = "__STAGE__";
          var tries = 0, max = 90;
          function nodeShape(){
            return document.querySelector(".vditor-ir__preview svg g.node rect, .language-mermaid svg g.node rect, [data-type='mermaid'] svg g.node rect, .vditor-reset svg g.node rect")
                || document.querySelector(".vditor-reset svg .node rect, .vditor-reset svg rect.basic, .vditor-reset svg .nodes rect");
          }
          function lum(rgb){
            var m = (rgb || "").match(/(\d+(?:\.\d+)?)/g);
            if (!m || m.length < 3) return -1;
            return 0.299*parseFloat(m[0]) + 0.587*parseFloat(m[1]) + 0.114*parseFloat(m[2]);
          }
          function poll(){
            var rect = nodeShape();
            if (!rect && tries < max){ tries++; return void setTimeout(poll, 100); }
            var fill = rect ? getComputedStyle(rect).fill : "";
            window.webkit.messageHandlers.ouro.postMessage({
              type: "lum", stage: stage, found: !!rect, fill: fill, lum: lum(fill)
            });
          }
          poll();
        })();
        """#
        .replacingOccurrences(of: "__STAGE__", with: stage)
        // Give the re-render a beat to settle before measuring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
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
