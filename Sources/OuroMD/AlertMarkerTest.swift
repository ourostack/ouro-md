import AppKit
import WebKit

/// Headless `--alerttest`: verifies GitHub-style alert callouts hide their raw
/// marker visually without removing it from the Markdown source.
final class AlertMarkerTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var didStart = false

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
            FileHandle.standardError.write(Data("alerttest: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("alerttest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            guard !didStart else { return }
            didStart = true
            webView.evaluateJavaScript(Self.script, completionHandler: nil)
        } else if type == "alerttest" {
            let results = body["results"] as? [[String: Any]] ?? []
            var allPassed = true
            for result in results {
                let name = result["name"] as? String ?? "unnamed"
                let ok = result["ok"] as? Bool ?? false
                let detail = result["detail"] as? String ?? ""
                allPassed = allPassed && ok
                print("\(ok ? "PASS" : "FAIL") \(name): \(detail.replacingOccurrences(of: "\n", with: "\\n"))")
            }
            exit(allPassed && !results.isEmpty ? 0 : 1)
        }
    }

    private static let script = #"""
    (async function () {
      var results = [];
      function delay(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
      async function waitFor(label, fn) {
        for (var i = 0; i < 70; i++) {
          if (fn()) { return true; }
          await delay(100);
        }
        results.push({ name: "wait for " + label, ok: false, detail: snapshot(label).detail });
        return false;
      }
      function findTextNode(text) {
        var root = document.querySelector("#editor");
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
        var n;
        while ((n = walker.nextNode())) {
          if ((n.nodeValue || "").indexOf(text) !== -1) { return n; }
        }
        return null;
      }
      function caretAfter(text) {
        var n = findTextNode(text);
        if (!n) { return false; }
        var idx = n.nodeValue.indexOf(text) + text.length;
        var range = document.createRange();
        range.setStart(n, idx);
        range.collapse(true);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        return true;
      }
      function snapshot(label) {
        var bq = document.querySelector("#editor blockquote.ouro-alert-note");
        var alertCount = document.querySelectorAll("#editor blockquote.ouro-alert").length;
        var tip = document.querySelector("#editor blockquote.ouro-alert-tip");
        var marker = bq ? bq.querySelector(".ouro-alert-marker") : null;
        var markerStyle = marker ? getComputedStyle(marker) : null;
        var before = bq ? getComputedStyle(bq, "::before") : null;
        var value = window.ouro.getValue();
        var markerFont = markerStyle ? markerStyle.fontSize : "";
        var markerOpacity = markerStyle ? markerStyle.opacity : "";
        var beforeContent = before ? before.content : "";
        var beforeDisplay = before ? before.display : "";
        var hidden = markerStyle ? (parseFloat(markerFont) === 0 && parseFloat(markerOpacity) === 0) : false;
        var revealed = markerStyle ? (parseFloat(markerFont) > 0 && parseFloat(markerOpacity) > 0) : false;
        return {
          hasAlert: !!bq,
          alertCount: alertCount,
          hasTipAlert: !!tip,
          tipHasNestedQuote: !!(tip && tip.querySelector("blockquote")),
          hasMarker: !!marker,
          markerText: marker ? marker.textContent : "",
          markerHidden: hidden,
          markerRevealed: revealed,
          labelRendered: beforeContent.indexOf("Note") !== -1 && beforeDisplay !== "none",
          labelHidden: beforeDisplay === "none",
          sourcePreserved: value.indexOf("> [!NOTE]") !== -1 && value.indexOf("> An alert.") !== -1 &&
            value.indexOf("> [!TIP]") !== -1 && value.indexOf("Nested quote body.") !== -1,
          value: value,
          detail: "label=" + label + " hasAlert=" + !!bq + " alertCount=" + alertCount + " hasMarker=" + !!marker +
            " markerText=" + (marker ? marker.textContent : "") +
            " markerFont=" + markerFont + " markerOpacity=" + markerOpacity +
            " before=" + beforeContent + "/" + beforeDisplay +
            " hasTip=" + !!tip + " tipNested=" + !!(tip && tip.querySelector("blockquote")) +
            " value=" + value.replace(/\n/g, "\\n")
        };
      }
      function record(name, ok, snap) {
        results.push({ name: name, ok: !!ok, detail: (snap || snapshot(name)).detail });
      }

      var doc = [
        "# Alerts",
        "",
        "  > Leading-space top-level quote stays normal.",
        "",
        "- List item",
        "  > [!NOTE]",
        "  > List-contained marker stays normal.",
        "",
        "> [!NOTE]",
        "> An alert.",
        "",
        "> [!TIP]",
        "> Tip alert.",
        "> > Nested quote body.",
        "",
        "> `[!NOTE]`",
        "> Code marker stays normal.",
        "",
        "> [!NOTE](https://x.com)",
        "> Link marker stays normal.",
        "",
        "> **[!NOTE]**",
        "> Strong marker stays normal.",
        "",
        "> [!NOTE][ref]",
        "> Ref marker stays normal.",
        "",
        "> Ordinary quote first.",
        "> [!NOTE] later stays normal.",
        "",
        "> > [!NOTE]",
        "> > Nested marker stays normal.",
        "",
        "Outside paragraph.",
        ""
      ].join("\n");

      window.ouro.setValue(doc);
      await waitFor("initial marker", function () {
        return !!document.querySelector("#editor blockquote.ouro-alert-note .ouro-alert-marker");
      });
      var initial = snapshot("initial");
      record("initial callout hides raw marker and keeps source",
        initial.hasAlert && initial.alertCount === 2 && initial.hasTipAlert && initial.tipHasNestedQuote &&
        initial.hasMarker && initial.markerText === "[!NOTE]" &&
        initial.markerHidden && initial.labelRendered && initial.sourcePreserved,
        initial);

      window.ouro.focus();
      caretAfter("An alert.");
      await delay(250);
      var focused = snapshot("focused");
      record("focused callout reveals editable marker",
        focused.hasAlert && focused.alertCount === 2 && focused.hasMarker && focused.markerText === "[!NOTE]" &&
        focused.markerRevealed && focused.labelHidden && focused.sourcePreserved,
        focused);

      document.execCommand("insertText", false, " Edited");
      await delay(500);
      var edited = snapshot("edited");
      record("editing alert body preserves marker",
        edited.sourcePreserved && edited.value.indexOf("An alert. Edited") !== -1,
        edited);

      var firstEditor = window.__ouroEditor;
      window.ouro.setMode("sv");
      await waitFor("sv rebuild", function () {
        return window.__ouroEditor && window.__ouroEditor !== firstEditor &&
          !!document.querySelector("#editor blockquote.ouro-alert-note .ouro-alert-marker");
      });
      var sv = snapshot("sv");
      record("split-view rebuild preserves callout marker",
        sv.hasAlert && sv.alertCount === 2 && sv.hasTipAlert && sv.tipHasNestedQuote && sv.hasMarker && sv.sourcePreserved,
        sv);

      var secondEditor = window.__ouroEditor;
      window.ouro.setMode("ir");
      await waitFor("ir rebuild", function () {
        return window.__ouroEditor && window.__ouroEditor !== secondEditor &&
          !!document.querySelector("#editor blockquote.ouro-alert-note .ouro-alert-marker");
      });
      var ir = snapshot("ir");
      record("instant-render rebuild preserves callout marker",
        ir.hasAlert && ir.alertCount === 2 && ir.hasTipAlert && ir.tipHasNestedQuote && ir.hasMarker && ir.sourcePreserved,
        ir);

      window.ouro.setValue([
        "Before paragraph.",
        "",
        "> [!NOTE]",
        "> Selection body.",
        "",
        "After paragraph.",
        ""
      ].join("\n"));
      await waitFor("selection marker", function () {
        return !!document.querySelector("#editor blockquote.ouro-alert-note .ouro-alert-marker");
      });
      var beforeNode = findTextNode("Before paragraph.");
      var afterNode = findTextNode("After paragraph.");
      var selectionIncludesMarker = false;
      if (beforeNode && afterNode) {
        var range = document.createRange();
        range.setStart(beforeNode, 0);
        range.setEnd(afterNode, "After paragraph.".length);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        selectionIncludesMarker = sel.toString().indexOf("[!NOTE]") !== -1;
      }
      record("spanning selection includes hidden marker", selectionIncludesMarker, snapshot("spanning-selection"));

      window.ouro.setValue([
        "> [!NOTE]",
        "> Marker edit body.",
        ""
      ].join("\n"));
      await waitFor("editable marker", function () {
        return !!document.querySelector("#editor blockquote.ouro-alert-note .ouro-alert-marker");
      });
      var editableMarker = document.querySelector("#editor blockquote.ouro-alert-note .ouro-alert-marker");
      if (editableMarker && editableMarker.firstChild) {
        var markerRange = document.createRange();
        markerRange.selectNodeContents(editableMarker);
        var markerSelection = window.getSelection();
        markerSelection.removeAllRanges();
        markerSelection.addRange(markerRange);
        document.execCommand("insertText", false, "[!CUSTOM]");
      }
      await delay(700);
      var editedMarker = snapshot("unsupported-marker-edit");
      record("editing marker to unsupported type removes alert styling",
        editedMarker.alertCount === 0 && editedMarker.value.indexOf("> [!CUSTOM]") !== -1,
        editedMarker);

      window.webkit.messageHandlers.ouro.postMessage({ type: "alerttest", results: results });
    })();
    """#
}
