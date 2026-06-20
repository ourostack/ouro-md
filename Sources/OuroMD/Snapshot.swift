import AppKit
import WebKit

/// Headless `--shoot` mode: renders the editor in an off-screen web view (no
/// window) and writes a PNG of the rendered Markdown from WebKit's viewport
/// snapshot API. Captures only the app's own content — never the screen — so it
/// is safe and Space-independent.
final class Snapshotter: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let fileURL: URL
    private let outURL: URL
    private let theme: Theme
    private let size: NSSize
    private var webView: WKWebView!
    private var markdown = ""

    init(fileURL: URL, outURL: URL, themeID: String, size: NSSize) {
        self.fileURL = fileURL
        self.outURL = outURL
        self.theme = ThemeStore.shared.theme(id: themeID)
        self.size = size
    }

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        markdown = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "# (could not read file)"

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        webView.navigationDelegate = self

        guard let indexURL = OuroResources.web("index", "html") else {
            fail("index.html not found in bundle")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.fail("timed out waiting for editor") }
        app.run()
        exit(0)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "ready" else { return }
        let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
        webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)))", completionHandler: nil)
        webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(markdown)))", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.capture() }
    }

    private func capture() {
        webView.evaluateJavaScript("document.querySelectorAll('.vditor-reset table').forEach(function(t){t.scrollLeft=0})") { [weak self] _, _ in
            guard let self else { return }
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(origin: .zero, size: self.size)
            self.webView.takeSnapshot(with: config) { [weak self] image, error in
                guard let self else { return }
                if let error {
                    self.fail("snapshot failed: \(error.localizedDescription)")
                }
                guard let image else { self.fail("snapshot returned no image") }
                self.write(image: image)
            }
        }
    }

    private func write(image: NSImage) {
        guard let data = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: data),
              let png = rep.representation(using: .png, properties: [:]) else {
            fail("could not encode PNG")
        }
        do {
            try png.write(to: outURL)
            print(outURL.path)
            exit(0)
        } catch {
            fail("write failed: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("ouro-md --shoot: \(message)\n".utf8))
        exit(1)
    }
}

private func jsLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value]),
       let json = String(data: data, encoding: .utf8) {
        return String(json.dropFirst().dropLast())
    }
    return "\"\""
}
