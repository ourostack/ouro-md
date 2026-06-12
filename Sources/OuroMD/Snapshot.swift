import AppKit
import CoreGraphics
import WebKit

/// Headless `--shoot` mode: renders the editor in an off-screen web view (no
/// window) and writes a PNG of the rendered Markdown via `createPDF` +
/// CoreGraphics rasterization. Captures only the app's own content — never the
/// screen — so it is safe and Space-independent.
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

        guard let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
            fail("index.html not found in bundle")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.fail("timed out waiting for editor") }
        app.run()
        exit(0)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "ready" else { return }
        let codeTheme = theme.uiMode == "dark" ? "github-dark" : "atom-one-light"
        webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)))", completionHandler: nil)
        webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(markdown)))", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.capture() }
    }

    private func capture() {
        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = NSRect(origin: .zero, size: size)
        webView.createPDF(configuration: pdfConfig) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                self.rasterize(pdfData: data)
            case .failure(let error):
                self.fail("createPDF failed: \(error.localizedDescription)")
            }
        }
    }

    private func rasterize(pdfData: Data) {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            fail("could not read rendered PDF")
        }
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 2
        let width = Int(box.width * scale)
        let height = Int(box.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fail("could not create bitmap context")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        guard let cgImage = context.makeImage() else { fail("could not rasterize PDF") }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode PNG") }
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
