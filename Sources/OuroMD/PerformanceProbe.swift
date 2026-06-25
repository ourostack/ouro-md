import AppKit
import Darwin
import WebKit

/// Headless `--performanceprobe`: exercises the live editor with a generated
/// large Markdown document, then measures folder search on a many-file fixture.
/// The thresholds are intentionally loose enough for CI variance but tight
/// enough to catch runaway editor/search regressions.
@MainActor
final class PerformanceProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private var root: URL!
    private let rssBefore = residentMemoryBytes()

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()
        prepareSearchFixture()

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        webView.navigationDelegate = self
        window = HeadlessHarness.offscreenHost(webView, size: NSSize(width: 1200, height: 900))

        guard let indexURL = OuroResources.web("index", "html") else {
            fail("performanceprobe: index.html not found")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            self.fail("performanceprobe: timed out")
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }
        if type == "ready" {
            webView.evaluateJavaScript(Self.editorScript) { _, error in
                if let error {
                    self.fail("performanceprobe javascript failed to start: \(error.localizedDescription)")
                }
            }
        } else if type == "performanceprobe" {
            if let error = body["error"] as? String {
                fail("performanceprobe javascript error: \(error)")
            }
            measureFolderSearch(editorMetrics: body)
        }
    }

    private func prepareSearchFixture() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-performance-probe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<320 {
            let section = i % 16
            let hit = i % 3 == 0 ? " needle_token" : ""
            let body = """
            # Search Fixture \(i)

            Section \(section)\(hit) has ordinary prose, a path `Sources/OuroMD/File\(i).swift`, and enough context to exercise snippets.
            Another line keeps file \(i) realistic for folder search.
            """
            try? body.write(to: root.appendingPathComponent(String(format: "fixture-%03d.md", i)),
                            atomically: true,
                            encoding: .utf8)
        }
    }

    private func measureFolderSearch(editorMetrics: [String: Any]) {
        let searcher = ContentSearcher()
        let start = Date()
        var resultCount = 0
        var completion = SearchCompletion.empty
        searcher.search(
            "needle_token",
            in: root,
            caseSensitive: false,
            wholeWord: false,
            regexp: false,
            onResult: { _ in resultCount += 1 },
            onComplete: { [weak self] value in
                guard let self else { return }
                completion = value
                let searchMs = Date().timeIntervalSince(start) * 1000
                self.finish(editorMetrics: editorMetrics, searchMs: searchMs, resultCount: resultCount, completion: completion)
            }
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            searcher.cancel()
            self?.fail("performanceprobe: folder search timed out")
        }
    }

    private func finish(editorMetrics: [String: Any], searchMs: Double, resultCount: Int, completion: SearchCompletion) {
        let loadMs = double(editorMetrics["loadMs"])
        let editMs = double(editorMetrics["editMs"])
        let replaceMs = double(editorMetrics["replaceMs"])
        let clearMs = double(editorMetrics["clearMs"])
        let headings = int(editorMetrics["headings"])
        let tables = int(editorMetrics["tables"])
        let htmlLength = int(editorMetrics["htmlLength"])
        let valueLength = int(editorMetrics["valueLength"])
        let finalLength = int(editorMetrics["finalLength"])
        let rssAfter = Self.residentMemoryBytes()
        let rssDelta = rssAfter > rssBefore ? rssAfter - rssBefore : 0
        let rssMB = Double(rssAfter) / 1_048_576.0
        let rssDeltaMB = Double(rssDelta) / 1_048_576.0

        let loadLimit = envLimit("OURO_PERF_LARGE_DOC_LOAD_MS", default: 12_000)
        let editLimit = envLimit("OURO_PERF_EDIT_MS", default: 4_000)
        let replaceLimit = envLimit("OURO_PERF_REPLACE_MS", default: 4_000)
        let clearLimit = envLimit("OURO_PERF_CLEAR_MS", default: 4_000)
        let searchLimit = envLimit("OURO_PERF_SEARCH_MS", default: 6_000)
        let rssLimit = envLimit("OURO_PERF_RSS_MB", default: 1_200)
        let rssDeltaLimit = envLimit("OURO_PERF_RSS_DELTA_MB", default: 650)

        let largeDocRendered = (headings >= 70 && tables >= 18) || (htmlLength > 25_000 && valueLength > 30_000)
        let editorOK = loadMs < loadLimit
            && editMs < editLimit
            && replaceMs < replaceLimit
            && clearMs < clearLimit
            && largeDocRendered
            && finalLength < 1_000
        let searchOK = searchMs < searchLimit
            && resultCount >= 100
            && completion == .empty
        let memoryOK = rssMB < rssLimit && rssDeltaMB < rssDeltaLimit

        print(String(format: "large document load: %.1fms headings=%d tables=%d html=%d value=%d %@",
                     loadMs, headings, tables, htmlLength, valueLength, largeDocRendered && loadMs < loadLimit ? "✓" : "✗"))
        print(String(format: "large document edit latency: %.1fms %@", editMs, editMs < editLimit ? "✓" : "✗"))
        print(String(format: "large document replace latency: %.1fms %@", replaceMs, replaceMs < replaceLimit ? "✓" : "✗"))
        print(String(format: "large document clear latency: %.1fms %@", clearMs, clearMs < clearLimit ? "✓" : "✗"))
        print(String(format: "folder search latency: %.1fms results=%d %@",
                     searchMs, resultCount, searchOK ? "✓" : "✗"))
        print(String(format: "resident memory: %.1fMB delta=%.1fMB %@",
                     rssMB, rssDeltaMB, memoryOK ? "✓" : "✗"))

        cleanup()
        exit(editorOK && searchOK && memoryOK ? 0 : 1)
    }

    private func cleanup() {
        window?.orderOut(nil)
        try? FileManager.default.removeItem(at: root)
    }

    private func fail(_ message: String) -> Never {
        cleanup()
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return 0
    }

    private func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        return 0
    }

    private func envLimit(_ key: String, default value: Double) -> Double {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let parsed = Double(raw) else {
            return value
        }
        return parsed
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    private static let editorScript = #"""
    (function () {
      function now() { return performance.now ? performance.now() : Date.now(); }
      function waitUntil(predicate, timeoutMs) {
        var started = now();
        return new Promise(function (resolve) {
          function tick() {
            if (predicate()) { resolve(true); return; }
            if (now() - started > timeoutMs) { resolve(false); return; }
            requestAnimationFrame(tick);
          }
          tick();
        });
      }
      function largeDoc() {
        var parts = [];
        for (var i = 0; i < 80; i++) {
          parts.push("# Section " + i);
          parts.push("");
          parts.push("Paragraph " + i + " with needle_token, **bold**, `inline_code_" + i + "`, [a link](https://example.com/" + i + "), and enough prose to make wrapping and rendering realistic.");
          parts.push("");
          if (i % 4 === 0) {
            parts.push("| Artifact | Repository | Producer | Verification consumer |");
            parts.push("| --- | --- | --- | --- |");
            for (var r = 0; r < 4; r++) {
              parts.push("| `Sources/OuroMD/VeryLongPath/Generated/File" + i + "_" + r + ".swift` | ouro-md | Performance Probe | The live editor must keep table-local scroll without page overflow. |");
            }
            parts.push("");
          }
          if (i % 9 === 0) {
            parts.push("```swift");
            parts.push("let value" + i + " = \"needle_token\"");
            parts.push("```");
            parts.push("");
          }
        }
        return parts.join("\n");
      }
      function activeRoot() {
        return document.querySelector("#editor .vditor-reset") || document.getElementById("editor") || document.body;
      }
      function collect() {
        var root = activeRoot();
          return {
            headings: root.querySelectorAll("h1,h2,h3,h4,h5,h6").length,
            tables: root.querySelectorAll("table").length,
            htmlLength: (window.ouro.getHTML() || "").length,
            valueLength: (window.ouro.getValue() || "").length
          };
      }
      async function run() {
        var doc = largeDoc();
        var loadStart = now();
        window.ouro.setValue(doc);
        await waitUntil(function () {
          var s = collect();
          return (s.headings >= 70 && s.tables >= 18) || s.htmlLength > 25000;
        }, 12000);
        var loadMs = now() - loadStart;
        var stats = collect();

        window.ouro.focus();
        var editStart = now();
        if (window.__ouroEditor && window.__ouroEditor.insertValue) {
          window.__ouroEditor.insertValue("\nPERF_EDIT_TOKEN\n");
        } else {
          window.ouro.setValue(window.ouro.getValue() + "\nPERF_EDIT_TOKEN\n");
        }
        await waitUntil(function () { return window.ouro.getValue().indexOf("PERF_EDIT_TOKEN") !== -1; }, 4000);
        var editMs = now() - editStart;

        var replaceStart = now();
        window.ouro.replaceAll("needle_token", "needle_done", { caseSensitive: false, wholeWord: false, regexp: false }, true);
        await waitUntil(function () { return window.ouro.getValue().indexOf("needle_done") !== -1; }, 4000);
        var replaceMs = now() - replaceStart;

        var clearStart = now();
        window.ouro.setValue("# Cleared\n");
        await waitUntil(function () { return window.ouro.getValue().length < 20; }, 4000);
        var clearMs = now() - clearStart;

        window.webkit.messageHandlers.ouro.postMessage({
          type: "performanceprobe",
          loadMs: loadMs,
          editMs: editMs,
          replaceMs: replaceMs,
          clearMs: clearMs,
          headings: stats.headings,
          tables: stats.tables,
          htmlLength: stats.htmlLength,
          valueLength: stats.valueLength,
          finalLength: window.ouro.getValue().length
        });
      }
      run().catch(function (error) {
        window.webkit.messageHandlers.ouro.postMessage({
          type: "performanceprobe",
          error: String(error && (error.stack || error.message) || error)
        });
      });
    })();
    """#
}
