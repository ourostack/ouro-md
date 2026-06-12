import SwiftUI
import WebKit

/// Hosts the Vditor editor in a WKWebView and bridges it to `AppModel`.
struct EditorWebView: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.webView = webView
        model.bridge = context.coordinator

        if let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            let webDirectory = indexURL.deletingLastPathComponent()
            webView.loadFileURL(indexURL, allowingReadAccessTo: webDirectory)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, EditorBridge {
        let model: AppModel
        weak var webView: WKWebView?

        init(model: AppModel) { self.model = model }

        // MARK: JS -> native

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                model.editorDidBecomeReady()
            case "dirty":
                if let dirty = body["dirty"] as? Bool { model.setDirty(dirty) }
            default:
                break
            }
        }

        // Open external links in the default browser instead of navigating in-app.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // MARK: native -> JS (EditorBridge)

        func setMarkdown(_ markdown: String) {
            eval("window.ouro && window.ouro.setValue(\(Coordinator.jsString(markdown)))")
        }

        func getMarkdown(_ completion: @escaping (String) -> Void) {
            webView?.evaluateJavaScript("window.ouro ? window.ouro.getValue() : ''") { result, _ in
                completion(result as? String ?? "")
            }
        }

        func getHTML(_ completion: @escaping (String) -> Void) {
            webView?.evaluateJavaScript("window.ouro ? window.ouro.getHTML() : ''") { result, _ in
                completion(result as? String ?? "")
            }
        }

        func applyTheme(uiMode: String, css: String) {
            eval("window.ouro && window.ouro.setTheme(\(Coordinator.jsString(uiMode)),\(Coordinator.jsString(css)))")
        }

        func setMode(_ mode: String) {
            eval("window.ouro && window.ouro.setMode(\(Coordinator.jsString(mode)))")
        }

        func setOutline(_ on: Bool) {
            eval("window.ouro && window.ouro.setOutline(\(on ? "true" : "false"))")
        }

        func execCommand(_ command: String) {
            eval("window.ouro && window.ouro.exec(\(Coordinator.jsString(command)))")
        }

        func markSaved() { eval("window.ouro && window.ouro.markSaved()") }

        func focusEditor() { eval("window.ouro && window.ouro.focus()") }

        func setZoom(_ factor: Double) { webView?.magnification = CGFloat(factor) }

        private func eval(_ js: String) {
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        /// Encodes a Swift string as a safe JavaScript string literal.
        static func jsString(_ value: String) -> String {
            if let data = try? JSONSerialization.data(withJSONObject: [value]),
               let json = String(data: data, encoding: .utf8) {
                return String(json.dropFirst().dropLast())
            }
            return "\"\""
        }
    }
}
