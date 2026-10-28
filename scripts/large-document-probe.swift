import AppKit
import Foundation
import WebKit

// Metadata-only real WebKit proof. Never print source, HTML, URLs or screenshots.
final class LargeDocumentRunner: NSObject, WKScriptMessageHandler {
    let index: URL
    let markdown: String
    var webView: WKWebView!
    var window: NSWindow!
    var started = false
    var failures = 0
    var phase = "starting"

    init(index: URL, markdown: String) {
        self.index = index
        self.markdown = markdown
    }

    func run() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "ouro")
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderOut(nil)
        webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            print("FAIL timeout phase=\(self.phase)")
            exit(1)
        }
        NSApplication.shared.run()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready", !started {
            started = true
            webView.callAsyncJavaScript(Self.script, arguments: ["markdown": markdown], in: nil, in: .page) { result in
                if case .failure = result { print("FAIL JavaScript dispatch"); exit(1) }
            }
        } else if type == "large-probe-phase" {
            phase = body["phase"] as? String ?? "unknown"
            print("phase: \(phase)")
            fflush(stdout)
        } else if type == "large-probe-result" {
            guard let metrics = body["metrics"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { exit(1) }
            print(text)
            exit((metrics["passed"] as? Bool) == true ? 0 : 1)
        }
    }

    static let script = #"""
    const metrics = { checks: {} };
    const now = () => performance.now();
    const phase = name => window.webkit.messageHandlers.ouro.postMessage({type:"large-probe-phase", phase:name});
    window.__ouroPerfHooks = {event: name => { if (name.startsWith("large.")) phase(name); }};
    const frame = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const check = (name, value) => { metrics.checks[name] = !!value; };
    const scroller = () => document.scrollingElement;
    try {
      const original = markdown;
      phase("open");
      let start = now();
      window.ouro.setValue(original);
      await frame();
      metrics.openMs = now() - start;
      check("largeMode", window.ouro.documentMode && window.ouro.documentMode().large);
      if (!metrics.checks.largeMode) throw new Error("missing compatibility mode");
      check("noRichEditor", !window.__ouroEditor);
      check("roundtrip", window.ouro.getValue() === original);
      check("announced", !!document.querySelector("#ouro-large-note")?.textContent);
      metrics.headings = document.querySelectorAll("#ouro-large-reading h1,h2,h3,h4,h5,h6").length;
      metrics.tables = document.querySelectorAll("#ouro-large-reading table").length;
      const html = window.ouro.getHTML();
      metrics.htmlLength = html.length;
      check("fullExport", html.includes("PERF_EOF_SENTINEL") || html.length > original.length / 2);
      phase("scroll");
      start = now();
      scroller().scrollTop = scroller().scrollHeight * .5;
      await frame();
      metrics.scrollMs = now() - start;
      check("scrolled", scroller().scrollTop > 0);
      const y = scroller().scrollTop;
      phase("reload-reading");
      start = now();
      window.ouro.reloadValue(original + "\nPERF_RELOAD_TOKEN\n");
      await frame();
      metrics.readingReloadMs = now() - start;
      check("readingReloadIntegrity", window.ouro.getValue() === original + "\nPERF_RELOAD_TOKEN\n");
      check("readingPosition", Math.abs(scroller().scrollTop - y) < 3);
      phase("source");
      start = now();
      window.ouro.setMode("sv");
      await frame();
      metrics.sourceModeMs = now() - start;
      const input = document.querySelector("#ouro-large-source");
      check("sourceSurface", !!input && !input.hidden);
      input.focus();
      input.setSelectionRange(input.value.length, input.value.length);
      const beforeTyping = window.ouro.getValue();
      phase("typing");
      start = now();
      document.execCommand("insertText", false, "🙂PERF_TYPED_TOKEN");
      metrics.inputCallMs = now() - start;
      await frame();
      metrics.inputPaintMs = now() - start;
      check("typingFullIntegrity", window.ouro.getValue() === beforeTyping + "🙂PERF_TYPED_TOKEN");
      window.ouro.undo();
      check("typingUndo", window.ouro.getValue() === beforeTyping);
      window.ouro.redo();
      check("typingRedo", window.ouro.getValue() === beforeTyping + "🙂PERF_TYPED_TOKEN");
      window.ouro.revealSearchMatch({query:"PERF_TYPED_TOKEN", matchedText:"PERF_TYPED_TOKEN", matchOrdinal:0});
      await frame();
      check("findNearEOF", input.value.slice(input.selectionStart, input.selectionEnd) === "PERF_TYPED_TOKEN");
      check("replaceNearEOF", window.ouro.replaceNext("PERF_TYPED_TOKEN", "PERF_REPLACED_TOKEN", {}) === 1);
      check("replaceIntegrity", window.ouro.getValue() === beforeTyping + "🙂PERF_REPLACED_TOKEN");
      window.ouro.undo();
      check("replaceUndo", window.ouro.getValue() === beforeTyping + "🙂PERF_TYPED_TOKEN");
      window.ouro.setEditable(false);
      const locked = window.ouro.getValue();
      window.ouro.insertText("FORBIDDEN");
      window.ouro.applyEdit("FORBIDDEN");
      check("lock", window.ouro.getValue() === locked && input.readOnly);
      window.ouro.setEditable(true);
      window.ouro.applyEdit(locked + "\nASSISTANT\n");
      window.ouro.undo();
      check("assistantUndo", window.ouro.getValue() === locked);
      phase("reload-source");
      const reload = original + "\nPERF_SOURCE_RELOAD_TOKEN\n";
      start = now();
      window.ouro.reloadValue(reload);
      await frame();
      metrics.sourceReloadMs = now() - start;
      check("sourceReloadIntegrity", window.ouro.getValue() === reload);
      phase("review");
      start = now();
      window.ouro.setMode("ir");
      window.ouro.showChangesSince(original);
      await frame();
      metrics.reviewMs = now() - start;
      check("retainedReview", document.querySelectorAll(".ouro-change-mark").length > 0 || !document.querySelector("#ouro-next-change").hidden);
      window.ouro.clearChangeReview();
      phase("transitions");
      window.ouro.setMode("sv");
      window.ouro.applyEdit("short 🙂\r\n");
      window.ouro.undo();
      check("thresholdUndo", window.ouro.getValue() === reload);
      window.ouro.setValue("short document\n");
      await new Promise(resolve => setTimeout(resolve, 600));
      check("smallDocumentRestored", !window.ouro.documentMode().large && !!window.__ouroEditor && window.ouro.getValue().trim() === "short document");
      const exact = "🙂漢字\r\n".repeat(70000) + "EOF\r\n";
      window.ouro.setValue(exact);
      window.ouro.setMode("sv");
      check("unicodeCRLFRoundtrip", window.ouro.getValue() === exact);
      const source = document.querySelector("#ouro-large-source");
      source.focus(); source.setSelectionRange(source.value.length, source.value.length);
      document.execCommand("insertText", false, "X");
      check("unicodeCRLFEdit", window.ouro.getValue() === exact + "X");
      metrics.bytes = new TextEncoder().encode(original).length;
      metrics.lines = original.split("\n").length;
      metrics.passed = Object.values(metrics.checks).every(Boolean) && metrics.openMs < 5000 && metrics.inputPaintMs < 200 && metrics.readingReloadMs < 5000 && metrics.sourceReloadMs < 5000;
    } catch (_) { metrics.passed = false; metrics.failedPhase = "see last phase"; }
    window.webkit.messageHandlers.ouro.postMessage({type:"large-probe-result", metrics});
    """#
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: swift scripts/large-document-probe.swift WEB_INDEX MARKDOWN_FILE")
    exit(2)
}
LargeDocumentRunner(index: URL(fileURLWithPath: arguments[1]), markdown: try String(contentsOfFile: arguments[2], encoding: .utf8)).run()
