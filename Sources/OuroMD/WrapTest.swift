import AppKit
import WebKit

/// Headless `--wraptest`: loads the editor, selects a word, simulates typing a
/// pairing character (and pasting a URL), and prints the result, so the
/// wrap-the-selection QOL behaviour can be verified without a GUI.
final class WrapTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
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
        configuration.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("wraptest: index.html not found\n".utf8)); exit(1)
        }
        window = HeadlessHarness.offscreenHostActive(webView, size: NSSize(width: 800, height: 600))

        lastPhase = "loading \(indexURL.path)"
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            let phase = self?.lastPhase ?? "unknown"
            FileHandle.standardError.write(Data("wraptest: timed out (\(phase))\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishNavigation = true
        if !didStart {
            lastPhase = "navigation finished; waiting for editor ready"
        }
        startScriptIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("wraptest: navigation failed: \(error)\n".utf8))
        exit(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("wraptest: provisional navigation failed: \(error)\n".utf8))
        exit(1)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        FileHandle.standardError.write(Data("wraptest: web content process terminated\n".utf8))
        exit(1)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            guard !didStart else { return }
            didReceiveReady = true
            lastPhase = "editor ready; waiting for navigation finish"
            startScriptIfReady()
        } else if type == "wraptest" {
            if let error = body["error"] as? String {
                FileHandle.standardError.write(Data("wraptest: \(error)\n".utf8))
                exit(1)
            }
            let quote = body["quote"] as? String ?? "?"
            let paren = body["paren"] as? String ?? "?"
            let link = body["link"] as? String ?? "?"
            let pairInsert = body["pairInsert"] as? String ?? "?"
            let skipOver = body["skipOver"] as? String ?? "?"
            let curlySkip = body["curlySkip"] as? String ?? "?"
            let deletePair = body["deletePair"] as? String ?? "?"
            let checks: [(String, String, Bool)] = [
                ("type \" over selection", quote, quote.contains("\"world\"") || quote.contains("“world\"") || quote.contains("“world”")),
                ("type ( over selection", paren, paren.contains("(world)")),
                ("paste url over selection", link, link.contains("[world](https://x.com)")),
                ("auto-pair ( then x", pairInsert, pairInsert.contains("hello(x)")),
                ("skip over typed )", skipOver, skipOver.replacingOccurrences(of: "\n", with: "").contains("()x")),
                ("skip over a curly close-quote", curlySkip, curlySkip.replacingOccurrences(of: "\n", with: "").contains("a”xb")),
                ("backspace deletes pair", deletePair, deletePair.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]
            var allOK = true
            for (label, value, ok) in checks {
                if !ok { allOK = false }
                print("\(label): \(value.replacingOccurrences(of: "\n", with: "\\n"))   \(ok ? "OK ✓" : "FAIL ✗")")
            }
            exit(allOK ? 0 : 1)
        } else if type == "wrapstep" {
            lastPhase = "script step: \(body["step"] as? String ?? "unknown")"
        }
    }

    private func startScriptIfReady() {
        guard didReceiveReady, didFinishNavigation, !didStart else { return }
        didStart = true
        lastPhase = "editor ready and navigation finished; running wrap script"
        webView.evaluateJavaScript(Self.script) { _, error in
            if let error {
                FileHandle.standardError.write(Data("wraptest: script failed: \(error)\n".utf8))
                exit(1)
            }
            self.lastPhase = "wrap script dispatched"
        }
    }

    private static let script = """
    (function () {
      function post(payload) {
        window.webkit.messageHandlers.ouro.postMessage(payload);
      }
      post({ type: "wrapstep", step: "script entered" });
      function sandbox() { return document.getElementById("wraptest-sandbox"); }
      function gv() {
        var box = sandbox();
        return box ? (box.textContent || "") : "";
      }
      function setSandbox(content) {
        var root = document.getElementById("editor");
        if (!root) { throw new Error("#editor not found"); }
        var prior = sandbox();
        if (prior && prior.parentNode) { prior.parentNode.removeChild(prior); }
        var box = document.createElement("div");
        box.id = "wraptest-sandbox";
        box.contentEditable = "true";
        box.textContent = content;
        root.appendChild(box);
      }
      function findText(needle) {
        var root = sandbox();
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
        var n;
        while ((n = walker.nextNode())) { if (n.nodeValue && n.nodeValue.indexOf(needle) !== -1) { return n; } }
        return null;
      }
      function selectWord(word) {
        var n = findText(word);
        if (!n) { return false; }
        var idx = n.nodeValue.indexOf(word);
        var r = document.createRange();
        r.setStart(n, idx); r.setEnd(n, idx + word.length);
        var sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
        return true;
      }
      function caretInNode(needle, pos) {
        var n = findText(needle);
        if (!n) { return false; }
        var at = n.nodeValue.indexOf(needle) + pos;
        var r = document.createRange();
        r.setStart(n, at); r.collapse(true);
        var sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
        return true;
      }
      function typeKey(key) {
        if (!window.__ouroQOLTest || !window.__ouroQOLTest.key(key)) {
          throw new Error("QOL key hook did not handle " + key);
        }
      }
      function pasteURL(url) {
        if (!window.__ouroQOLTest || !window.__ouroQOLTest.pastePlainText(url)) {
          throw new Error("QOL paste hook did not handle URL");
        }
      }
      function trial(content, setup, cb) {
        post({ type: "wrapstep", step: "trial setSandbox start" });
        setSandbox(content);
        post({ type: "wrapstep", step: "trial setSandbox done" });
        try {
          setup();
          cb(gv());
        } catch (e) {
          post({ type: "wraptest", error: "trial failed: " + String(e && (e.stack || e.message || e)) });
        }
      }
      setTimeout(function () {
        post({ type: "wrapstep", step: "outer timer fired" });
        try {
        var out = {};
        trial("hello world", function () { selectWord("world"); typeKey('"'); }, function (v) { out.quote = v;
        trial("hello world", function () { selectWord("world"); typeKey('('); }, function (v) { out.paren = v;
        trial("hello world", function () { selectWord("world"); pasteURL('https://x.com'); }, function (v) { out.link = v;
        trial("hello", function () { caretInNode("hello", 5); typeKey('('); document.execCommand('insertText', false, 'x'); }, function (v) { out.pairInsert = v;
        trial("()", function () { caretInNode("()", 1); typeKey(')'); document.execCommand('insertText', false, 'x'); }, function (v) { out.skipOver = v;
        trial("a”b", function () { caretInNode("a”b", 1); typeKey('"'); document.execCommand('insertText', false, 'x'); }, function (v) { out.curlySkip = v;
        trial("()", function () { caretInNode("()", 1); typeKey('Backspace'); }, function (v) { out.deletePair = v;
          post({ type: "wraptest", quote: out.quote, paren: out.paren, link: out.link, pairInsert: out.pairInsert, skipOver: out.skipOver, curlySkip: out.curlySkip, deletePair: out.deletePair });
        }); }); }); }); }); }); });
        } catch (e) {
          post({ type: "wraptest", error: String(e && (e.stack || e.message || e)) });
        }
      }, 1500);
    })();
    """
}
