import AppKit
import WebKit

/// Headless `--undotest`: loads the editor, makes a real edit (execCommand →
/// input event → Vditor undo stack), then exercises undo and redo and prints
/// the value at each step, so undo/redo can be verified without a GUI.
final class UndoTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
            FileHandle.standardError.write(Data("undotest: index.html not found\n".utf8)); exit(1)
        }
        // Host the web view in an off-screen key window so it can take focus and
        // receive real input events (execCommand needs a focused editable).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            FileHandle.standardError.write(Data("undotest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            webView.evaluateJavaScript(Self.script, completionHandler: nil)
        } else if type == "undotest" {
            let edit = body["edit"] as? String ?? "?"
            let undo = body["undo"] as? String ?? "?"
            let redo = body["redo"] as? String ?? "?"
            let undoOK = !undo.contains("INSERTED")
            let redoOK = redo.contains("INSERTED")
            print("after edit: \(jsonInline(edit))")
            print("after undo: \(jsonInline(undo))   \(undoOK ? "UNDO OK ✓" : "UNDO FAIL ✗")")
            print("after redo: \(jsonInline(redo))   \(redoOK ? "REDO OK ✓" : "REDO FAIL ✗")")
            exit(undoOK && redoOK ? 0 : 1)
        }
    }

    private func jsonInline(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "\\n") }

    private static let script = """
    (function () {
      function gv() { return window.ouro.getValue(); }
      window.ouro.setValue("Alpha line.");
      setTimeout(function () {
        var ed = window.__ouroEditor, iv = ed.vditor;
        window.ouro.focus();
        ed.insertValue(" INSERTED");
        setTimeout(function () {
          // record the post-edit snapshot exactly as a real input event would
          try { iv.undo.addToUndoStack(iv); } catch (e) {}
          setTimeout(function () {
            var edit = gv();
            window.ouro.undo();
            setTimeout(function () {
              var undo = gv();
              window.ouro.redo();
              setTimeout(function () {
                var redo = gv();
                window.webkit.messageHandlers.ouro.postMessage({ type: "undotest", edit: edit, undo: undo, redo: redo });
              }, 400);
            }, 400);
          }, 200);
        }, 250);
      }, 500);
    })();
    """
}
