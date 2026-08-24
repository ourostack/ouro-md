import AppKit
import WebKit

/// Headless `--linktest`: verifies link rendering, gestures, and fragment
/// navigation against the real bundled Vditor surface.
final class LinkTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let markdown: String?
    private let inputError: Error?
    private let artifactDirectory: URL?
    private var webView: WKWebView!
    private var window: NSWindow!
    private var openedURLs: [String] = []
    private var didStart = false
    private var didFinishNavigation = false
    private var didReceiveReady = false
    private var lastPhase = "not started"

    init(markdownPath: String? = nil, artifactDirectoryPath: String? = nil) {
        if let markdownPath {
            do {
                markdown = try String(contentsOfFile: markdownPath, encoding: .utf8)
                inputError = nil
            } catch {
                markdown = nil
                inputError = error
            }
        } else {
            markdown = nil
            inputError = nil
        }
        artifactDirectory = artifactDirectoryPath.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
    }

    func run() -> Never {
        if let inputError {
            FileHandle.standardError.write(Data("linktest: \(inputError.localizedDescription)\n".utf8))
            exit(2)
        }

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
            FileHandle.standardError.write(Data("linktest: index.html not found\n".utf8))
            exit(1)
        }
        window = HeadlessHarness.offscreenHostActive(webView, size: NSSize(width: 800, height: 600))

        lastPhase = "loading \(indexURL.path)"
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        let outerBudget = Double(
            ProcessInfo.processInfo.environment["OURO_LINKTEST_SCENARIO_TIMEOUT_SECONDS"] ?? ""
        ) ?? 90
        let internalBudget = max(10, outerBudget * 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + internalBudget) { [weak self] in
            let phase = self?.lastPhase ?? "unknown"
            FileHandle.standardError.write(Data("linktest: timed out (\(phase))\n".utf8))
            exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            guard !didStart else { return }
            didReceiveReady = true
            lastPhase = "editor ready; waiting for navigation finish"
            startScriptIfReady()
        case "openURL":
            if let url = body["url"] as? String { openedURLs.append(url) }
        case "linkprobe":
            handleProbe(body)
        default:
            break
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
        let source: String
        if let markdown {
            lastPhase = "running extended link contract"
            source = Self.extendedScript(markdown)
        } else {
            lastPhase = "running legacy link contract"
            source = Self.legacyScript
        }
        webView.evaluateJavaScript(source) { _, error in
            if let error {
                FileHandle.standardError.write(Data("linktest: script dispatch failed: \(error)\n".utf8))
                exit(1)
            }
            self.lastPhase = "link script dispatched"
        }
    }

    private func handleProbe(_ body: [String: Any]) {
        lastPhase = "results received"
        let scriptError = body["error"] as? String
        let checks: [(String, String, Bool)]

        if markdown == nil {
            let foundExternal = body["foundExternal"] as? Bool ?? false
            let foundLocal = body["foundLocal"] as? Bool ?? false
            checks = [
                ("linktest script completed", scriptError ?? "ok", scriptError == nil),
                ("IR external link rendered", "found=\(foundExternal)", foundExternal),
                ("IR local Markdown link rendered", "found=\(foundLocal)", foundLocal),
                ("Command-mousedown forwards external URL", "opened=\(openedURLs)", openedURLs.first == "https://ouro.bot"),
                (
                    "plain click forwards raw relative Markdown target",
                    "opened=\(openedURLs)",
                    openedURLs.count == 2 && openedURLs[1] == "mendelow-me-build-corpus.md"
                ),
            ]
        } else {
            checks = [
                ("linktest script completed", scriptError ?? "ok", scriptError == nil),
                ("IR resolved reference nodes rendered", "\(body["irReferenceCount"] ?? "nil")", (body["irReferenceCount"] as? Int ?? 0) >= 7),
                ("IR unresolved reference stays source text", "\(body["irUnresolvedPlain"] ?? "nil")", body["irUnresolvedPlain"] as? Bool ?? false),
                ("IR focused reference markers hidden", "\(body["irMarkersHidden"] ?? "nil")", body["irMarkersHidden"] as? Bool ?? false),
                ("IR reference has link affordance", "\(body["irLinkAffordance"] ?? "nil")", body["irLinkAffordance"] as? Bool ?? false),
                ("external reference opens on Command-mousedown", "opened=\(openedURLs)", openedURLs.contains("https://example.com/external")),
                ("local reference opens in app", "opened=\(openedURLs)", openedURLs.contains("other.md#target-heading")),
                ("collapsed reference resolves", "opened=\(openedURLs)", openedURLs.contains("https://example.com/collapsed")),
                ("shortcut reference resolves", "opened=\(openedURLs)", openedURLs.contains("https://example.com/shortcut")),
                ("normalized label resolves", "opened=\(openedURLs)", openedURLs.contains("https://example.com/normalized")),
                ("IR fragment scrolls", "\(body["irAnchorScrolled"] ?? "nil")", body["irAnchorScrolled"] as? Bool ?? false),
                ("SV source remains literal", "\(body["svSourceLiteral"] ?? "nil")", body["svSourceLiteral"] as? Bool ?? false),
                ("SV preview resolves reference", "\(body["svReferenceRendered"] ?? "nil")", body["svReferenceRendered"] as? Bool ?? false),
                ("SV fragment scrolls", "\(body["svAnchorScrolled"] ?? "nil")", body["svAnchorScrolled"] as? Bool ?? false),
                ("fragment navigation keeps editor URL stable", "\(body["pageURLStable"] ?? "nil")", body["pageURLStable"] as? Bool ?? false),
                ("IR app export uses shared heading IDs", "\(body["irExportAnchors"] ?? "nil")", body["irExportAnchors"] as? Bool ?? false),
                ("SV app export uses shared heading IDs", "\(body["svExportAnchors"] ?? "nil")", body["svExportAnchors"] as? Bool ?? false),
                ("app export preserves non-heading IDs", "\(body["nonHeadingIDsStable"] ?? "nil")", body["nonHeadingIDsStable"] as? Bool ?? false),
            ]
        }

        var allOK = true
        for (label, value, ok) in checks {
            if !ok { allOK = false }
            print("\(label): \(value)   \(ok ? "OK ✓" : "FAIL ✗")")
        }
        persistArtifacts(body) {
            exit(allOK ? 0 : 1)
        }
    }

    private func persistArtifacts(_ body: [String: Any], completion: @escaping () -> Void) {
        guard let artifactDirectory else {
            completion()
            return
        }
        do {
            try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: artifactDirectory.appendingPathComponent("link-results.json"))
        } catch {
            FileHandle.standardError.write(Data("linktest: could not write result artifact: \(error)\n".utf8))
        }

        webView.takeSnapshot(with: nil) { image, error in
            if let error {
                FileHandle.standardError.write(Data("linktest: snapshot failed: \(error)\n".utf8))
            } else if let tiff = image?.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try png.write(to: artifactDirectory.appendingPathComponent("link-final.png"))
                } catch {
                    FileHandle.standardError.write(Data("linktest: could not write snapshot: \(error)\n".utf8))
                }
            }
            completion()
        }
    }

    private static func extendedScript(_ markdown: String) -> String {
        """
        (async function () {
          function post(payload) {
            window.webkit.messageHandlers.ouro.postMessage(Object.assign({ type: "linkprobe" }, payload));
          }
          function sleep(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
          async function waitFor(predicate, label) {
            for (var i = 0; i < 120; i++) {
              if (predicate()) { return; }
              await sleep(50);
            }
            throw new Error("timed out waiting for " + label);
          }
          async function loadMode(mode, markdown) {
            if (!window.__ouroEditor || window.__ouroEditor.vditor.currentMode !== mode) {
              window.ouro.setMode(mode);
              await waitFor(function () {
                return window.__ouroEditor && window.__ouroEditor.vditor.currentMode === mode;
              }, "mode " + mode);
            }
            window.ouro.setValue(markdown);
            await sleep(700);
          }
          function targetFor(node) {
            return node && (node.querySelector(".vditor-ir__link") || node.querySelector("span:not(.vditor-ir__marker)") || node);
          }
          function exportHeadingIDs(html) {
            var parsed = new DOMParser().parseFromString(html || "", "text/html");
            return Array.from(parsed.querySelectorAll("h1,h2,h3,h4,h5,h6")).map(function (heading) {
              return heading.id || "";
            });
          }
          function hasSharedHeadingIDs(html) {
            var ids = exportHeadingIDs(html);
            return ids.indexOf("link-contract-fixture") !== -1 &&
              ids.indexOf("target-heading") !== -1 &&
              ids.indexOf("duplicate-heading") !== -1 &&
              ids.indexOf("duplicate-heading-1") !== -1;
          }
          function nonHeadingIDs(html) {
            var parsed = new DOMParser().parseFromString(html || "", "text/html");
            return Array.from(parsed.querySelectorAll("[id]"))
              .filter(function (node) { return !/^H[1-6]$/.test(node.tagName || ""); })
              .map(function (node) { return node.id; })
              .sort();
          }
          try {
            var markdown = \(js(markdown));
            var originalURL = location.href;
            await loadMode("ir", markdown);

            var refs = Array.from(document.querySelectorAll('#editor span[data-type="link-ref"]'));
            var unresolved = (document.querySelector("#editor")?.innerText || "").indexOf("[Missing][not-defined]") !== -1;
            var firstLabel = targetFor(refs[0]);
            if (firstLabel && firstLabel.firstChild) {
              var range = document.createRange();
              range.selectNodeContents(firstLabel);
              range.collapse(false);
              var selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              document.dispatchEvent(new Event("selectionchange", { bubbles: true }));
              await sleep(250);
            }
            if (refs[0]) { refs[0].classList.add("vditor-ir__node--expand"); }
            var markers = refs[0] ? Array.from(refs[0].querySelectorAll(".vditor-ir__marker")) : [];
            var markersHidden = markers.length > 0 && markers.every(function (marker) {
              var style = getComputedStyle(marker);
              return style.display === "none" || (parseFloat(style.width) === 0 && parseFloat(style.height) === 0);
            });
            var refStyle = refs[0] ? getComputedStyle(refs[0]) : null;
            var linkAffordance = !!refStyle && (refStyle.cursor === "pointer" || refStyle.textDecorationLine.indexOf("underline") !== -1);

            if (refs[0]) {
              targetFor(refs[0]).dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, metaKey: true }));
            }
            await sleep(800);
            if (refs[1]) {
              targetFor(refs[1]).dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
            }
            await sleep(800);
            if (refs[2]) {
              targetFor(refs[2]).dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, metaKey: true }));
            }
            await sleep(800);
            if (refs[3]) {
              targetFor(refs[3]).dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, metaKey: true }));
            }
            await sleep(800);
            if (refs[5]) {
              targetFor(refs[5]).dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, metaKey: true }));
            }
            await sleep(300);

            var inlineAnchors = Array.from(document.querySelectorAll('#editor span[data-type="a"]'));
            var jump = inlineAnchors.find(function (node) {
              return (node.textContent || "").indexOf("#target-heading") !== -1;
            });
            var heading = Array.from(document.querySelectorAll("#editor h2")).find(function (node) {
              return (node.textContent || "").indexOf("Target Heading") !== -1;
            });
            if (heading) { heading.style.marginTop = "1600px"; }
            window.scrollTo(0, 0);
            await sleep(50);
            var irBefore = heading ? heading.getBoundingClientRect().top : 0;
            if (jump) {
              targetFor(jump).dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
            }
            await sleep(350);
            var irAfter = heading ? heading.getBoundingClientRect().top : 0;

            var irHTML = window.ouro.getHTML();
            var rawValue = window.__ouroEditor.getValue();
            var bridgeValue = window.ouro.getValue();

            await loadMode("sv", markdown);
            var sourcePane = document.querySelector("#editor .vditor-sv");
            var previewPane = document.querySelector("#editor .vditor-preview");
            var previewReference = previewPane && previewPane.querySelector('a[href="https://example.com/external"]');
            var previewJump = previewPane && previewPane.querySelector('a[href="#target-heading"]');
            var previewHeading = previewPane && Array.from(previewPane.querySelectorAll("h2")).find(function (node) {
              return (node.textContent || "").indexOf("Target Heading") !== -1;
            });
            if (previewHeading) { previewHeading.style.marginTop = "1600px"; }
            if (previewPane) { previewPane.scrollTop = 0; }
            await sleep(50);
            var svBefore = previewHeading ? previewHeading.getBoundingClientRect().top : 0;
            if (previewJump) {
              previewJump.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
            }
            await sleep(350);
            var svAfter = previewHeading ? previewHeading.getBoundingClientRect().top : 0;
            var svHTML = window.ouro.getHTML();

            post({
              irReferenceCount: refs.length,
              irUnresolvedPlain: unresolved,
              irMarkersHidden: markersHidden,
              irLinkAffordance: linkAffordance,
              irAnchorScrolled: !!heading && irAfter < irBefore - 100,
              svSourceLiteral: !!sourcePane && (sourcePane.innerText || "").indexOf("[External full][external]") !== -1,
              svReferenceRendered: !!previewReference,
              svAnchorScrolled: !!previewHeading && svAfter < svBefore - 100,
              svPreviewJumpFound: !!previewJump,
              svPreviewHeadingFound: !!previewHeading,
              svBefore: svBefore,
              svAfter: svAfter,
              svPreviewScrollTop: previewPane ? previewPane.scrollTop : -1,
              pageURLStable: location.href === originalURL,
              rawEqualsBridge: rawValue === bridgeValue,
              irExportAnchors: hasSharedHeadingIDs(irHTML),
              svExportAnchors: hasSharedHeadingIDs(svHTML),
              nonHeadingIDsStable: JSON.stringify(nonHeadingIDs(irHTML)) === JSON.stringify(nonHeadingIDs(svHTML)),
              irHTML: irHTML,
              svHTML: svHTML
            });
          } catch (error) {
            post({ error: error && (error.stack || error.message) ? (error.stack || error.message) : String(error) });
          }
        })();
        undefined;
        """
    }

    private static let legacyScript = """
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
                if (foundExternal) {
                  externalTarget.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, metaKey: true }));
                }
                setTimeout(function () {
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

    private static func js(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
