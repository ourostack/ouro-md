import AppKit
import WebKit

/// Headless `--undotest`: loads the editor, makes a real edit (execCommand →
/// input event → Vditor undo stack), then exercises undo and redo and prints
/// the value at each step, so undo/redo can be verified without a GUI.
final class UndoTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private var shortcutMonitor: UndoRedoShortcutMonitor?
    private var lastShortcutHandled = false
    private var lastShortcutResponder = ""
    private var didStart = false
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
        // for WebKit to grant DOM focus and route the synthesized cmd-z — the host
        // window stays off-screen, so nothing visible appears.
        self.window = HeadlessHarness.offscreenHostActive(webView, size: NSSize(width: 800, height: 600))
        installShortcutMonitor()

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
            guard !didStart else { return }
            didStart = true
            lastPhase = "editor ready; running undo script"
            logDebug(lastPhase)
            webView.evaluateJavaScript(Self.script(stressCycles: stressCycles)) { _, error in
                if let error {
                    FileHandle.standardError.write(Data("undotest: script failed: \(error)\n".utf8))
                    exit(1)
                }
                self.logDebug("script dispatched")
            }
        } else if type == "shortcut" {
            guard let command = body["command"] as? String,
                  let nonce = body["nonce"] as? String else { return }
            lastPhase = "native shortcut requested: \(command)"
            logDebug(lastPhase)
            sendShortcut(command, nonce: nonce)
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
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastPhase = "navigation finished; waiting for editor ready"
        logDebug(lastPhase)
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

    private func installShortcutMonitor() {
        let monitor = UndoRedoShortcutMonitor { [weak self] command, firstResponder in
            guard let self else { return false }
            let handled = UndoRedoCommandRouter.perform(
                command,
                firstResponder: firstResponder,
                editorIsReady: true,
                editorUndo: { self.webView.evaluateJavaScript("window.ouro && window.ouro.undo()", completionHandler: nil) },
                editorRedo: { self.webView.evaluateJavaScript("window.ouro && window.ouro.redo()", completionHandler: nil) }
            )
            self.lastShortcutHandled = handled
            self.lastShortcutResponder = Self.responderDescription(firstResponder)
            return handled
        }
        monitor.install()
        shortcutMonitor = monitor
    }

    private func sendShortcut(_ command: String, nonce: String) {
        let modifiers: NSEvent.ModifierFlags
        let characters: String
        let keyCode: UInt16
        switch command {
        case "redo":
            modifiers = [.command, .shift]
            characters = "Z"
            keyCode = 6
        case "redoY":
            modifiers = [.command]
            characters = "y"
            keyCode = 16
        default:
            modifiers = [.command]
            characters = "z"
            keyCode = 6
        }
        lastShortcutHandled = false
        lastShortcutResponder = Self.responderDescription(window.firstResponder)
        guard let event = NSEvent.keyEvent(with: .keyDown,
                                           location: .zero,
                                           modifierFlags: modifiers,
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber,
                                           context: nil,
                                           characters: characters,
                                           charactersIgnoringModifiers: characters.lowercased(),
                                           isARepeat: false,
                                           keyCode: keyCode) else {
            let js = "window.__ouroShortcutDone(\(Self.jsString(nonce)),false,\(Self.jsString("event-unavailable")))"
            webView.evaluateJavaScript(js, completionHandler: nil)
            return
        }
        NSApp.sendEvent(event)
        let js = "window.__ouroShortcutDone(\(Self.jsString(nonce)),\(lastShortcutHandled ? "true" : "false"),\(Self.jsString(lastShortcutResponder)))"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private static func responderDescription(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        return String(describing: type(of: responder))
    }

    private static func jsString(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
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
      function step(name) { lastStep = name; }
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
      var shortcutNonce = 0;
      var shortcutResolvers = {};
      window.__ouroShortcutDone = function (nonce, handled, responder) {
        if (shortcutResolvers[nonce]) {
          shortcutResolvers[nonce]({ handled: !!handled, responder: responder || "" });
          delete shortcutResolvers[nonce];
        }
      };
      async function reset(markdown) {
        window.ouro.setValue(markdown);
        window.ouro.focus();
        await delay(450);
      }
      async function insert(text) {
        var ed = window.__ouroEditor;
        if (!ed || !ed.vditor) { return "editor not ready"; }
        window.ouro.focus();
        var stack = ed.vditor.undo && ed.vditor.undo[ed.vditor.currentMode];
        if (stack && stack.undoStack && stack.undoStack.length === 0) {
          try { ed.vditor.undo.addToUndoStack(ed.vditor); } catch (e) { return "undo stack baseline failed: " + e; }
        }
        ed.insertValue(text, false);
        try { ed.vditor.undo.addToUndoStack(ed.vditor); } catch (e) { return "undo stack insert failed: " + e; }
        await delay(350);
        return "";
      }
      async function undo() { window.ouro.undo(); await delay(350); return gv(); }
      async function redo() { window.ouro.redo(); await delay(350); return gv(); }
      async function shortcut(command) {
        var nonce = String(++shortcutNonce);
        step("shortcut " + command + " waiting for native response");
        var meta = await new Promise(function (resolve) {
          var done = false;
          function finish(value) {
            if (done) { return; }
            done = true;
            resolve(value);
          }
          shortcutResolvers[nonce] = finish;
          setTimeout(function () {
            if (shortcutResolvers[nonce]) {
              delete shortcutResolvers[nonce];
              finish({ handled: false, responder: "shortcut-timeout" });
            }
          }, 1500);
          window.webkit.messageHandlers.ouro.postMessage({ type: "shortcut", command: command, nonce: nonce });
        });
        await delay(450);
        return { value: gv(), handled: !!meta.handled, responder: meta.responder || "" };
      }
      async function waitForEditorReplacement(previous) {
        for (var i = 0; i < 50; i++) {
          var ed = window.__ouroEditor;
          if (ed && ed !== previous && ed.vditor) { return true; }
          await delay(100);
        }
        return false;
      }
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

      step("native shortcut undo/redo");
      await reset("Shortcut base.");
      await insert(" ONE");
      await insert(" TWO");
      var shortcutAfterTwo = gv();
      var shortcutUndoOneMeta = await shortcut("undo");
      var shortcutUndoTwoMeta = await shortcut("undo");
      var shortcutRedoOneMeta = await shortcut("redo");
      var shortcutRedoTwoMeta = await shortcut("redo");
      var shortcutUndoOne = shortcutUndoOneMeta.value;
      var shortcutUndoTwo = shortcutUndoTwoMeta.value;
      var shortcutRedoOne = shortcutRedoOneMeta.value;
      var shortcutRedoTwo = shortcutRedoTwoMeta.value;
      record("cmd-z/cmd-shift-z native shortcut undo/redo",
        shortcutUndoOneMeta.handled && shortcutUndoTwoMeta.handled &&
        shortcutRedoOneMeta.handled && shortcutRedoTwoMeta.handled &&
        shortcutAfterTwo.indexOf("ONE") >= 0 && shortcutAfterTwo.indexOf("TWO") >= 0 &&
        shortcutUndoOne.indexOf("ONE") >= 0 && shortcutUndoOne.indexOf("TWO") < 0 &&
        shortcutUndoTwo.indexOf("ONE") < 0 && shortcutUndoTwo.indexOf("TWO") < 0 &&
        shortcutRedoOne.indexOf("ONE") >= 0 && shortcutRedoOne.indexOf("TWO") < 0 &&
        shortcutRedoTwo.indexOf("ONE") >= 0 && shortcutRedoTwo.indexOf("TWO") >= 0,
        "handled=" + [shortcutUndoOneMeta.handled, shortcutUndoTwoMeta.handled, shortcutRedoOneMeta.handled, shortcutRedoTwoMeta.handled].join(",") +
        " responder=" + shortcutRedoTwoMeta.responder +
        " edit=" + shortcutAfterTwo + " undo1=" + shortcutUndoOne + " undo2=" + shortcutUndoTwo + " redo1=" + shortcutRedoOne + " redo2=" + shortcutRedoTwo);

      step("cmd-y redo fallback");
      await reset("Shortcut Y base.");
      await insert(" YALT");
      await shortcut("undo");
      var redoYMeta = await shortcut("redoY");
      var redoY = redoYMeta.value;
      record("cmd-y native shortcut redo fallback",
        redoYMeta.handled && redoY.indexOf("YALT") >= 0,
        "handled=" + redoYMeta.handled + " responder=" + redoYMeta.responder + " value=" + redoY);

      step("redo invalidated after new edit");
      await reset("Redo base.");
      await insert(" A");
      await insert(" B");
      await undo();
      await insert(" C");
      var invalidated = await redo();
      record("redo invalidated after new edit",
        invalidated.indexOf("C") >= 0 && invalidated.indexOf("B") < 0,
        invalidated);

      step("mode rebuild undo/redo");
      await reset("Mode base.");
      var beforeRebuild = window.__ouroEditor;
      window.ouro.setMode("sv");
      var rebuilt = await waitForEditorReplacement(beforeRebuild);
      if (!rebuilt) {
        record("undo/redo after mode rebuild", false, "new editor did not become ready after mode change");
      } else {
        var modeInsertError = await insert(" AFTERMODE");
        if (modeInsertError) {
          record("undo/redo after mode rebuild", false, modeInsertError);
        } else {
          var modeUndo = await undo();
          var modeRedo = await redo();
          record("undo/redo after mode rebuild",
            modeUndo.indexOf("AFTERMODE") < 0 && modeRedo.indexOf("AFTERMODE") >= 0,
            "undo=" + modeUndo + " redo=" + modeRedo);
        }
      }

      step("shortcut stress");
      await reset("Shortcut stress base.");
      var stressOk = true;
      var stressDetail = "";
      for (var i = 0; i < \(stressCycles); i++) {
        var token = "S" + i + "_TOKEN";
        var beforeStressEdit = gv();
        var insertError = await insert(" " + token);
        if (insertError) {
          stressOk = false;
          stressDetail = insertError;
          break;
        }
        var afterStressEdit = gv();
        var stressUndoMeta = await shortcut("undo");
        var stressRedoMeta = await shortcut("redo");
        var stressUndo = stressUndoMeta.value;
        var stressRedo = stressRedoMeta.value;
        if (!stressUndoMeta.handled || !stressRedoMeta.handled ||
            afterStressEdit.indexOf(token) < 0 ||
            stressUndo !== beforeStressEdit ||
            stressRedo !== afterStressEdit) {
          stressOk = false;
          stressDetail = "cycle=" + i + " undoHandled=" + stressUndoMeta.handled +
            " redoHandled=" + stressRedoMeta.handled + " responder=" + stressRedoMeta.responder +
            " before=" + beforeStressEdit + " edit=" + afterStressEdit +
            " undo=" + stressUndo + " redo=" + stressRedo;
          break;
        }
      }
      record("cmd-shift-z redo stress \(stressCycles)x", stressOk, stressDetail || gv());

      step("empty stack no-op");
      await reset("Empty base.");
      var emptyBefore = gv();
      var emptyUndoMeta = await shortcut("undo");
      var emptyUndo = emptyUndoMeta.value;
      var emptyRedoMeta = await shortcut("redo");
      var emptyRedo = emptyRedoMeta.value;
      record("empty stack no-op",
        emptyUndoMeta.handled && emptyRedoMeta.handled && emptyUndo === emptyBefore && emptyRedo === emptyBefore,
        "before=" + emptyBefore + " undo=" + emptyUndo + " redo=" + emptyRedo +
        " handled=" + emptyUndoMeta.handled + "," + emptyRedoMeta.handled);

      finish(results);
      } catch (e) {
        finish([{ name: "script exception", ok: false, detail: String(e && (e.stack || e.message) || e) }]);
      }
    })();
    """
    }
}
