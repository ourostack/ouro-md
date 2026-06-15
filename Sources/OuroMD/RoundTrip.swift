import AppKit
import WebKit

/// Headless `--roundtrip` mode: loads a markdown file into the real editor,
/// reads the value back out, and writes it to stdout (or `--out`). Lets us
/// verify the editor preserves the source on save — critical for the
/// agent↔human loop, where reformatting would create diff noise.
final class RoundTripper: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let input: String
    private let outURL: URL?
    private var webView: WKWebView!
    private var timeoutSeconds: TimeInterval {
        min(360, max(180, 60 + Double(input.utf8.count) / 20_000))
    }
    private var settleSeconds: TimeInterval {
        min(12, max(1.5, Double(input.utf8.count) / 500_000))
    }

    init(fileURL: URL, outURL: URL?) throws {
        self.input = try Self.readInput(fileURL)
        self.outURL = outURL
    }

    static func readInput(_ fileURL: URL) throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self

        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("roundtrip: index.html not found\n".utf8)); exit(1)
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
            FileHandle.standardError.write(Data("roundtrip: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "ready" else { return }
        webView.evaluateJavaScript("window.ouro.setValue(\(RoundTripper.js(input)))", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + settleSeconds) {
            self.webView.evaluateJavaScript("window.ouro.getValue()") { result, _ in
                let output = MarkdownTidy.roundTripProbeOutput((result as? String) ?? "", preserving: self.input)
                if let outURL = self.outURL {
                    try? output.write(to: outURL, atomically: true, encoding: .utf8)
                } else {
                    FileHandle.standardOutput.write(Data(output.utf8))
                }
                exit(0)
            }
        }
    }

    private static func js(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
