import AppKit
import WebKit

/// Headless `--linktest`: loads the editor with a Markdown link in IR (live
/// preview) mode, simulates a ⌘-click on it, and verifies the bridge resolves
/// the URL and posts an `openURL` message — so the "links don't open" fix can be
/// verified without a GUI (and without launching a browser: this harness
/// intercepts `openURL` itself rather than calling NSWorkspace).
final class LinkTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var openedURL: String?

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
            FileHandle.standardError.write(Data("linktest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHost(webView, size: NSSize(width: 800, height: 600))

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            FileHandle.standardError.write(Data("linktest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            webView.evaluateJavaScript(Self.script, completionHandler: nil)
        } else if type == "openURL" {
            // The bridge's ⌘-click handler fired. Record it instead of opening.
            openedURL = body["url"] as? String
        } else if type == "linkprobe" {
            let found = body["found"] as? Bool ?? false
            let opened = openedURL ?? ""
            let checks: [(String, String, Bool)] = [
                ("IR link node rendered for [text](url)", "found=\(found)", found),
                ("⌘-mousedown posts openURL with the link's URL", "opened=\(opened)", opened == "https://ouro.bot")
            ]
            var allOK = true
            for (label, value, ok) in checks {
                if !ok { allOK = false }
                print("\(label): \(value)   \(ok ? "OK ✓" : "FAIL ✗")")
            }
            exit(allOK ? 0 : 1)
        }
    }

    private static let script = """
    (function () {
      setTimeout(function () {
        window.ouro.setValue("[OuroMD](https://ouro.bot)");
        setTimeout(function () {
          window.ouro.focus();
          var node = document.querySelector('#editor span[data-type="a"]');
          var target = node && (node.querySelector('.vditor-ir__link') || node);
          var found = !!target;
          // ⌘-mousedown the link; the bridge now opens on mousedown (macOS
          // WKWebView does not reliably fire a `click` for a ⌘-click in a
          // contenteditable), so this is the event the real fix depends on.
          if (found) {
            target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, metaKey: true }));
          }
          setTimeout(function () {
            window.webkit.messageHandlers.ouro.postMessage({ type: "linkprobe", found: found });
          }, 200);
        }, 600);
      }, 500);
    })();
    """
}
