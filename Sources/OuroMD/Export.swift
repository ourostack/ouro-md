import AppKit
import WebKit

/// Renders an HTML document to PDF using an offscreen web view.
/// Retains itself for the lifetime of the asynchronous render.
final class PDFExporter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var destination: URL?
    private var completion: ((Bool) -> Void)?
    private static var inFlight: Set<PDFExporter> = []

    func export(html: String, to url: URL, completion: @escaping (Bool) -> Void) {
        PDFExporter.inFlight.insert(self)
        destination = url
        self.completion = completion

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 816, height: 1056),
                                configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give the layout engine a moment to settle (fonts, KaTeX, code blocks).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                var ok = false
                if case .success(let data) = result, let destination = self.destination {
                    ok = (try? data.write(to: destination)) != nil
                }
                self.finish(ok)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    private func finish(_ ok: Bool) {
        completion?(ok)
        completion = nil
        webView = nil
        PDFExporter.inFlight.remove(self)
    }
}
