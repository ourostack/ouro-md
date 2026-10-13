import AppKit
import Darwin
import Foundation
import WebKit

/// Headless `--performanceprobe`: exercises the live editor with either the
/// default CI-sized Markdown workload or a caller-supplied Markdown file, then
/// measures folder search on a many-file fixture. Optional workload and web-root
/// overrides let local profiling compare exact resource revisions without
/// mutating the checked-in bundle.
@MainActor
final class PerformanceProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    struct Configuration {
        let markdownPath: String?
        let webRootPath: String?
    }

    private struct WorkloadSummary {
        let source: String
        let bytes: Int
        let chars: Int
        let lines: Int
        let headings: Int
        let pipeLines: Int
        let inlineLinks: Int
        let referenceDefinitions: Int

        var dictionary: [String: Any] {
            [
                "source": source,
                "bytes": bytes,
                "chars": chars,
                "lines": lines,
                "headings": headings,
                "pipeLines": pipeLines,
                "inlineLinks": inlineLinks,
                "referenceDefinitions": referenceDefinitions
            ]
        }
    }

    private let configuration: Configuration
    private var webView: WKWebView!
    private var window: NSWindow!
    private var searchFixtureRoot: URL!
    private var workloadMarkdown = ""
    private var workloadSummary = WorkloadSummary(source: "generated-default", bytes: 0, chars: 0, lines: 0, headings: 0, pipeLines: 0, inlineLinks: 0, referenceDefinitions: 0)
    private var lastProgress = "not started"
    private let rssBefore = residentMemoryBytes()

    init(markdownPath: String? = nil, webRootPath: String? = nil) {
        self.configuration = Configuration(markdownPath: markdownPath, webRootPath: webRootPath)
        super.init()
    }

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()
        do {
            try prepareWorkload()
            try prepareSearchFixture()
        } catch {
            fail("performanceprobe: \(error.localizedDescription)")
        }

        let webConfiguration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        controller.addUserScript(WKUserScript(source: Self.hookScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webConfiguration.userContentController = controller
        webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        webConfiguration.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: webConfiguration)
        webView.navigationDelegate = self
        window = HeadlessHarness.offscreenHost(webView, size: NSSize(width: 1200, height: 900))

        guard let indexURL = webIndexURL() else {
            fail("performanceprobe: index.html not found")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        let timeoutSeconds = configuration.markdownPath == nil ? 240.0 : 900.0
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
            self.fail("performanceprobe: timed out (\(self.lastProgress))")
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
            lastProgress = "editor ready"
            webView.callAsyncJavaScript(Self.editorScript, arguments: [
                "markdown": workloadMarkdown,
                "skipActualReload": ProcessInfo.processInfo.environment["OURO_PERF_SKIP_RELOAD"] == "1"
            ], in: nil, in: .page) { result in
                if case .failure(let error) = result {
                    self.fail("performanceprobe javascript failed to start: \(error.localizedDescription)")
                }
            }
        } else if type == "performanceprobe-progress" {
            let phase = body["phase"] as? String ?? "unknown"
            let detail = body["detail"] as? String ?? ""
            lastProgress = detail.isEmpty ? phase : "\(phase): \(detail)"
            print("progress: \(lastProgress)")
        } else if type == "performanceprobe" {
            if let error = body["error"] as? String {
                fail("performanceprobe javascript error: \(error)")
            }
            measureFolderSearch(editorMetrics: body)
        }
    }

    private func prepareWorkload() throws {
        if let markdownPath = configuration.markdownPath {
            let url = URL(fileURLWithPath: markdownPath)
            workloadMarkdown = try String(contentsOf: url, encoding: .utf8)
            workloadSummary = summarize(markdown: workloadMarkdown, source: url.path)
        } else {
            workloadMarkdown = Self.defaultMarkdown
            workloadSummary = summarize(markdown: workloadMarkdown, source: "generated-default")
        }
    }

    private func prepareSearchFixture() throws {
        let buildRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("ouro-performance-probe-search-fixture", isDirectory: true)
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }
        try FileManager.default.createDirectory(at: buildRoot, withIntermediateDirectories: true)
        searchFixtureRoot = buildRoot
        for i in 0..<320 {
            let section = i % 16
            let hit = i % 3 == 0 ? " needle_token" : ""
            let body = """
            # Search Fixture \(i)

            Section \(section)\(hit) has ordinary prose, a path `Sources/OuroMD/File\(i).swift`, and enough context to exercise snippets.
            Another line keeps file \(i) realistic for folder search.
            """
            try body.write(to: buildRoot.appendingPathComponent(String(format: "fixture-%03d.md", i)),
                           atomically: true,
                           encoding: .utf8)
        }
    }

    private func webIndexURL() -> URL? {
        if let webRootPath = configuration.webRootPath {
            let root = URL(fileURLWithPath: webRootPath, isDirectory: true)
            let indexURL = root.appendingPathComponent("index.html")
            return FileManager.default.fileExists(atPath: indexURL.path) ? indexURL : nil
        }
        return OuroResources.web("index", "html")
    }

    private func summarize(markdown: String, source: String) -> WorkloadSummary {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        let headings = markdown.split(whereSeparator: \.isNewline).filter { $0.first == "#" }.count
        let pipeLines = markdown.split(whereSeparator: \.isNewline).filter { $0.contains("|") }.count
        let referenceDefinitions = markdown.split(whereSeparator: \.isNewline).filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.contains("]: ")
        }.count
        return WorkloadSummary(
            source: source,
            bytes: markdown.lengthOfBytes(using: .utf8),
            chars: markdown.count,
            lines: lines,
            headings: headings,
            pipeLines: pipeLines,
            inlineLinks: markdown.components(separatedBy: "](").count - 1,
            referenceDefinitions: referenceDefinitions
        )
    }

    private func measureFolderSearch(editorMetrics: [String: Any]) {
        let searcher = ContentSearcher()
        let start = Date()
        var resultCount = 0
        var completion = SearchCompletion.empty
        searcher.search(
            "needle_token",
            in: searchFixtureRoot,
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
        let parseMedianMs = double(editorMetrics["parseMedianMs"])
        let openUsableMs = double(editorMetrics["openUsableMs"])
        let openSettledMs = double(editorMetrics["openSettledMs"])
        let scrollReadyTotalMs = double(editorMetrics["scrollReadyTotalMs"])
        let scrollSettledTotalMs = double(editorMetrics["scrollSettledTotalMs"])
        let scrollMaxStepMs = double(editorMetrics["scrollMaxStepMs"])
        let editReadyMs = double(editorMetrics["editReadyMs"])
        let editSettledMs = double(editorMetrics["editSettledMs"])
        let reloadReadyMs = double(editorMetrics["reloadReadyMs"])
        let reloadSettledMs = double(editorMetrics["reloadSettledMs"])
        let reloadMarks = int(editorMetrics["reloadMarks"])
        let finalLength = int(editorMetrics["finalLength"])
        let rendered = dictionary(editorMetrics["rendered"])
        let openEvents = dictionary(editorMetrics["openEvents"])
        let scrollEvents = dictionary(editorMetrics["scrollEvents"])
        let reloadEvents = dictionary(editorMetrics["reloadEvents"])
        let editEvents = dictionary(editorMetrics["editEvents"])

        let rssAfter = Self.residentMemoryBytes()
        let rssDelta = rssAfter > rssBefore ? rssAfter - rssBefore : 0
        let rssMB = Double(rssAfter) / 1_048_576.0
        let rssDeltaMB = Double(rssDelta) / 1_048_576.0

        let usingCustomWorkload = configuration.markdownPath != nil
        let openUsableLimit = envLimit("OURO_PERF_OPEN_USABLE_MS", default: usingCustomWorkload ? 10_000 : 12_000)
        let openSettledLimit = envLimit("OURO_PERF_OPEN_SETTLED_MS", default: usingCustomWorkload ? 18_000 : 12_000)
        let scrollLimit = envLimit("OURO_PERF_SCROLL_READY_TOTAL_MS", default: usingCustomWorkload ? 4_000 : 4_000)
        let editLimit = envLimit("OURO_PERF_EDIT_READY_MS", default: 1_500)
        let reloadLimit = envLimit("OURO_PERF_RELOAD_READY_MS", default: usingCustomWorkload ? 15_000 : 5_000)
        let searchLimit = envLimit("OURO_PERF_SEARCH_MS", default: 6_000)
        let rssLimit = envLimit("OURO_PERF_RSS_MB", default: 1_200)
        let rssDeltaLimit = envLimit("OURO_PERF_RSS_DELTA_MB", default: 650)

        let renderOK = openUsableMs < openUsableLimit && openSettledMs < openSettledLimit
        let reloadMeasured = reloadReadyMs >= 0
        let interactionOK = scrollReadyTotalMs < scrollLimit && editReadyMs < editLimit && (!reloadMeasured || reloadReadyMs < reloadLimit)
        let searchOK = searchMs < searchLimit && resultCount >= 100 && completion == .empty
        let memoryOK = rssMB < rssLimit && rssDeltaMB < rssDeltaLimit

        print("workload source: \(workloadSummary.source)")
        print("workload dimensions: bytes=\(workloadSummary.bytes) chars=\(workloadSummary.chars) lines=\(workloadSummary.lines) headings=\(workloadSummary.headings) pipeLines=\(workloadSummary.pipeLines) inlineLinks=\(workloadSummary.inlineLinks) referenceDefs=\(workloadSummary.referenceDefinitions)")
        print(String(format: "parse median: %.1fms", parseMedianMs))
        print(String(format: "open usable: %.1fms %@ | settled: %.1fms %@", openUsableMs, renderOK && openUsableMs < openUsableLimit ? "✓" : "✗", openSettledMs, renderOK && openSettledMs < openSettledLimit ? "✓" : "✗"))
        print("rendered surface: blocks=\(int(rendered["blockCount"])) headings=\(int(rendered["headings"])) tables=\(int(rendered["tables"])) links=\(int(rendered["links"])) text=\(int(rendered["textLength"])) scrollHeight=\(int(rendered["scrollHeight"]))")
        print(String(format: "scroll ready: %.1fms %@ | settled: %.1fms | max step: %.1fms", scrollReadyTotalMs, scrollReadyTotalMs < scrollLimit ? "✓" : "✗", scrollSettledTotalMs, scrollMaxStepMs))
        print(String(format: "typing ready: %.1fms %@ | settled: %.1fms", editReadyMs, editReadyMs < editLimit ? "✓" : "✗", editSettledMs))
        if reloadMeasured {
            print(String(format: "external reload ready: %.1fms %@ | settled: %.1fms | marks=%d", reloadReadyMs, reloadReadyMs < reloadLimit ? "✓" : "✗", reloadSettledMs, reloadMarks))
        } else {
            print("external reload: skipped by OURO_PERF_SKIP_RELOAD")
        }
        print("open hooks: \(format(eventSummary: openEvents))")
        print("scroll hooks: \(format(eventSummary: scrollEvents))")
        print("reload hooks: \(format(eventSummary: reloadEvents))")
        print("typing hooks: \(format(eventSummary: editEvents))")
        print(String(format: "folder search latency: %.1fms results=%d %@", searchMs, resultCount, searchOK ? "✓" : "✗"))
        print(String(format: "resident memory: %.1fMB delta=%.1fMB %@", rssMB, rssDeltaMB, memoryOK ? "✓" : "✗"))

        let report: [String: Any] = [
            "workload": workloadSummary.dictionary,
            "metrics": [
                "parseMedianMs": parseMedianMs,
                "openUsableMs": openUsableMs,
                "openSettledMs": openSettledMs,
                "scrollReadyTotalMs": scrollReadyTotalMs,
                "scrollSettledTotalMs": scrollSettledTotalMs,
                "scrollMaxStepMs": scrollMaxStepMs,
                "editReadyMs": editReadyMs,
                "editSettledMs": editSettledMs,
                "reloadReadyMs": reloadReadyMs,
                "reloadSettledMs": reloadSettledMs,
                "reloadMarks": reloadMarks,
                "finalLength": finalLength,
                "rendered": rendered,
                "openEvents": openEvents,
                "scrollEvents": scrollEvents,
                "reloadEvents": reloadEvents,
                "editEvents": editEvents,
                "searchMs": searchMs,
                "searchResultCount": resultCount,
                "rssMB": rssMB,
                "rssDeltaMB": rssDeltaMB
            ],
            "limits": [
                "openUsableMs": openUsableLimit,
                "openSettledMs": openSettledLimit,
                "scrollReadyTotalMs": scrollLimit,
                "editReadyMs": editLimit,
                "reloadReadyMs": reloadLimit,
                "searchMs": searchLimit,
                "rssMB": rssLimit,
                "rssDeltaMB": rssDeltaLimit
            ],
            "ok": [
                "render": renderOK,
                "interaction": interactionOK,
                "search": searchOK,
                "memory": memoryOK
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            print("performanceprobe-json: \(json)")
        }

        cleanup()
        exit(renderOK && interactionOK && searchOK && memoryOK ? 0 : 1)
    }

    private func format(eventSummary: [String: Any]) -> String {
        let keys = eventSummary.keys.sorted()
        guard !keys.isEmpty else { return "none" }
        return keys.compactMap { key in
            guard let stats = eventSummary[key] as? [String: Any] else { return nil }
            return String(format: "%@ count=%d total=%.1fms max=%.1fms", key, int(stats["count"]), double(stats["totalMs"]), double(stats["maxMs"]))
        }.joined(separator: "; ")
    }

    private func cleanup() {
        window?.orderOut(nil)
        if let searchFixtureRoot {
            try? FileManager.default.removeItem(at: searchFixtureRoot)
        }
    }

    private func fail(_ message: String) -> Never {
        cleanup()
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }

    private func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }

    private func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
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

    private static let defaultMarkdown = {
        var parts: [String] = []
        for i in 0..<80 {
            parts.append("# Section \(i)")
            parts.append("")
            parts.append("Paragraph \(i) with needle_token, **bold**, `inline_code_\(i)`, [a link](https://example.com/\(i)), and enough prose to make wrapping and rendering realistic.")
            parts.append("")
            if i % 4 == 0 {
                parts.append("| Artifact | Repository | Producer | Verification consumer |")
                parts.append("| --- | --- | --- | --- |")
                for r in 0..<4 {
                    parts.append("| `Sources/OuroMD/VeryLongPath/Generated/File\(i)_\(r).swift` | ouro-md | Performance Probe | The live editor must keep table-local scroll without page overflow. |")
                }
                parts.append("")
            }
            if i % 9 == 0 {
                parts.append("```swift")
                parts.append("let value\(i) = \"needle_token\"")
                parts.append("```")
                parts.append("")
            }
        }
        return parts.joined(separator: "\n")
    }()

    private static let hookScript = #"""
    window.__ouroPerfHooks = {
      events: [],
      event: function (name, detail) {
        this.events.push(Object.assign({
          name: name,
          at: (performance.now ? performance.now() : Date.now())
        }, detail || {}));
      }
    };
    """#

    private static let editorScript = #"""
    (async function () {
      const doc = markdown;
      const skipReload = !!skipActualReload;
      const hooks = window.__ouroPerfHooks || { events: [] };
      const now = () => performance.now ? performance.now() : Date.now();
      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      function notify(phase, detail) {
        window.webkit.messageHandlers.ouro.postMessage({ type: "performanceprobe-progress", phase: phase, detail: detail || "" });
      }
      function root() {
        return document.querySelector("#editor .vditor-ir .vditor-reset") ||
          document.querySelector("#editor .vditor-preview .vditor-reset") ||
          document.querySelector("#editor .vditor-reset") ||
          document.getElementById("editor");
      }
      function scroller() {
        return document.scrollingElement || document.documentElement;
      }
      function shape() {
        const current = root();
        return {
          blockCount: current ? current.children.length : 0,
          headings: current ? current.querySelectorAll("h1,h2,h3,h4,h5,h6").length : 0,
          tables: current ? current.querySelectorAll("table").length : 0,
          marks: document.querySelectorAll(".ouro-change-mark").length,
          scrollHeight: Math.round(scroller().scrollHeight || 0)
        };
      }
      function collect() {
        const current = root();
        const summary = shape();
        summary.links = current ? current.querySelectorAll("a").length : 0;
        summary.textLength = current ? (current.textContent || "").length : 0;
        return summary;
      }
      async function waitUntil(predicate, timeoutMs) {
        const started = now();
        while (now() - started < timeoutMs) {
          if (predicate()) { return true; }
          await sleep(16);
        }
        return false;
      }
      async function waitForQuiet(timeoutMs, quietMs, signatureFn) {
        const started = now();
        let last = "", quietStart = 0;
        while (now() - started < timeoutMs) {
          const current = signatureFn();
          if (current === last) {
            if (!quietStart) { quietStart = now(); }
            if (now() - quietStart >= quietMs) { return true; }
          } else {
            last = current;
            quietStart = 0;
          }
          await sleep(50);
        }
        return false;
      }
      function clearHooks() { hooks.events.length = 0; }
      function summarizeHooks() {
        return hooks.events.reduce((summary, event) => {
          const entry = summary[event.name] || { count: 0, totalMs: 0, maxMs: 0 };
          entry.count += 1;
          entry.totalMs += event.durationMs || 0;
          entry.maxMs = Math.max(entry.maxMs, event.durationMs || 0);
          summary[event.name] = entry;
          return summary;
        }, {});
      }
      function median(values) {
        const sorted = values.slice().sort((a, b) => a - b);
        const middle = Math.floor(sorted.length / 2);
        return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
      }
      function focusEnd() {
        const editorRoot = root();
        if (!editorRoot) { return; }
        editorRoot.focus();
        const range = document.createRange();
        range.selectNodeContents(editorRoot);
        range.collapse(false);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
      }
      function withReloadChange(source) {
        const lines = source.split("\n");
        const midpoint = Math.floor(lines.length / 2);
        for (let offset = 0; offset < lines.length; offset++) {
          const index = (midpoint + offset) % lines.length;
          const line = lines[index];
          if (!line || line[0] === "#" || line.startsWith("| ---") || line.startsWith("```")) { continue; }
          if (line.indexOf("[probe reload]") >= 0) { continue; }
          lines[index] = line + " [probe reload]";
          return lines.join("\n");
        }
        return source + "\n[probe reload]\n";
      }

      try {
        notify("parse", "starting parse micro-benchmark");
        const parseRuns = [];
        for (let i = 0; i < 3; i++) {
          const started = now();
          window.__ouroEditor.vditor.lute.Md2VditorIRDOM(doc);
          parseRuns.push(now() - started);
          await sleep(50);
        }
        notify("parse", "completed parse micro-benchmark");

        clearHooks();
        const openStart = now();
        notify("open", "calling window.ouro.setValue");
        window.ouro.setValue(doc);
        notify("open", "setValue returned");
        const openUsable = await waitUntil(function () {
          const current = shape();
          return current.blockCount > 0 && current.headings > 0 && (doc.indexOf("|") < 0 || current.tables > 0);
        }, 120000);
        const openUsableMs = now() - openStart;
        notify("open", openUsable ? ("usable " + openUsableMs.toFixed(1) + "ms") : "usable wait timed out");
        const openSettled = openUsable && await waitForQuiet(120000, 300, function () {
          const current = shape();
          return [current.blockCount, current.headings, current.tables, current.scrollHeight, current.marks, hooks.events.length].join(":");
        });
        const openSettledMs = now() - openStart;
        notify("open", openSettled ? ("settled " + openSettledMs.toFixed(1) + "ms") : "settle wait timed out");
        const rendered = collect();
        const openEvents = summarizeHooks();

        await sleep(100);
        clearHooks();
        notify("scroll", "starting scripted scroll pass");
        const scrollReadyDurations = [];
        const scrollSettledDurations = [];
        const scrollPoints = [0.25, 0.5, 0.75, 1, 0].map((fraction) => Math.max(0, Math.floor(scroller().scrollHeight * fraction)));
        for (const point of scrollPoints) {
          const started = now();
          scroller().scrollTop = point;
          const ready = await waitUntil(function () { return Math.abs(scroller().scrollTop - point) < 2; }, 2000);
          scrollReadyDurations.push(now() - started);
          if (ready) {
            await waitForQuiet(12000, 150, function () {
              return [Math.round(scroller().scrollTop), hooks.events.length].join(":");
            });
          }
          scrollSettledDurations.push(now() - started);
        }
        notify("scroll", "ready " + scrollReadyDurations.reduce((sum, value) => sum + value, 0).toFixed(1) + "ms settled " + scrollSettledDurations.reduce((sum, value) => sum + value, 0).toFixed(1) + "ms");
        const scrollEvents = summarizeHooks();

        clearHooks();
        focusEnd();
        const editStart = now();
        notify("typing", "inserting PERF_EDIT_TOKEN");
        if (window.__ouroEditor && window.__ouroEditor.insertValue) {
          window.__ouroEditor.insertValue("\nPERF_EDIT_TOKEN\n");
        } else {
          window.ouro.setValue(window.ouro.getValue() + "\nPERF_EDIT_TOKEN\n");
        }
        const editReady = await waitUntil(() => {
          const current = root();
          const tail = current && current.lastElementChild;
          return !!tail && ((tail.textContent || "").indexOf("PERF_EDIT_TOKEN") >= 0);
        }, 12000);
        const editReadyMs = now() - editStart;
        notify("typing", editReady ? ("ready " + editReadyMs.toFixed(1) + "ms") : "token wait timed out");
        const editSettled = editReady && await waitForQuiet(12000, 300, function () {
          const current = shape();
          return [current.blockCount, current.headings, current.tables, current.scrollHeight, current.marks, hooks.events.length].join(":");
        });
        const editSettledMs = now() - editStart;
        notify("typing", editSettled ? ("settled " + editSettledMs.toFixed(1) + "ms") : "typing settle wait timed out");
        const editEvents = summarizeHooks();

        let reloadReady = false;
        let reloadSettled = false;
        let reloadReadyMs = -1;
        let reloadSettledMs = -1;
        let reloadStats = { marks: -1 };
        let reloadEvents = {};
        if (skipReload) {
          notify("reload", "skipped by OURO_PERF_SKIP_RELOAD");
        } else {
          clearHooks();
          const reloadStart = now();
          const reloaded = withReloadChange(doc);
          notify("reload", "calling window.ouro.reloadValue");
          window.ouro.reloadValue(reloaded);
          notify("reload", "reloadValue returned");
          reloadReady = await waitUntil(() => shape().marks > 0, 120000);
          reloadReadyMs = now() - reloadStart;
          notify("reload", reloadReady ? ("ready " + reloadReadyMs.toFixed(1) + "ms") : "reload wait timed out");
          reloadSettled = reloadReady && await waitForQuiet(120000, 400, function () {
            const current = shape();
            return [current.blockCount, current.headings, current.tables, current.scrollHeight, current.marks, hooks.events.length].join(":");
          });
          reloadSettledMs = now() - reloadStart;
          notify("reload", reloadSettled ? ("settled " + reloadSettledMs.toFixed(1) + "ms") : "reload settle wait timed out");
          reloadStats = collect();
          reloadEvents = summarizeHooks();
        }

        window.webkit.messageHandlers.ouro.postMessage({
          type: "performanceprobe",
          parseMedianMs: median(parseRuns),
          openUsableMs: openUsableMs,
          openSettledMs: openSettledMs,
          scrollReadyTotalMs: scrollReadyDurations.reduce((sum, value) => sum + value, 0),
          scrollSettledTotalMs: scrollSettledDurations.reduce((sum, value) => sum + value, 0),
          scrollMaxStepMs: scrollSettledDurations.reduce((max, value) => Math.max(max, value), 0),
          editReadyMs: editReadyMs,
          editSettledMs: editSettledMs,
          reloadReadyMs: reloadReadyMs,
          reloadSettledMs: reloadSettledMs,
          reloadMarks: reloadStats.marks,
          finalLength: (window.ouro.getValue() || "").length,
          rendered: rendered,
          openEvents: openEvents,
          scrollEvents: scrollEvents,
          reloadEvents: reloadEvents,
          editEvents: editEvents,
          ok: {
            openUsable: openUsable,
            openSettled: openSettled,
            reloadReady: reloadReady,
            reloadSettled: reloadSettled,
            editReady: editReady,
            editSettled: editSettled
          }
        });
      } catch (error) {
        window.webkit.messageHandlers.ouro.postMessage({
          type: "performanceprobe",
          error: String(error && (error.stack || error.message) || error)
        });
      }
    })();
    undefined;
    """#
}
