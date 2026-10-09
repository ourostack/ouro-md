import AppKit
import WebKit

/// Headless `--changehighlighttest`: checks that pasted text, an assistant's
/// edit and an agent's file change are highlighted, so the reader can see what
/// changed. A paste far down the page must be highlighted exactly, scrolled into
/// view and painted in the accent colour, then cleared; an assistant edit must
/// be highlighted and brought into view; an agent's file change must be
/// highlighted without moving the reader; and loading a document must
/// highlight nothing.
final class ChangeHighlightTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let theme = ThemeStore.shared.defaultTheme
    private var results: [(String, Bool, String)] = []

    private static let paragraphs = (1...60).map { "Paragraph \($0) says something worth reading." }
    private static let original = paragraphs.joined(separator: "\n\n") + "\n"

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("changehighlighttest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHost(webView, size: frame.size)
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
            FileHandle.standardError.write(Data("changehighlighttest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], (body["type"] as? String) == "ready" else { return }
        let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
        webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
        webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(Self.original)))", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.pasteCase() }
    }

    /// Shared JS: the live highlight's text and on-screen rect.
    private static let probe = #"""
    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const live = () => {
      const h = window.CSS && CSS.highlights && CSS.highlights.get("ouro-change");
      if (!h) { return null; }
      const range = [...h][0];
      const r = range.getBoundingClientRect();
      return { text: range.toString(), top: r.top, bottom: r.bottom, left: r.left, right: r.right, viewport: window.innerHeight };
    };
    const scroller = document.scrollingElement || document.documentElement;
    """#

    private func pasteCase() {
        let script = Self.probe + #"""
        const loadHighlight = live();
        scroller.scrollTop = 0;
        await sleep(100);
        const root = document.querySelector("#editor .vditor-ir .vditor-reset") || document.querySelector("#editor .vditor-reset");
        const target = [...root.querySelectorAll("p")].find((p) => p.textContent.indexOf("Paragraph 50 ") === 0);
        if (!target) {
          const ps = [...root.querySelectorAll("p")];
          return { error: "no paragraph 50: " + ps.length + " paragraphs, first=" + JSON.stringify(ps.slice(0, 2).map((p) => p.textContent)) + " value=" + JSON.stringify(window.ouro.getValue().slice(0, 60)) };
        }
        root.focus();
        const walker = document.createTreeWalker(target, NodeFilter.SHOW_TEXT);
        let last = null;
        while (walker.nextNode()) { last = walker.currentNode; }
        const caret = document.createRange();
        caret.setStart(last, last.data.length);
        caret.collapse(true);
        getSelection().removeAllRanges();
        getSelection().addRange(caret);
        const pasted = " PASTED-TEXT";
        const data = new DataTransfer();
        data.setData("text/plain", pasted);
        target.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
        await sleep(40);
        // A synthetic paste event has no default action; insert the text the
        // way WebKit's paste does, unless the editor already did.
        if (root.textContent.indexOf("PASTED-TEXT") < 0) { document.execCommand("insertText", false, pasted); }
        // Wait for the reveal scroll to come to rest; the glow holds from then.
        await sleep(150);
        let lastTop = -1;
        for (let i = 0; i < 30 && scroller.scrollTop !== lastTop; i++) { lastTop = scroller.scrollTop; await sleep(60); }
        const during = live();
        const flash = getComputedStyle(document.documentElement).getPropertyValue("--ouro-flash").trim();
        const changeColor = getComputedStyle(document.documentElement).getPropertyValue("--ouro-change-color").trim();
        return { loadHighlight, during, flash, changeColor };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("paste script failed: \(result)") }
            if let error = r["error"] as? String { self.fail(error) }
            self.record("loading a document highlights nothing", r["loadHighlight"] is NSNull || r["loadHighlight"] == nil, "\(String(describing: r["loadHighlight"]))")
            let during = r["during"] as? [String: Any]
            let text = (during?["text"] as? String)?.trimmingCharacters(in: .whitespaces)
            self.record("pasted text is highlighted exactly", text == "PASTED-TEXT", "\(text ?? "none")")
            let top = during?["top"] as? Double ?? -1, bottom = during?["bottom"] as? Double ?? -1, viewport = during?["viewport"] as? Double ?? 0
            self.record("paste below the fold is scrolled into view", top >= 0 && bottom <= viewport, "top=\(top) bottom=\(bottom) viewport=\(viewport)")
            self.record("highlight is at full strength", (r["flash"] as? String) == "1", "--ouro-flash=\(r["flash"] ?? "nil")")
            // Sample the painted highlight against the same text once it clears.
            let rect = CGRect(x: during?["left"] as? Double ?? 0, y: top, width: (during?["right"] as? Double ?? 0) - (during?["left"] as? Double ?? 0), height: bottom - top)
            let changeColor = (r["changeColor"] as? String) ?? ""
            self.snapshotTint(in: rect) { lit in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    self.snapshotTint(in: rect) { cleared in
                        let accent = self.isTinted(lit, towards: changeColor, against: cleared)
                        self.record("highlight paints in the theme's change colour", accent, "colour=\(changeColor) lit=\(lit) cleared=\(cleared)")
                        self.clearedCase()
                    }
                }
            }
        }
    }

    private func clearedCase() {
        let script = Self.probe + #"""
        return { after: live(), flash: getComputedStyle(document.documentElement).getPropertyValue("--ouro-flash").trim() };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("clear script failed: \(result)") }
            let cleared = (r["after"] == nil || r["after"] is NSNull) && (r["flash"] as? String) == "0"
            self.record("highlight clears after its fade", cleared, "after=\(String(describing: r["after"])) flash=\(r["flash"] ?? "nil")")
            self.assistantCase()
        }
    }

    private func assistantCase() {
        let script = Self.probe + #"""
        scroller.scrollTop = 0;
        await sleep(100);
        const next = window.ouro.getValue().replace(/\s+$/, "") + "\n\nASSISTANT-ADDED paragraph.\n";
        window.ouro.applyEdit(next);
        await sleep(150);
        let lastTop = -1;
        for (let i = 0; i < 30 && scroller.scrollTop !== lastTop; i++) { lastTop = scroller.scrollTop; await sleep(60); }
        return { during: live(), last: JSON.stringify(window.__ouroLastChangeFlash) };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("assistant script failed: \(result)") }
            let during = r["during"] as? [String: Any]
            let text = (during?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.record("assistant edit is highlighted", text.contains("ASSISTANT-ADDED paragraph."), "\(text) last=\(r["last"] ?? "")")
            let top = during?["top"] as? Double ?? -1, bottom = during?["bottom"] as? Double ?? -1, viewport = during?["viewport"] as? Double ?? 0
            self.record("assistant edit is brought into view", top >= 0 && bottom <= viewport, "top=\(top) bottom=\(bottom) viewport=\(viewport)")
            self.agentCase()
        }
    }

    private func agentCase() {
        let script = Self.probe + #"""
        await sleep(1600);
        scroller.scrollTop = 0;
        await sleep(150);
        const next = window.ouro.getValue().replace("Paragraph 55 says", "Paragraph 55 now AGENT-CHANGED says");
        window.ouro.reloadValue(next);
        await sleep(250);
        return { during: live(), scrollTop: scroller.scrollTop };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("agent script failed: \(result)") }
            let during = r["during"] as? [String: Any]
            let text = (during?["text"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            self.record("agent change is highlighted", text == "now AGENT-CHANGED", text)
            let scrollTop = r["scrollTop"] as? Double ?? -1
            self.record("agent change does not move the reader", scrollTop == 0, "scrollTop=\(scrollTop)")
            self.finish()
        }
    }

    // MARK: - Pixels

    private func snapshotTint(in rect: CGRect, completion: @escaping ((r: Double, g: Double, b: Double)) -> Void) {
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { image, _ in
            completion(Self.averageColor(of: image, in: rect, viewHeight: self.webView.bounds.height))
        }
    }

    private static func averageColor(of image: NSImage?, in rect: CGRect, viewHeight: CGFloat) -> (r: Double, g: Double, b: Double) {
        guard let image, rect.width > 1, rect.height > 1,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return (0, 0, 0) }
        let scale = Double(cg.width) / Double(image.size.width)
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0) }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Web rects are top-left based; the bitmap rows run top to bottom too.
        let x0 = max(0, Int(rect.minX * scale)), x1 = min(width, Int(rect.maxX * scale))
        let y0 = max(0, Int(rect.minY * scale)), y1 = min(height, Int(rect.maxY * scale))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                let i = (y * width + x) * 4
                r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); n += 1
            }
        }
        _ = viewHeight
        return n > 0 ? (r / n, g / n, b / n) : (0, 0, 0)
    }

    /// The lit region moved towards the theme accent compared with the same
    /// text once the highlight cleared.
    private func isTinted(_ lit: (r: Double, g: Double, b: Double), towards hex: String, against cleared: (r: Double, g: Double, b: Double)) -> Bool {
        guard let accent = NSColor(hex: hex)?.usingColorSpace(.deviceRGB) else { return false }
        let a = (Double(accent.redComponent) * 255, Double(accent.greenComponent) * 255, Double(accent.blueComponent) * 255)
        func distance(_ c: (r: Double, g: Double, b: Double)) -> Double {
            let dr = c.r - a.0, dg = c.g - a.1, db = c.b - a.2
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
        return distance(lit) < distance(cleared) - 8
    }

    // MARK: - Reporting

    private func record(_ name: String, _ ok: Bool, _ detail: String) {
        results.append((name, ok, detail))
    }

    private func finish() -> Never {
        for (name, ok, detail) in results {
            print("\(name): \(ok ? "✓" : "✗ \(detail)")")
        }
        exit(results.allSatisfy { $0.1 } ? 0 : 1)
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("changehighlighttest: \(message)\n".utf8))
        exit(1)
    }

    private func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
