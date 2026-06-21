import AppKit
import WebKit

/// Headless `--firstlaunchtest`: renders the built-in welcome document through
/// the real editor and checks both DOM content and snapshot pixels, guarding
/// against blank first-launch windows.
final class FirstLaunchTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private var lastDOMSnapshot = "none"
    private let size = NSSize(width: 900, height: 700)
    private let theme = ThemeStore.shared.defaultTheme

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let indexURL = OuroResources.web("index", "html") else {
            fail("index.html not found")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.fail("timed out") }
        app.run()
        exit(0)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "ready" else { return }
        let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
        webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
        webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Welcome.markdown)))", completionHandler: nil)
        pollDOM(deadline: Date().addingTimeInterval(8))
    }

    private func pollDOM(deadline: Date) {
        let script = """
        (function () {
          var root = document.querySelector(".vditor-reset") || document.getElementById("editor") || document.body;
          var text = root ? (root.textContent || root.innerText || "") : "";
          var heading = document.querySelector(".vditor-reset h1");
          var value = window.ouro && window.ouro.getValue ? window.ouro.getValue() : "";
          var html = window.ouro && window.ouro.getHTML ? window.ouro.getHTML() : "";
          return {
            valueHasWelcome: value.indexOf("Welcome to Ouro MD") !== -1,
            hasWelcome: text.indexOf("Welcome to Ouro MD") !== -1,
            htmlHasWelcome: html.indexOf("Welcome to Ouro MD") !== -1 && html.indexOf("<h1") !== -1,
            heading: heading ? heading.textContent : "",
            textLength: text.length,
            htmlLength: html.length,
            bodyLength: text.length,
            bodyHeight: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
            rootHeight: root ? root.getBoundingClientRect().height : 0
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            if let values = result as? [String: Any],
               values["valueHasWelcome"] as? Bool == true,
               (values["hasWelcome"] as? Bool == true || values["htmlHasWelcome"] as? Bool == true),
               (((values["heading"] as? String) ?? "").contains("Welcome to Ouro MD") || values["htmlHasWelcome"] as? Bool == true),
               (self.doubleValue(values["bodyLength"]) > 200 || self.doubleValue(values["htmlLength"]) > 800),
               self.doubleValue(values["bodyHeight"]) > 300 {
                self.captureSnapshot()
                return
            }
            if let values = result as? [String: Any] {
                self.lastDOMSnapshot = values
                    .map { "\($0.key)=\($0.value)" }
                    .sorted()
                    .joined(separator: " ")
            }
            guard Date() < deadline else {
                self.fail("welcome DOM was blank or incomplete (\(self.lastDOMSnapshot))")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.pollDOM(deadline: deadline)
            }
        }
    }

    private func captureSnapshot() {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(origin: .zero, size: size)
        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self else { return }
            if let error { self.fail("snapshot failed: \(error.localizedDescription)") }
            guard let image,
                  let data = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: data) else {
                self.fail("snapshot returned no pixels")
            }
            let nonBlank = self.nonBlankSampleCount(in: rep)
            print("first launch welcome pixels: \(nonBlank) nonblank samples")
            if nonBlank < 40 { self.fail("welcome snapshot was visually blank") }
            exit(0)
        }
    }

    private func nonBlankSampleCount(in rep: NSBitmapImageRep) -> Int {
        var count = 0
        let step = 12
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                let alpha = color.alphaComponent
                if alpha > 0.05 && (red < 0.94 || green < 0.94 || blue < 0.94) {
                    count += 1
                }
            }
        }
        return count
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("firstlaunchtest: \(message)\n".utf8))
        exit(1)
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }

    private func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
