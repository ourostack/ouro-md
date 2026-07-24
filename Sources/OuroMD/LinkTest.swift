import AppKit
import WebKit

/// Headless `--linktest`: verifies both link contracts in IR (live-preview):
/// ⌘-click opens an external URL, while a normal click forwards a relative
/// Markdown target for native resolution into another Ouro MD window.
final class LinkTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private var openedURLs: [String] = []
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
            FileHandle.standardError.write(Data("linktest: index.html not found\n".utf8)); exit(1)
        }
        window = HeadlessHarness.offscreenHostActive(webView, size: NSSize(width: 800, height: 600))

        lastPhase = "loading \(indexURL.path)"
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in
            let phase = self?.lastPhase ?? "unknown"
            FileHandle.standardError.write(Data("linktest: timed out (\(phase))\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            guard !didStart else { return }
            didReceiveReady = true
            lastPhase = "editor ready; waiting for navigation finish"
            startScriptIfReady()
        } else if type == "openURL" {
            if let url = body["url"] as? String { openedURLs.append(url) }
        } else if type == "linkprobe" {
            lastPhase = "results received"
            let foundExternal = body["foundExternal"] as? Bool ?? false
            let foundLocal = body["foundLocal"] as? Bool ?? false
            let scriptError = body["error"] as? String
            let checks: [(String, String, Bool)] = [
                ("linktest script completed", scriptError ?? "ok", scriptError == nil),
                ("IR external link rendered", "found=\(foundExternal)", foundExternal),
                ("IR local Markdown link rendered", "found=\(foundLocal)", foundLocal),
                (
                    "⌘-mousedown forwards external URL",
                    "opened=\(openedURLs)",
                    openedURLs.first == "https://ouro.bot"
                ),
                (
                    "plain click forwards raw relative Markdown target",
                    "opened=\(openedURLs)",
                    openedURLs.count == 2 && openedURLs[1] == "mendelow-me-build-corpus.md"
                )
            ]
            var allOK = true
            for (label, value, ok) in checks {
                if !ok { allOK = false }
                print("\(label): \(value)   \(ok ? "OK ✓" : "FAIL ✗")")
            }
            exit(allOK ? 0 : 1)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishNavigation = true
        if !didStart {
            lastPhase = "navigation finished; waiting for editor ready"
        }
        startScriptIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("linktest: navigation failed: \(error)\n".utf8))
        exit(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("linktest: provisional navigation failed: \(error)\n".utf8))
        exit(1)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        FileHandle.standardError.write(Data("linktest: web content process terminated\n".utf8))
        exit(1)
    }

    private func startScriptIfReady() {
        guard didReceiveReady, didFinishNavigation, !didStart else { return }
        didStart = true
        lastPhase = "editor ready and navigation finished; running link script"
        webView.evaluateJavaScript(Self.script) { _, error in
            if let error {
                FileHandle.standardError.write(Data("linktest: script dispatch failed: \(error)\n".utf8))
                exit(1)
            }
            self.lastPhase = "link script dispatched"
        }
    }

    private static let script = """
    (function () {
      function post(payload) {
        window.webkit.messageHandlers.ouro.postMessage(Object.assign({ type: "linkprobe" }, payload));
      }
      try {
        setTimeout(function () {
          try {
            window.ouro.setValue("[OuroMD](https://ouro.bot)\\n\\n[build corpus](mendelow-me-build-corpus.md)");
            setTimeout(function () {
              try {
                window.ouro.focus();
                var nodes = document.querySelectorAll('#editor span[data-type="a"]');
                var externalTarget = nodes[0] && (nodes[0].querySelector('.vditor-ir__link') || nodes[0]);
                var localTarget = nodes[1] && (nodes[1].querySelector('.vditor-ir__link') || nodes[1]);
                var foundExternal = !!externalTarget;
                var foundLocal = !!localTarget;
                // ⌘-mousedown the link; the bridge now opens on mousedown (macOS
                // WKWebView does not reliably fire a `click` for a ⌘-click in a
                // contenteditable), so this is the event the real fix depends on.
                if (foundExternal) {
                  externalTarget.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, metaKey: true }));
                }
                setTimeout(function () {
                  // Local Markdown stays inside the app, so a normal rendered-link
                  // click should open another Ouro MD window without a modifier.
                  if (foundLocal) {
                    localTarget.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                  }
                  setTimeout(function () {
                    post({ foundExternal: foundExternal, foundLocal: foundLocal });
                  }, 200);
                }, 800);
              } catch (error) {
                post({ foundExternal: false, foundLocal: false, error: error && (error.stack || error.message) ? (error.stack || error.message) : String(error) });
              }
            }, 600);
          } catch (error) {
            post({ foundExternal: false, foundLocal: false, error: error && (error.stack || error.message) ? (error.stack || error.message) : String(error) });
          }
        }, 500);
      } catch (error) {
        post({ foundExternal: false, foundLocal: false, error: error && (error.stack || error.message) ? (error.stack || error.message) : String(error) });
      }
    })();
    undefined;
    """
}
