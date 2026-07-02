import AppKit
import SwiftUI
import WebKit

/// Hosts the Vditor editor in a WKWebView and bridges it to `AppModel`.
struct EditorWebView: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Self.initialThemeBootstrapScript(for: model.theme),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.add(context.coordinator, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = EditorDropWebView(frame: .zero, configuration: configuration)
        webView.model = model
        Self.applyLayerBackground(model.theme.backgroundHex, to: webView)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.registerForDraggedTypes([.fileURL])

        context.coordinator.webView = webView
        model.bridge = context.coordinator

        if let indexURL = OuroResources.web("index", "html") {
            // Read access at root lets the editor display images a document
            // references by absolute or (resolved) relative file paths.
            webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        Self.applyLayerBackground(model.theme.backgroundHex, to: nsView)
    }

    static func initialThemeBootstrapScript(for theme: Theme) -> String {
        let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
        return """
        (function () {
          var theme = {
            uiMode: \(Coordinator.jsString(theme.uiMode)),
            codeTheme: \(Coordinator.jsString(codeTheme)),
            background: \(Coordinator.jsString(theme.backgroundHex)),
            css: \(Coordinator.jsString(theme.editorCSS))
          };
          window.__ouroInitialTheme = theme;
          function backgroundCSS(background) {
            return "html,body,#editor,.vditor,.vditor-content{background:" + background + " !important;background-color:" + background + " !important;}";
          }
          function setBackground(el) {
            if (!el || !el.style) { return; }
            el.style.setProperty("background", theme.background, "important");
            el.style.setProperty("background-color", theme.background, "important");
          }
          function ensureInitialBackgroundStyle() {
            var target = document.head || document.documentElement;
            var tag = document.getElementById("ouro-initial-background");
            if (!tag && target) {
              tag = document.createElement("style");
              tag.id = "ouro-initial-background";
              target.appendChild(tag);
            }
            if (tag) { tag.textContent = backgroundCSS(theme.background); }
          }
          setBackground(document.documentElement);
          ensureInitialBackgroundStyle();
          function applyInitialTheme() {
            var target = document.head || document.documentElement;
            var tag = document.getElementById("ouro-theme");
            if (!tag && target) {
              tag = document.createElement("style");
              tag.id = "ouro-theme";
              target.appendChild(tag);
            }
            if (tag) { tag.textContent = theme.css; }
            ensureInitialBackgroundStyle();
            setBackground(document.body);
            var editor = document.getElementById("editor");
            setBackground(editor);
          }
          applyInitialTheme();
          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", applyInitialTheme, { once: true });
          }
        })();
        """
    }

    private static func applyLayerBackground(_ hex: String, to webView: WKWebView) {
        guard let background = NSColor(hex: hex) else { return }
        webView.wantsLayer = true
        webView.layer?.backgroundColor = background.cgColor
    }

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
            case "count":
                if let words = body["words"] as? Int {
                    model.setCounts(words: words, chars: body["chars"] as? Int ?? 0)
                }
            case "outline":
                if let items = body["items"] as? [[String: Any]] {
                    let parsed = items.compactMap { dict -> OutlineItem? in
                        guard let index = dict["index"] as? Int,
                              let level = dict["level"] as? Int,
                              let text = dict["text"] as? String else { return nil }
                        return OutlineItem(index: index, level: level, text: text)
                    }
                    model.updateOutline(parsed)
                }
            case "activeHeading":
                if let index = body["index"] as? Int { model.setActiveHeading(index) }
            case "openURL":
                // ⌘-click on a link in the editable area: the bridge resolved the
                // anchor's href and asks us to open it. Same scheme allow-list as
                // the navigation delegate so the editor can't be coaxed into
                // opening file:// or other unexpected schemes.
                if let urlString = body["url"] as? String,
                   let url = URL(string: urlString),
                   let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }
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

        // Recover if the web content process is terminated (crash / jetsam):
        // restore content and reload rather than leaving a blank editor.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            model.editorCrashed()
            if let indexURL = OuroResources.web("index", "html") {
                webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            } else {
                webView.reload()
            }
        }

        // MARK: native -> JS (EditorBridge)

        func setMarkdown(_ markdown: String) {
            eval("window.ouro && window.ouro.setValue(\(Coordinator.jsString(markdown)))")
        }
        func reloadMarkdown(_ markdown: String) {
            eval("window.ouro && window.ouro.reloadValue(\(Coordinator.jsString(markdown)))")
        }

        func getMarkdown(_ completion: @escaping (String?) -> Void) {
            guard let webView else { completion(nil); return }
            webView.evaluateJavaScript("window.ouro ? window.ouro.getValue() : null") { result, _ in
                completion(result as? String)
            }
        }

        func getHTML(_ completion: @escaping (String?) -> Void) {
            guard let webView else { completion(nil); return }
            webView.evaluateJavaScript("window.ouro ? window.ouro.getHTML() : null") { result, _ in
                completion(result as? String)
            }
        }

        func applyTheme(uiMode: String, css: String, codeTheme: String, background: String) {
            if let webView {
                EditorWebView.applyLayerBackground(background, to: webView)
            }
            eval("window.ouro && window.ouro.setTheme(\(Coordinator.jsString(uiMode)),\(Coordinator.jsString(css)),\(Coordinator.jsString(codeTheme)),\(Coordinator.jsString(background)))")
        }

        func setMode(_ mode: String) {
            eval("window.ouro && window.ouro.setMode(\(Coordinator.jsString(mode)))")
        }

        func setOutline(_ on: Bool) {
            eval("window.ouro && window.ouro.setOutline(\(on ? "true" : "false"))")
        }

        func setFocusMode(_ on: Bool) {
            eval("window.ouro && window.ouro.setFocusMode(\(on ? "true" : "false"))")
        }

        func setTypewriter(_ on: Bool) {
            eval("window.ouro && window.ouro.setTypewriter(\(on ? "true" : "false"))")
        }

        func setAutoPair(_ on: Bool) {
            eval("window.ouro && window.ouro.setAutoPair(\(on ? "true" : "false"))")
        }

        func scrollToHeading(_ index: Int) {
            eval("window.ouro && window.ouro.scrollToHeading(\(index))")
        }

        func find(_ query: String, backward: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {
            let opts = "{backward:\(backward),caseSensitive:\(caseSensitive),wholeWord:\(wholeWord),regexp:\(regexp)}"
            eval("window.ouro && window.ouro.find(\(Coordinator.jsString(query)),\(opts))")
        }

        func revealSearchMatch(
            lineNumber: Int,
            sourceColumn: Int,
            sourceLength: Int,
            matchOrdinal: Int,
            matchedText: String,
            query: String,
            caseSensitive: Bool,
            wholeWord: Bool,
            regexp: Bool
        ) {
            let opts = """
            {lineNumber:\(lineNumber),sourceColumn:\(sourceColumn),sourceLength:\(sourceLength),matchOrdinal:\(matchOrdinal),matchedText:\(Coordinator.jsString(matchedText)),query:\(Coordinator.jsString(query)),caseSensitive:\(caseSensitive),wholeWord:\(wholeWord),regexp:\(regexp)}
            """
            eval("window.ouro && window.ouro.revealSearchMatch(\(opts))")
        }

        func replace(_ query: String, with replacement: String, all: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool, completion: @escaping (Int) -> Void) {
            let opts = "{caseSensitive:\(caseSensitive),wholeWord:\(wholeWord),regexp:\(regexp)}"
            let fn = all ? "replaceAll" : "replaceNext"
            let js = "window.ouro ? window.ouro.\(fn)(\(Coordinator.jsString(query)),\(Coordinator.jsString(replacement)),\(opts)) : 0"
            webView?.evaluateJavaScript(js) { result, _ in
                completion((result as? NSNumber)?.intValue ?? 0)
            }
        }

        func clearFind() {
            eval("window.ouro && window.ouro.clearFind()")
        }

        func execCommand(_ command: String) {
            eval("window.ouro && window.ouro.exec(\(Coordinator.jsString(command)))")
        }

        func insertText(_ text: String) {
            eval("window.ouro && window.ouro.insertText(\(Coordinator.jsString(text)))")
        }

        func copyAs(_ mode: String) {
            eval("window.ouro && window.ouro.copyAs(\(Coordinator.jsString(mode)))")
        }

        func setDocBase(_ directory: String?) {
            eval("window.ouro && window.ouro.setDocBase(\(Coordinator.jsString(directory ?? "")))")
        }

        func markSaved() { eval("window.ouro && window.ouro.markSaved()") }
        func undo() { eval("window.ouro && window.ouro.undo()") }
        func redo() { eval("window.ouro && window.ouro.redo()") }

        func focusEditor() {
            // Route keystrokes to the editor: the WKWebView must be the window's
            // first responder AND the contenteditable must hold the caret. Without
            // the first-responder step, a freshly opened window swallows typing
            // until the user clicks into the page.
            if let webView { webView.window?.makeFirstResponder(webView) }
            eval("window.ouro && window.ouro.focus()")
        }

        func printDocument() {
            guard let webView, let window = webView.window else { return }
            let operation = webView.printOperation(with: NSPrintInfo.shared)
            operation.view?.frame = webView.bounds
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }

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

final class EditorDropWebView: WKWebView {
    weak var model: AppModel?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.openableMarkdownURL(from: sender.draggingPasteboard) == nil ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = Self.openableMarkdownURL(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        model?.open(url: url)
        return true
    }

    static func openableMarkdownURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.first(where: FolderScanner.canOpen)
    }
}
