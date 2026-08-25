import AppKit
import WebKit

/// Headless `--linktest`: verifies link rendering, gestures, and fragment
/// navigation against the real bundled Vditor surface.
final class LinkTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let markdown: String?
    private let inputError: Error?
    private let artifactDirectory: URL?
    private let anchorContractJSON: String?
    private let requestedMode: String
    private var webView: WKWebView!
    private var window: NSWindow!
    private var openedURLs: [String] = []
    private var didStart = false
    private var didFinishNavigation = false
    private var didReceiveReady = false
    private var lastPhase = "not started"

    init(markdownPath: String? = nil, artifactDirectoryPath: String? = nil, requestedMode: String? = nil) {
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
        if let contractURL = OuroResources.web("heading-anchor-contract", "json") {
            anchorContractJSON = try? String(contentsOf: contractURL, encoding: .utf8)
        } else {
            anchorContractJSON = nil
        }
        self.requestedMode = requestedMode == "sv" ? "sv" : "ir"
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
        case "linkphase":
            lastPhase = body["name"] as? String ?? "unnamed link phase"
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
            source = Self.extendedScript(
                markdown,
                anchorContractJSON: anchorContractJSON,
                requestedMode: requestedMode
            )
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
        var checks: [(String, String, Bool)]

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
            let referenceDestinations = body["referenceDestinations"] as? [String] ?? []
            checks = [("linktest script completed", scriptError ?? "ok", scriptError == nil)]
            if requestedMode == "ir" {
                checks += [
                ("IR resolved reference nodes rendered", "\(body["irReferenceCount"] ?? "nil")", (body["irReferenceCount"] as? Int ?? 0) >= 16),
                ("IR unresolved reference stays source text", "\(body["irUnresolvedPlain"] ?? "nil")", body["irUnresolvedPlain"] as? Bool ?? false),
                ("IR focused reference markers hidden", "\(body["irMarkersHidden"] ?? "nil")", body["irMarkersHidden"] as? Bool ?? false),
                ("IR reference has link affordance", "\(body["irLinkAffordance"] ?? "nil")", body["irLinkAffordance"] as? Bool ?? false),
                ("external reference opens on Command-mousedown", "opened=\(openedURLs)", openedURLs.contains("https://example.com/external")),
                ("local reference opens in app", "opened=\(openedURLs)", openedURLs.contains("other.md#target-heading")),
                ("collapsed reference resolves", "opened=\(openedURLs)", openedURLs.contains("https://example.com/collapsed")),
                ("shortcut reference resolves", "opened=\(openedURLs)", openedURLs.contains("https://example.com/shortcut")),
                ("normalized label resolves", "opened=\(openedURLs)", openedURLs.contains("https://example.com/normalized")),
                ("ASCII-space label resolves", "opened=\(openedURLs)", openedURLs.contains("https://example.com/ascii-space")),
                ("NBSP label remains distinct", "opened=\(openedURLs)", openedURLs.contains("https://example.com/nbsp")),
                ("duplicate reference definition uses first destination", "projected=\(referenceDestinations)", referenceDestinations.contains("https://example.com/duplicate-first") && !referenceDestinations.contains("https://example.com/duplicate-second")),
                ("escaped reference label resolves", "projected=\(referenceDestinations)", referenceDestinations.contains("https://example.com/escaped-label")),
                ("Unicode case-folded reference label resolves", "projected=\(referenceDestinations)", referenceDestinations.contains("https://example.com/unicode-fold")),
                ("dotless i remains distinct under Unicode case folding", "projected=\(referenceDestinations)", referenceDestinations.contains("https://example.com/latin-i") && referenceDestinations.contains("https://example.com/dotless-i")),
                ("image-labelled reference resolves", "\(body["imageReferenceProjected"] ?? "nil")", body["imageReferenceProjected"] as? Bool ?? false),
                ("IR fragment scrolls", "\(body["irAnchorScrolled"] ?? "nil")", body["irAnchorScrolled"] as? Bool ?? false),
                ("IR linked heading uses semantic slug", "\(body["irLinkedHeadingAnchor"] ?? "nil")", body["irLinkedHeadingAnchor"] as? Bool ?? false),
                ]
            } else {
                checks += [
                ("SV source remains literal", "\(body["svSourceLiteral"] ?? "nil")", body["svSourceLiteral"] as? Bool ?? false),
                ("SV preview resolves reference", "\(body["svReferenceRendered"] ?? "nil")", body["svReferenceRendered"] as? Bool ?? false),
                ("SV fragment scrolls", "\(body["svAnchorScrolled"] ?? "nil")", body["svAnchorScrolled"] as? Bool ?? false),
                ("SV footnote anchor remains below sticky toolbar", "\(body["svFootnoteVisible"] ?? "nil")", body["svFootnoteVisible"] as? Bool ?? false),
                ]
            }
            checks += [
                ("fragment navigation keeps editor URL stable", "\(body["pageURLStable"] ?? "nil")", body["pageURLStable"] as? Bool ?? false),
                ("app export uses shared heading IDs", "\(body["modeExportAnchors"] ?? "nil")", body["modeExportAnchors"] as? Bool ?? false),
                ("app export preserves non-heading IDs", "\(body["nonHeadingIDsStable"] ?? "nil")", body["nonHeadingIDsStable"] as? Bool ?? false),
                ("app export IDs remain globally unique", "\(body["appExportIDsUnique"] ?? "nil")", body["appExportIDsUnique"] as? Bool ?? false),
                ("footnote collision namespace matches across exports", "\(body["footnoteCollisionParity"] ?? "nil")", body["footnoteCollisionParity"] as? Bool ?? false),
                ("footnote reservation parser matches standalone export", "\(body["footnoteReservationContract"] ?? "nil")", body["footnoteReservationContract"] as? Bool ?? false),
                ("JavaScript heading slugger matches shared contract", "\(body["anchorContractMatches"] ?? "nil")", body["anchorContractMatches"] as? Bool ?? false),
                ("HTML heading scanner preserves raw text and quoted attributes", "\(body["htmlScannerSafe"] ?? "nil")", body["htmlScannerSafe"] as? Bool ?? false),
                ("HTML heading scanner resumes after self-closing SVG script", "\(body["svgScriptScannerSafe"] ?? "nil")", body["svgScriptScannerSafe"] as? Bool ?? false),
                ("HTML heading scanner resumes after self-closing SVG style", "\(body["svgStyleScannerSafe"] ?? "nil")", body["svgStyleScannerSafe"] as? Bool ?? false),
                ("HTML heading scanner resumes after self-closing SVG title", "\(body["svgTitleScannerSafe"] ?? "nil")", body["svgTitleScannerSafe"] as? Bool ?? false),
                ("HTML heading scanner reserves foreign element IDs", "\(body["svgHeadingScannerSafe"] ?? "nil")", body["svgHeadingScannerSafe"] as? Bool ?? false),
                ("HTML heading scanner honors SVG and MathML integration points", "\(body["htmlIntegrationScannerSafe"] ?? "nil")", body["htmlIntegrationScannerSafe"] as? Bool ?? false),
                ("HTML heading scanner matches foreign namespaces and malformed attributes", "\(body["htmlTokenizerEdgeCasesSafe"] ?? "nil")", body["htmlTokenizerEdgeCasesSafe"] as? Bool ?? false),
                ("HTML heading scanner tracks integration-point descendants", "\(body["htmlCurrentNodeScannerSafe"] ?? "nil")", body["htmlCurrentNodeScannerSafe"] as? Bool ?? false),
                ("anchor retries cancel when document content changes", "\(body["anchorRetryCancelled"] ?? "nil")", body["anchorRetryCancelled"] as? Bool ?? false),
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

    private static func extendedScript(
        _ markdown: String,
        anchorContractJSON: String?,
        requestedMode: String
    ) -> String {
        """
        (async function () {
          function post(payload) {
            window.webkit.messageHandlers.ouro.postMessage(Object.assign({ type: "linkprobe" }, payload));
          }
          function phase(name) {
            window.webkit.messageHandlers.ouro.postMessage({ type: "linkphase", name: name });
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
              ids.indexOf("duplicate-heading-1") !== -1 &&
              ids.indexOf("docs-heading") !== -1;
          }
          function nonHeadingIDs(html) {
            var parsed = new DOMParser().parseFromString(html || "", "text/html");
            return Array.from(parsed.querySelectorAll("[id]"))
              .filter(function (node) { return !/^H[1-6]$/.test(node.tagName || ""); })
              .map(function (node) { return node.id; })
              .sort();
          }
          function allIDsUnique(html) {
            var parsed = new DOMParser().parseFromString(html || "", "text/html");
            var ids = Array.from(parsed.querySelectorAll("[id]")).map(function (node) { return node.id; });
            return new Set(ids).size === ids.length;
          }
          function footnoteCollisionIDsPresent(html) {
            var ids = exportHeadingIDs(html);
            return ["footnotes-def-1-1", "footnotes-def-2", "footnotes-ref-1-1", "footnotes-ref-1-2", "fn-note-1", "fnref-note-1"].every(function (id) {
              return ids.indexOf(id) !== -1;
            });
          }
          try {
            window.__ouroCaptureAnchorDiagnostics = true;
            var requestedMode = \(js(requestedMode));
            phase("extended: initializing " + requestedMode);
            var markdown = \(js(markdown));
            var anchorContract = JSON.parse(\(js(anchorContractJSON ?? "{\"cases\":[]}")));
            var expectedAnchorIDs = anchorContract.cases.map(function (item) { return item.expected; });
            var scannerSample = '<script>const sample = "<h1>";</script/><!-- <h2> --><svg><![CDATA[<h1>CDATA fake</h1>]]></svg><script/><h1>Script fake</h1></script><template/><h2>Template fake</h2></template><h1-widget>Custom element</h1-widget><h1 data-note=" id=\\'sentinel\\'">Raw Heading</h1>';
            var scannerNormalized = window.__ouroAnchorTest.normalizeHTML(scannerSample);
            var svgScriptScanner = window.__ouroAnchorTest.normalizeHTML('<svg><script /></svg><h1>SVG Script Follower</h1>');
            var svgStyleScanner = window.__ouroAnchorTest.normalizeHTML('<svg><style /></svg><h1>SVG Style Follower</h1>');
            var svgTitleScanner = window.__ouroAnchorTest.normalizeHTML('<svg><title /></svg><h1>SVG Title Follower</h1>');
            var svgHeadingScanner = window.__ouroAnchorTest.normalizeHTML('<svg><g id="svg-heading">SVG fake</g></svg><h2>SVG Heading</h2>');
            var integrationScannerSamples = [
              '<svg><desc><script /></desc></svg><h1>Fake</h1></script><h1>Real</h1>',
              '<svg><title><script /></title></svg><h1>Fake</h1></script><h1>Real</h1>',
              '<math><mtext><script /></mtext></math><h1>Fake</h1></script><h1>Real</h1>'
            ];
            var htmlIntegrationScannerSafe = integrationScannerSamples.every(function (sample) {
              return window.__ouroAnchorTest.normalizeHTML(sample).indexOf(
                '<h1>Fake</h1></script><h1 id="real">Real</h1>'
              ) !== -1;
            });
            var namespaceScannerSamples = [
              '<svg><mtext><textarea><h1>Fake</h1></textarea></mtext></svg><h1>Real</h1>',
              '<math><desc><textarea><h1>Fake</h1></textarea></desc></math><h1>Real</h1>'
            ];
            var namespaceScannerSafe = namespaceScannerSamples.every(function (sample) {
              var normalized = window.__ouroAnchorTest.normalizeHTML(sample);
              return normalized.indexOf('<h1 id="fake">Fake</h1>') !== -1 &&
                normalized.indexOf('<h1 id="real">Real</h1>') !== -1;
            });
            var fontScanner = window.__ouroAnchorTest.normalizeHTML(
              '<svg><font color=x><textarea><h1>Fake</h1></textarea></font></svg><h1>Real</h1>'
            );
            var annotationScanner = window.__ouroAnchorTest.normalizeHTML(
              '<math><annotation-xml encoding="text&#x2F;html"><textarea><h1>Fake</h1></textarea></annotation-xml></math><h1>Real</h1>'
            );
            var malformedAttributeScanner = window.__ouroAnchorTest.normalizeHTML(
              '<h1 data=x">Alpha</h1><h2>Beta</h2>'
            );
            var foreignEndScanner = window.__ouroAnchorTest.normalizeHTML(
              '<h1>Alpha<svg></h2>tail'
            );
            var htmlTokenizerEdgeCasesSafe = namespaceScannerSafe &&
              fontScanner.indexOf('<h1>Fake</h1></textarea>') !== -1 &&
              fontScanner.indexOf('<h1 id="real">Real</h1>') !== -1 &&
              annotationScanner.indexOf('<h1>Fake</h1></textarea>') !== -1 &&
              annotationScanner.indexOf('<h1 id="real">Real</h1>') !== -1 &&
              malformedAttributeScanner.indexOf('<h1 data=x" id="alpha">') !== -1 &&
              malformedAttributeScanner.indexOf('<h2 id="beta">') !== -1 &&
              foreignEndScanner.indexOf('<h1 id="alpha">Alpha<svg></h2>tail') !== -1;
            var mathDescendantScanner = window.__ouroAnchorTest.normalizeHTML(
              '<math><mtext><div><mglyph><textarea><h1>Same</h1></textarea></mglyph></div></mtext></math><h1>Same</h1>'
            );
            var svgTitleSemanticScanner = window.__ouroAnchorTest.normalizeHTML(
              '<h1><svg><title><span>Text</span></title></svg>After</h1>'
            );
            var htmlCurrentNodeScannerSafe =
              mathDescendantScanner.indexOf('<h1>Same</h1></textarea>') !== -1 &&
              mathDescendantScanner.indexOf('<h1 id="same">Same</h1>') !== -1 &&
              svgTitleSemanticScanner.indexOf('<h1 id="textafter">') !== -1;
            var footnoteReservationSample = "First[^A B] second[^A B].\\n`[^A B]` \\\\[^A B]\\n```\\n[^fake]: Fake\\n[^fake]\\n```\\n    [^indented]: Fake\\n\\n[^A B]: First\\n[^a-b]: Second";
            var footnoteReservations = window.__ouroAnchorTest.footnoteReservations(footnoteReservationSample);
            var expectedFootnoteReservations = [
              "fn-a-b", "footnotes-def-1", "fnref-a-b", "footnotes-ref-1",
              "fnref-a-b-2", "footnotes-ref-1:2", "fn-a-b-1",
              "footnotes-def-2", "fnref-a-b-1", "footnotes-ref-2"
            ];
            var footnoteReservationContract = expectedFootnoteReservations.every(function (id) {
              return footnoteReservations.indexOf(id) !== -1;
            }) && ["fn-fake", "fn-indented"].every(function (id) {
              return footnoteReservations.indexOf(id) === -1;
            });
            var originalURL = location.href;

            if (requestedMode === "sv") {
              await loadMode("sv", markdown);
              phase("extended: SV loaded");
              var sourcePaneOnly = document.querySelector("#editor .vditor-sv");
              var previewPaneOnly = document.querySelector("#editor .vditor-preview");
              var previewReferenceOnly = previewPaneOnly && previewPaneOnly.querySelector('a[href="https://example.com/external"]');
              var previewJumpOnly = previewPaneOnly && previewPaneOnly.querySelector('a[href="#target-heading"]');
              var previewHeadingOnly = previewPaneOnly && Array.from(previewPaneOnly.querySelectorAll("h2")).find(function (node) {
                return (node.textContent || "").indexOf("Target Heading") !== -1;
              });
              var svAnchorCallOnly = window.ouro.scrollToAnchor("target-heading");
              var svAnchorScrolledOnly = svAnchorCallOnly && window.__ouroLastAnchor === "target-heading";
              var footnoteLinkOnly = previewPaneOnly && previewPaneOnly.querySelector('a[href="#footnotes-def-1"]');
              var svFootnoteCallOnly = window.ouro.scrollToAnchor("footnotes-def-1");
              var svFootnoteVisibleOnly = !!footnoteLinkOnly && svFootnoteCallOnly &&
                window.__ouroLastAnchor === "footnotes-def-1";
              var svRawHTMLOnly = window.__ouroEditor.getHTML();
              var svHTMLOnly = window.__ouroAnchorTest.normalizeHTML(svRawHTMLOnly);
              var footnoteCollisionSampleOnly = '<h2>footnotes-def-1</h2><h2>footnotes-def-2</h2><h2>footnotes-ref-1</h2><h2>footnotes-ref-1-2</h2><h2>fn-note</h2><h2>fnref-note</h2><li id="footnotes-def-1"></li><sup id="footnotes-ref-1"></sup>';
              var normalizedFootnoteCollisionOnly = window.__ouroAnchorTest.normalizeHTML(footnoteCollisionSampleOnly);
              var generationBeforeOnly = window.__ouroAnchorTest.anchorGeneration();
              window.ouro.scrollToAnchorWhenReady("missing-generation-anchor");
              var generationRequestedOnly = window.__ouroAnchorTest.anchorGeneration();
              window.ouro.setValue(markdown);
              var generationAfterReplaceOnly = window.__ouroAnchorTest.anchorGeneration();
              post({
                svSourceLiteral: !!sourcePaneOnly && (sourcePaneOnly.innerText || "").indexOf("[External full][external]") !== -1,
                svReferenceRendered: !!previewReferenceOnly,
                svAnchorScrolled: !!previewHeadingOnly && svAnchorScrolledOnly,
                svFootnoteVisible: svFootnoteVisibleOnly,
                pageURLStable: location.href === originalURL,
                modeExportAnchors: hasSharedHeadingIDs(svHTMLOnly),
                nonHeadingIDsStable: JSON.stringify(nonHeadingIDs(svRawHTMLOnly)) === JSON.stringify(nonHeadingIDs(svHTMLOnly)),
                appExportIDsUnique: allIDsUnique(svHTMLOnly),
                footnoteCollisionParity: footnoteCollisionIDsPresent(normalizedFootnoteCollisionOnly),
                footnoteReservationContract: footnoteReservationContract,
                anchorContractMatches: !!window.__ouroAnchorTest &&
                  JSON.stringify(window.__ouroAnchorTest.slugs(anchorContract.cases.map(function (item) { return item.text; }))) ===
                  JSON.stringify(anchorContract.cases.map(function (item) { return item.expected; })),
                htmlScannerSafe: scannerNormalized.indexOf('<script>const sample = "<h1>";</script/>') !== -1 &&
                  scannerNormalized.indexOf('<!-- <h2> -->') !== -1 &&
                  scannerNormalized.indexOf('<svg><![CDATA[<h1>CDATA fake</h1>]]></svg>') !== -1 &&
                  scannerNormalized.indexOf('<script/><h1>Script fake</h1></script>') !== -1 &&
                  scannerNormalized.indexOf('<template/><h2>Template fake</h2></template>') !== -1 &&
                  scannerNormalized.indexOf('<h1-widget>Custom element</h1-widget>') !== -1 &&
                  scannerNormalized.indexOf('<h1 data-note=" id=\\'sentinel\\'" id="raw-heading">') !== -1,
                 svgScriptScannerSafe: svgScriptScanner.indexOf('<svg><script /></svg><h1 id="svg-script-follower">') !== -1,
                 svgStyleScannerSafe: svgStyleScanner.indexOf('<svg><style /></svg><h1 id="svg-style-follower">') !== -1,
                 svgTitleScannerSafe: svgTitleScanner.indexOf('<svg><title /></svg><h1 id="svg-title-follower">') !== -1,
                 svgHeadingScannerSafe: svgHeadingScanner.indexOf('<svg><g id="svg-heading">SVG fake</g></svg><h2 id="svg-heading-1">') !== -1,
                 htmlIntegrationScannerSafe: htmlIntegrationScannerSafe,
                 htmlTokenizerEdgeCasesSafe: htmlTokenizerEdgeCasesSafe,
                 htmlCurrentNodeScannerSafe: htmlCurrentNodeScannerSafe,
                anchorRetryCancelled: generationRequestedOnly > generationBeforeOnly &&
                  generationAfterReplaceOnly > generationRequestedOnly,
                svHTML: svHTMLOnly
              });
              return;
            }

            phase("extended: loading IR");
            await loadMode("ir", markdown);
            phase("extended: IR loaded");

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
            phase("extended: IR references captured");
            phase("extended: reference projection starting");
            var projectedReferences = window.__ouroAnchorTest.referenceDestinations();
            phase("extended: reference projection complete " + JSON.stringify(projectedReferences));
            phase("extended: IR raw export starting");
            var irRawHTML = window.__ouroEditor.getHTML();
            phase("extended: IR raw export complete");
            var irHTML = window.__ouroAnchorTest.normalizeHTML(irRawHTML);
            phase("extended: IR normalization complete");
            var footnoteCollisionSample = '<h2>footnotes-def-1</h2><h2>footnotes-def-2</h2><h2>footnotes-ref-1</h2><h2>footnotes-ref-1-2</h2><h2>fn-note</h2><h2>fnref-note</h2><li id="footnotes-def-1"></li><sup id="footnotes-ref-1"></sup>';
            var normalizedFootnoteCollision = window.__ouroAnchorTest.normalizeHTML(footnoteCollisionSample);

            if (refs[0]) {
              phase("extended: first reference gesture starting");
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
            await sleep(800);
            if (refs[6]) {
              targetFor(refs[6]).dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, metaKey: true }));
            }
            await sleep(800);
            if (refs[7]) {
              targetFor(refs[7]).dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, metaKey: true }));
            }
            await sleep(300);
            phase("extended: reference gestures complete");

            phase("extended: locating IR anchor");
            var inlineAnchors = Array.from(document.querySelectorAll('#editor span[data-type="a"]'));
            var jump = inlineAnchors.find(function (node) {
              return (node.textContent || "").indexOf("#target-heading") !== -1;
            });
            var heading = Array.from(document.querySelectorAll("#editor h2")).find(function (node) {
              return (node.textContent || "").indexOf("Target Heading") !== -1;
            });
            phase("extended: IR anchor located");
            var irAnchorCall = window.ouro.scrollToAnchor("target-heading");
            phase("extended: IR inline anchor complete");
            var irAnchorScrolled = irAnchorCall && window.__ouroLastAnchor === "target-heading";
            phase("extended: IR linked anchor starting");
            var irLinkedHeadingAnchor = window.ouro.scrollToAnchor("docs-heading");
            phase("extended: IR linked anchor complete");

            window.getSelection().removeAllRanges();
            if (refs[0]) { refs[0].classList.remove("vditor-ir__node--expand"); }
            var generationBefore = window.__ouroAnchorTest.anchorGeneration();
            window.ouro.scrollToAnchorWhenReady("missing-generation-anchor");
            var generationRequested = window.__ouroAnchorTest.anchorGeneration();
            window.ouro.setValue(markdown);
            var generationAfterReplace = window.__ouroAnchorTest.anchorGeneration();

            phase("extended: posting result");
            post({
              irReferenceCount: refs.length,
              irUnresolvedPlain: unresolved,
              irMarkersHidden: markersHidden,
              irLinkAffordance: linkAffordance,
              irAnchorScrolled: !!heading && irAnchorScrolled,
              irLinkedHeadingAnchor: irLinkedHeadingAnchor,
              pageURLStable: location.href === originalURL,
              modeExportAnchors: hasSharedHeadingIDs(irHTML),
              nonHeadingIDsStable: JSON.stringify(nonHeadingIDs(irRawHTML)) === JSON.stringify(nonHeadingIDs(irHTML)),
              appExportIDsUnique: allIDsUnique(irHTML),
              footnoteCollisionParity: footnoteCollisionIDsPresent(normalizedFootnoteCollision),
              footnoteReservationContract: footnoteReservationContract,
              anchorContractMatches: !!window.__ouroAnchorTest &&
                JSON.stringify(window.__ouroAnchorTest.slugs(anchorContract.cases.map(function (item) { return item.text; }))) ===
                JSON.stringify(anchorContract.cases.map(function (item) { return item.expected; })),
              htmlScannerSafe: scannerNormalized.indexOf('<script>const sample = "<h1>";</script/>') !== -1 &&
                scannerNormalized.indexOf('<!-- <h2> -->') !== -1 &&
                scannerNormalized.indexOf('<svg><![CDATA[<h1>CDATA fake</h1>]]></svg>') !== -1 &&
                scannerNormalized.indexOf('<script/><h1>Script fake</h1></script>') !== -1 &&
                scannerNormalized.indexOf('<template/><h2>Template fake</h2></template>') !== -1 &&
                scannerNormalized.indexOf('<h1-widget>Custom element</h1-widget>') !== -1 &&
                scannerNormalized.indexOf('<h1 data-note=" id=\\'sentinel\\'" id="raw-heading">') !== -1,
               svgScriptScannerSafe: svgScriptScanner.indexOf('<svg><script /></svg><h1 id="svg-script-follower">') !== -1,
               svgStyleScannerSafe: svgStyleScanner.indexOf('<svg><style /></svg><h1 id="svg-style-follower">') !== -1,
               svgTitleScannerSafe: svgTitleScanner.indexOf('<svg><title /></svg><h1 id="svg-title-follower">') !== -1,
               svgHeadingScannerSafe: svgHeadingScanner.indexOf('<svg><g id="svg-heading">SVG fake</g></svg><h2 id="svg-heading-1">') !== -1,
               htmlIntegrationScannerSafe: htmlIntegrationScannerSafe,
               htmlTokenizerEdgeCasesSafe: htmlTokenizerEdgeCasesSafe,
               htmlCurrentNodeScannerSafe: htmlCurrentNodeScannerSafe,
              anchorRetryCancelled: generationRequested > generationBefore &&
                generationAfterReplace > generationRequested,
              referenceDestinations: window.__ouroAnchorTest.referenceDestinations(),
              referenceError: window.__ouroAnchorTest.referenceError(),
              imageReferenceProjected: projectedReferences.indexOf("https://example.com/image-reference") !== -1,
              irHTML: irHTML
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
