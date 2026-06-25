import AppKit
import WebKit

/// Headless `--codewraptest`: loads the live editor with a deliberately long
/// fenced-code line and fails if code-block overflow escapes the block into the
/// whole document. The acceptable behavior is table-like: local horizontal
/// scroll on the code block, stable page width everywhere else.
final class CodeWrapTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let viewportWidth: CGFloat
    private let viewportHeight: CGFloat
    private let theme = ThemeStore.shared.defaultTheme

    init(viewportWidth: CGFloat = 480, viewportHeight: CGFloat = 640) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("codewraptest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHost(webView, size: frame.size)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
            FileHandle.standardError.write(Data("codewraptest: timed out\n".utf8)); exit(1)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.webView.evaluateJavaScript(Self.measureScript, completionHandler: nil)
            }
        } else if type == "codewrap" {
            let codeBlockCount = (body["codeBlockCount"] as? Int) ?? 0
            let pageOverflow = (body["pageOverflow"] as? Double) ?? .infinity
            let clippedCount = (body["clippedCount"] as? Int) ?? .max
            let scrollableCount = (body["scrollableCount"] as? Int) ?? 0
            let initialScrolledCount = (body["initialScrolledCount"] as? Int) ?? .max
            let maxOverflow = (body["maxOverflow"] as? Double) ?? 0
            let tolerance = 2.0
            let pageOK = pageOverflow <= tolerance
            let codeOK = codeBlockCount >= 1
            let clippedOK = clippedCount == 0
            let scrollOK = scrollableCount >= 1 && maxOverflow > 40
            let initialScrollOK = initialScrolledCount == 0
            print("code blocks present: \(codeBlockCount) \(codeOK ? "✓" : "✗")")
            print(String(format: "page horizontal overflow: %.1fpx %@", pageOverflow, pageOK ? "✓" : "✗ (code escaped its own scroll)"))
            print("code blocks clipped by viewport: \(clippedCount) \(clippedOK ? "✓" : "✗")")
            print(String(format: "code blocks with own horizontal scroll: %d %@ (max %.1fpx)", scrollableCount, scrollOK ? "✓" : "✗", maxOverflow))
            print("code blocks initially scrolled sideways: \(initialScrolledCount) \(initialScrollOK ? "✓" : "✗")")
            exit(codeOK && pageOK && clippedOK && scrollOK && initialScrollOK ? 0 : 1)
        }
    }

    private static let markdown = """
    # Code Wrap Dogfood

    Surrounding prose must stay inside the document column.

    ```swift
    let extremelyLongIdentifierThatShouldNotPushTheWholeDocumentSideways = "Sources/OuroMD/DocumentWindowController.swift::Tests/OuroMDTests/NativeAppSurfaceCodeBlockOverflowRegressionTests.swift::abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789"
    ```

    More prose after the code block must remain readable without document-level horizontal scroll.
    """

    private static let measureScript = #"""
    (function () {
      var de = document.documentElement;
      var viewportWidth = de.clientWidth;
      var pageOverflow = Math.max(de.scrollWidth, document.body.scrollWidth) - viewportWidth;
      var candidates = Array.prototype.slice.call(document.querySelectorAll("#editor pre.vditor-ir__preview"));
      if (!candidates.length) {
        candidates = Array.prototype.slice.call(document.querySelectorAll("#editor pre"));
      }
      var blocks = candidates.filter(function (block) {
        return (block.textContent || "").indexOf("extremelyLongIdentifierThatShouldNotPush") !== -1;
      });
      var clippedCount = 0;
      var scrollableCount = 0;
      var initialScrolledCount = 0;
      var maxOverflow = 0;
      blocks.forEach(function (block) {
        var rect = block.getBoundingClientRect();
        var overflow = block.scrollWidth - block.clientWidth;
        if (rect.left < -2 || rect.right > viewportWidth + 2) { clippedCount += 1; }
        if (overflow > 2) { scrollableCount += 1; }
        if ((block.scrollLeft || 0) > 1) { initialScrolledCount += 1; }
        if (overflow > maxOverflow) { maxOverflow = overflow; }
      });
      window.webkit.messageHandlers.ouro.postMessage({
        type: "codewrap",
        codeBlockCount: blocks.length,
        pageOverflow: pageOverflow,
        clippedCount: clippedCount,
        scrollableCount: scrollableCount,
        initialScrolledCount: initialScrolledCount,
        maxOverflow: maxOverflow
      });
    })();
    """#

    private func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
