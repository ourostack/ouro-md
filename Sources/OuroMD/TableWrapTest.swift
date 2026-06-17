import AppKit
import WebKit

/// Headless `--tablewraptest`: loads the live editor in a deliberately narrow
/// window, applies the real theme, renders a table with long cell content, and
/// fails if the table (or the page) overflows horizontally. Guards the "wide
/// tables wrap to the editor width instead of forcing a horizontal scrollbar"
/// behaviour. The theme stylesheet (where the table rules live) is applied the
/// same way the app does — via `window.ouro.setTheme` — so this exercises the
/// shipped CSS, not Vditor's defaults.
final class TableWrapTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    // Narrow on purpose: a non-wrapping wide table cannot fit here, so a pass
    // proves the cells actually wrap.
    private static let viewportWidth: CGFloat = 480
    private let theme = ThemeStore.shared.defaultTheme

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: Self.viewportWidth, height: 640)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("tablewraptest: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
            FileHandle.standardError.write(Data("tablewraptest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.wideTableMarkdown)))", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.webView.evaluateJavaScript(Self.measureScript, completionHandler: nil)
            }
        } else if type == "tablewrap" {
            let hasTable = (body["hasTable"] as? Bool) ?? false
            let pageOverflow = (body["pageOverflow"] as? Double) ?? .infinity
            let tableOverflow = (body["tableOverflow"] as? Double) ?? .infinity
            // Allow a couple of px for sub-pixel rounding.
            let tolerance = 2.0
            let pageOK = pageOverflow <= tolerance
            let tableOK = tableOverflow <= tolerance
            print("table present: \(hasTable ? "yes ✓" : "NO ✗")")
            print(String(format: "page horizontal overflow: %.1fpx %@", pageOverflow, pageOK ? "✓" : "✗ (table did not wrap)"))
            print(String(format: "table horizontal overflow: %.1fpx %@", tableOverflow, tableOK ? "✓" : "✗ (cells did not wrap)"))
            exit(hasTable && pageOK && tableOK ? 0 : 1)
        }
    }

    private static let wideTableMarkdown = [
        "| Commitment | How I carry it |",
        "| - | - |",
        "| Done means shipped | A real person used my output for real work, not that I produced a draft that looks plausible at a glance but falls apart on contact with reality. |",
        "| Defined in markdown | I am defined in markdown, not code, which is exactly why my humans can reshape me by editing this single file at any time without a deploy or a release. |",
        "| Success is retention | My success is the team running real work through me and staying, not how often I happen to get pinged in a given week. |",
        "| Long unbreakable token | https://example.com/a/very/long/path/segment/that/keeps/going/withoutanyspacesorbreakpointsatallxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx |",
        ""
    ].joined(separator: "\n")

    private static let measureScript = #"""
    (function () {
      var de = document.documentElement;
      var pageOverflow = de.scrollWidth - de.clientWidth;
      var table = document.querySelector("#editor table");
      var tableOverflow = table ? (table.scrollWidth - table.clientWidth) : -1;
      window.webkit.messageHandlers.ouro.postMessage({
        type: "tablewrap",
        hasTable: !!table,
        pageOverflow: pageOverflow,
        tableOverflow: tableOverflow
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
