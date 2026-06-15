import AppKit
import WebKit

/// Headless `--undotest`: loads the editor, makes a real edit (execCommand →
/// input event → Vditor undo stack), then exercises undo and redo and prints
/// the value at each step, so undo/redo can be verified without a GUI.
final class UndoTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var didStart = false

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
            guard !didStart else { return }
            didStart = true
            webView.evaluateJavaScript(Self.script, completionHandler: nil)
        } else if type == "undotest" {
            let results = body["results"] as? [[String: Any]] ?? []
            var allPassed = true
            for result in results {
                let name = result["name"] as? String ?? "unnamed"
                let ok = result["ok"] as? Bool ?? false
                let detail = result["detail"] as? String ?? ""
                allPassed = allPassed && ok
                print("\(ok ? "PASS" : "FAIL") \(name): \(jsonInline(detail))")
            }
            exit(allPassed && !results.isEmpty ? 0 : 1)
        }
    }

    private func jsonInline(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "\\n") }

    private static let script = """
    (async function () {
      var results = [];
      function delay(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
      function gv() { return window.ouro.getValue(); }
      function record(name, ok, detail) { results.push({ name: name, ok: !!ok, detail: detail || gv() }); }
      async function reset(markdown) {
        window.ouro.setValue(markdown);
        window.ouro.focus();
        await delay(450);
      }
      async function insert(text) {
        var ed = window.__ouroEditor, iv = ed.vditor;
        window.ouro.focus();
        ed.insertValue(text);
        await delay(250);
        try { iv.undo.addToUndoStack(iv); } catch (e) {}
        await delay(250);
      }
      async function undo() { window.ouro.undo(); await delay(350); return gv(); }
      async function redo() { window.ouro.redo(); await delay(350); return gv(); }
      async function waitForEditor() {
        for (var i = 0; i < 30; i++) {
          if (window.__ouroEditor && window.__ouroEditor.vditor) { return true; }
          await delay(100);
        }
        return false;
      }

      await reset("Alpha line.");
      await insert(" ONE");
      await insert(" TWO");
      var afterTwo = gv();
      var undoOne = await undo();
      var undoTwo = await undo();
      var redoOne = await redo();
      var redoTwo = await redo();
      record("multi-step undo/redo",
        afterTwo.indexOf("ONE") >= 0 && afterTwo.indexOf("TWO") >= 0 &&
        undoOne.indexOf("ONE") >= 0 && undoOne.indexOf("TWO") < 0 &&
        undoTwo.indexOf("ONE") < 0 && undoTwo.indexOf("TWO") < 0 &&
        redoOne.indexOf("ONE") >= 0 && redoOne.indexOf("TWO") < 0 &&
        redoTwo.indexOf("ONE") >= 0 && redoTwo.indexOf("TWO") >= 0,
        "edit=" + afterTwo + " undo1=" + undoOne + " undo2=" + undoTwo + " redo1=" + redoOne + " redo2=" + redoTwo);

      await reset("Redo base.");
      await insert(" A");
      await insert(" B");
      await undo();
      await insert(" C");
      var invalidated = await redo();
      record("redo invalidated after new edit",
        invalidated.indexOf("C") >= 0 && invalidated.indexOf("B") < 0,
        invalidated);

      await reset("Empty base.");
      var emptyBefore = gv();
      var emptyUndo = await undo();
      var emptyRedo = await redo();
      record("empty stack no-op",
        emptyUndo === emptyBefore && emptyRedo === emptyBefore,
        "before=" + emptyBefore + " undo=" + emptyUndo + " redo=" + emptyRedo);

      await reset("Mode base.");
      window.ouro.setMode("sv");
      await delay(900);
      await waitForEditor();
      await insert(" AFTERMODE");
      var modeUndo = await undo();
      var modeRedo = await redo();
      record("undo/redo after mode rebuild",
        modeUndo.indexOf("AFTERMODE") < 0 && modeRedo.indexOf("AFTERMODE") >= 0,
        "undo=" + modeUndo + " redo=" + modeRedo);

      window.webkit.messageHandlers.ouro.postMessage({ type: "undotest", results: results });
    })();
    """
}
