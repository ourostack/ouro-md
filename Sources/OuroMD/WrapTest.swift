import AppKit
import WebKit

/// Headless `--wraptest`: loads the editor, selects a word, simulates typing a
/// pairing character (and pasting a URL), and prints the result, so the
/// wrap-the-selection QOL behaviour can be verified without a GUI.
final class WrapTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
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
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("wraptest: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            FileHandle.standardError.write(Data("wraptest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            webView.evaluateJavaScript(Self.script, completionHandler: nil)
        } else if type == "wraptest" {
            let quote = body["quote"] as? String ?? "?"
            let paren = body["paren"] as? String ?? "?"
            let link = body["link"] as? String ?? "?"
            let pairInsert = body["pairInsert"] as? String ?? "?"
            let skipOver = body["skipOver"] as? String ?? "?"
            let deletePair = body["deletePair"] as? String ?? "?"
            let checks: [(String, String, Bool)] = [
                ("type \" over selection", quote, quote.contains("\"world\"")),
                ("type ( over selection", paren, paren.contains("(world)")),
                ("paste url over selection", link, link.contains("[world](https://x.com)")),
                ("auto-pair ( then x", pairInsert, pairInsert.contains("hello(x)")),
                ("skip over typed )", skipOver, skipOver.replacingOccurrences(of: "\n", with: "").contains("()x")),
                ("backspace deletes pair", deletePair, deletePair.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]
            var allOK = true
            for (label, value, ok) in checks {
                if !ok { allOK = false }
                print("\(label): \(value.replacingOccurrences(of: "\n", with: "\\n"))   \(ok ? "OK ✓" : "FAIL ✗")")
            }
            exit(allOK ? 0 : 1)
        }
    }

    private static let script = """
    (function () {
      function gv() { return window.ouro.getValue(); }
      function findText(needle) {
        var root = document.querySelector('#editor');
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
        document.dispatchEvent(new KeyboardEvent('keydown', { key: key, bubbles: true, cancelable: true }));
      }
      function pasteURL(url) {
        var dt = new DataTransfer();
        dt.setData('text/plain', url);
        document.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
      }
      function trial(content, setup, cb) {
        window.ouro.setValue(content);
        setTimeout(function () { window.ouro.focus(); setup(); setTimeout(function () { cb(gv()); }, 300); }, 200);
      }
      setTimeout(function () {
        var out = {};
        trial("hello world", function () { selectWord("world"); typeKey('"'); }, function (v) { out.quote = v;
        trial("hello world", function () { selectWord("world"); typeKey('('); }, function (v) { out.paren = v;
        trial("hello world", function () { selectWord("world"); pasteURL('https://x.com'); }, function (v) { out.link = v;
        trial("hello", function () { caretInNode("hello", 5); typeKey('('); document.execCommand('insertText', false, 'x'); }, function (v) { out.pairInsert = v;
        trial("()", function () { caretInNode("()", 1); typeKey(')'); document.execCommand('insertText', false, 'x'); }, function (v) { out.skipOver = v;
        trial("()", function () { caretInNode("()", 1); typeKey('Backspace'); }, function (v) { out.deletePair = v;
          window.webkit.messageHandlers.ouro.postMessage({ type: "wraptest", quote: out.quote, paren: out.paren, link: out.link, pairInsert: out.pairInsert, skipOver: out.skipOver, deletePair: out.deletePair });
        }); }); }); }); }); });
      }, 500);
    })();
    """
}
