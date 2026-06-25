import AppKit
import WebKit

/// Headless `--undotest`: loads the editor, makes a real edit (execCommand →
/// input event → Vditor undo stack), then exercises undo and redo and prints
/// the value at each step, so undo/redo can be verified without a GUI.
final class UndoTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private var didStart = false
    private var didFinishNavigation = false
    private var didReceiveReady = false
    private var lastPhase = "not started"

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("undotest: index.html not found\n".utf8)); exit(1)
        }
        // Undo runs through a focused contentEditable, so the app must be active
        // for WebKit to grant DOM focus. The host window stays off-screen.
        self.window = HeadlessHarness.offscreenHostActive(webView, size: NSSize(width: 800, height: 600))

        lastPhase = "loading \(indexURL.path)"
        logDebug(lastPhase)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        let timeout = max(120.0, Double(stressCycles) * 2.5 + 60.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            let phase = self?.lastPhase ?? "unknown"
            FileHandle.standardError.write(Data("undotest: timed out (\(phase))\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            guard !didStart else {
                logDebug("ignored editor ready while undo script is running")
                return
            }
            didReceiveReady = true
            lastPhase = "editor ready; waiting for navigation finish"
            logDebug(lastPhase)
            startUndoScriptIfReady()
        } else if type == "undotest" {
            lastPhase = "results received"
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
        } else if type == "undostep" {
            let step = body["step"] as? String ?? "unknown"
            lastPhase = "script step: \(step)"
            logDebug(lastPhase)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishNavigation = true
        if !didStart {
            lastPhase = "navigation finished; waiting for editor ready"
        }
        logDebug(lastPhase)
        startUndoScriptIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("undotest: navigation failed: \(error)\n".utf8))
        exit(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("undotest: provisional navigation failed: \(error)\n".utf8))
        exit(1)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        FileHandle.standardError.write(Data("undotest: web content process terminated\n".utf8))
        exit(1)
    }

    private func jsonInline(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "\\n") }

    private func startUndoScriptIfReady() {
        guard didReceiveReady, didFinishNavigation, !didStart else { return }
        didStart = true
        lastPhase = "editor ready and navigation finished; running undo script"
        logDebug(lastPhase)
        webView.evaluateJavaScript(Self.script(stressCycles: stressCycles)) { _, error in
            if let error {
                FileHandle.standardError.write(Data("undotest: script failed: \(error)\n".utf8))
                exit(1)
            }
            self.lastPhase = "undo script dispatched"
            self.logDebug("script dispatched")
        }
    }

    private var debug: Bool {
        ProcessInfo.processInfo.environment["OURO_UNDO_DEBUG"] == "1"
    }

    private func logDebug(_ message: String) {
        guard debug else { return }
        FileHandle.standardError.write(Data("undotest: \(message)\n".utf8))
    }

    private var stressCycles: Int {
        max(1, Int(ProcessInfo.processInfo.environment["OURO_UNDO_STRESS_CYCLES"] ?? "") ?? 20)
    }

    private static func script(stressCycles: Int) -> String {
        """
    void (async function () {
      var results = [];
      var lastStep = "script start";
      var finished = false;
      var watchdog = setTimeout(function () {
        finish([{ name: "script watchdog", ok: false, detail: "last step: " + lastStep }]);
      }, Math.max(20000, \(stressCycles) * 3000 + 20000));
      function step(name) {
        lastStep = name;
        try { window.webkit.messageHandlers.ouro.postMessage({ type: "undostep", step: name }); } catch (e) {}
      }
      function finish(payload) {
        if (finished) { return; }
        finished = true;
        clearTimeout(watchdog);
        window.webkit.messageHandlers.ouro.postMessage({ type: "undotest", results: payload });
      }
      try {
      function delay(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
      function gv() { return window.ouro.getValue(); }
      function record(name, ok, detail) { results.push({ name: name, ok: !!ok, detail: detail || gv() }); }
      async function reset(markdown) {
        window.ouro.setValue(markdown);
        await delay(150);
        var ed = window.__ouroEditor;
        if (ed && ed.vditor && ed.vditor.undo) {
          try {
            ed.vditor.undo.clearStack(ed.vditor);
            ed.vditor.undo.addToUndoStack(ed.vditor);
          } catch (e) {
            throw new Error("undo stack reset failed: " + e);
          }
        }
        window.ouro.focus();
        await delay(300);
      }
      async function insert(text) {
        var ed = window.__ouroEditor;
        if (!ed || !ed.vditor) { return "editor not ready"; }
        window.ouro.focus();
        var stack = ed.vditor.undo && ed.vditor.undo[ed.vditor.currentMode];
        if (stack && stack.undoStack && stack.undoStack.length === 0) {
          try { ed.vditor.undo.addToUndoStack(ed.vditor); } catch (e) { return "undo stack baseline failed: " + e; }
        } else if (stack && stack.hasUndo) {
          try { ed.vditor.undo.addToUndoStack(ed.vditor); } catch (e) { return "undo stack redo invalidation failed: " + e; }
        }
        ed.insertValue(text, false);
        try { ed.vditor.undo.addToUndoStack(ed.vditor); } catch (e) { return "undo stack insert failed: " + e; }
        await delay(350);
        return "";
      }
      async function undo() { window.ouro.undo(); await delay(350); return gv(); }
      async function redo() { window.ouro.redo(); await delay(350); return gv(); }
      step("multi-step undo/redo");
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

      finish(results);
      } catch (e) {
        finish([{ name: "script exception", ok: false, detail: String(e && (e.stack || e.message) || e) }]);
      }
    })();
    """
    }
}
