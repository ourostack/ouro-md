import AppKit
import WebKit

/// Headless `--changehighlighttest`: checks that pasted text, an assistant's
/// edit glow, and agent file changes get margin cues, so the reader can see what
/// changed. A paste far down the page must be highlighted exactly, scrolled into
/// view and painted in the accent colour, then cleared; an assistant edit must
/// be highlighted and brought into view; an agent's file change must be
/// marked without moving the reader; and loading a document must add no cues.
/// Agent cues persist until reached and scrolled past, with explicit navigation
/// for off-screen changes and no saved review state.
final class ChangeHighlightTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let theme = ThemeStore.shared.defaultTheme
    private var results: [(String, Bool, String)] = []
    private var started = false

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
        guard !started else { return }
        started = true
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
    // Waits until the glow has begun, which is after any reveal scroll has
    // come to rest.
    const glowBegun = async () => {
      for (let i = 0; i < 80 && !(window.__ouroLastChangeFlash && window.__ouroLastChangeFlash.begun); i++) { await sleep(50); }
    };
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
        window.__ouroLastChangeFlash = null;
        target.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
        await sleep(40);
        // A synthetic paste event has no default action; insert the text the
        // way WebKit's paste does, unless the editor already did.
        if (root.textContent.indexOf("PASTED-TEXT") < 0) { document.execCommand("insertText", false, pasted); }
        // The glow begins once any reveal scroll has come to rest.
        await glowBegun();
        const during = live();
        const flashLevel = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--ouro-flash"));
        const flash = flashLevel();
        const timing = (window.__ouroLastChangeFlash || {}).timing || {};
        const changeColor = getComputedStyle(document.documentElement).getPropertyValue("--ouro-change-color").trim();
        const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
        return { loadHighlight, during, flash, hold: timing.hold, fade: timing.fade, reduceMotion, changeColor };
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
            // One continuous fade with no hold: strong once the change is on
            // screen. (Timers are throttled off-screen, so the curve itself is
            // checked through its timing rather than by sampling it.)
            // Reduce Motion shows the glow steadily, then clears it.
            let flash = r["flash"] as? Double ?? 0, hold = r["hold"] as? Double ?? -1, fade = r["fade"] as? Double ?? 0
            let reduceMotion = r["reduceMotion"] as? Bool ?? false
            let curve = reduceMotion ? (hold > 0 && fade == 0) : (hold == 0 && fade >= 800)
            self.record("highlight fades in one continuous step", flash > 0.3 && curve, "--ouro-flash=\(flash) hold=\(hold) fade=\(fade) reduceMotion=\(reduceMotion)")
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
        const flashLevel = () => getComputedStyle(document.documentElement).getPropertyValue("--ouro-flash").trim();
        for (let i = 0; i < 40 && (live() || flashLevel() !== "0"); i++) { await sleep(50); }
        return { after: live(), flash: flashLevel() };
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
        window.__ouroLastChangeFlash = null;
        window.ouro.applyEdit(next);
        await glowBegun();
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
        return { during: live(), marks: document.querySelectorAll(".ouro-change-mark").length, scrollTop: scroller.scrollTop };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("agent script failed: \(result)") }
            self.record("agent change gets a margin cue instead of a glow", (r["marks"] as? Int) == 1 && r["during"] is NSNull, "\(r)")
            let scrollTop = r["scrollTop"] as? Double ?? -1
            self.record("agent change does not move the reader", scrollTop == 0, "scrollTop=\(scrollTop)")
            self.reviewCases()
        }
    }

    /// Regressions from review: post-render table fix-ups must not widen an
    /// agent's highlight, a visible paste must not scroll, and an edit inside a
    /// code block's hidden source highlights the block without moving the page.
    private func reviewCases() {
        let script = Self.probe + #"""
        await sleep(1600);
        const table = "Intro line.\n\n| Column | Notes |\n| --- | --- |\n| one | see **this** here |\n\n```js\nconst answer = 41;\n```\n\nClosing line.\n";
        window.ouro.setValue(table);
        await sleep(900);
        scroller.scrollTop = 0;
        window.ouro.reloadValue(table.replace("Intro line.", "Intro AGENT-TOP line."));
        await sleep(500);
        const tableMark = document.querySelector(".ouro-change-mark");
        const intro = document.querySelector("#editor .vditor-ir .vditor-reset > p");
        const tableCue = tableMark && intro && Math.abs(tableMark.getBoundingClientRect().top - intro.getBoundingClientRect().top) < 2;
        await sleep(1600);

        const root = document.querySelector("#editor .vditor-ir .vditor-reset");
        const closing = [...root.querySelectorAll("p")].find((p) => p.textContent.indexOf("Closing line.") === 0);
        root.focus();
        const walker = document.createTreeWalker(closing, NodeFilter.SHOW_TEXT);
        let last = null;
        while (walker.nextNode()) { last = walker.currentNode; }
        const caret = document.createRange();
        caret.setStart(last, last.data.length);
        getSelection().removeAllRanges();
        getSelection().addRange(caret);
        const before = scroller.scrollTop;
        const data = new DataTransfer();
        data.setData("text/plain", " VISIBLE-PASTE");
        closing.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
        await sleep(40);
        if (root.textContent.indexOf("VISIBLE-PASTE") < 0) { document.execCommand("insertText", false, " VISIBLE-PASTE"); }
        await sleep(400);
        const visiblePaste = live();
        const pasteScroll = scroller.scrollTop - before;
        await sleep(1600);

        getSelection().removeAllRanges();
        scroller.scrollTop = 0;
        await sleep(100);
        window.ouro.applyEdit(window.ouro.getValue().replace("const answer = 41;", "const answer = 42;"));
        await sleep(500);
        const codeHighlight = live();
        return { tableCue, visiblePaste, pasteScroll, codeHighlight, codeScroll: scroller.scrollTop };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("review script failed: \(result)") }
            self.record("agent cue stays beside its passage after table fix-ups", (r["tableCue"] as? Bool) == true, "\(r["tableCue"] ?? "")")
            let pasteText = ((r["visiblePaste"] as? [String: Any])?["text"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let pasteScroll = r["pasteScroll"] as? Double ?? -1
            self.record("a paste already on screen is highlighted without scrolling", pasteText == "VISIBLE-PASTE" && pasteScroll == 0, "text=\(pasteText) scrolled=\(pasteScroll)")
            let code = r["codeHighlight"] as? [String: Any]
            let codeScroll = r["codeScroll"] as? Double ?? -1
            let codeVisible = (code?["bottom"] as? Double ?? 0) > (code?["top"] as? Double ?? 0)
            self.record("an edit in a code block highlights the block without moving the page", codeVisible && codeScroll == 0, "highlight=\(String(describing: code)) scrollTop=\(codeScroll)")
            self.marginCases()
        }
    }

    private func marginCases() {
        let script = Self.probe + #"""
        const marks = () => document.querySelectorAll(".ouro-change-mark").length;
        const button = () => document.getElementById("ouro-next-change");
        if (!button()) { return { missing: true }; }
        const root = () => document.querySelector("#editor .vditor-ir .vditor-reset");
        const paragraph = (n) => [...root().querySelectorAll("p")].find((p) => p.textContent.indexOf("Paragraph " + n + " ") === 0);
        window.ouro.setValue(original);
        await sleep(500);
        scroller.scrollTop = 0;
        await sleep(100);
        const initial = marks();
        const next = original.replace("Paragraph 5 says", "Paragraph 5 AGENT says")
          .replace("Paragraph 55 says", "Paragraph 55 AGENT says");
        window.ouro.reloadValue(next);
        await sleep(600);
        const two = marks();
        const unchangedScroll = scroller.scrollTop === 0;
        const navigation = button() && !button().hidden && button().textContent === "Next change" && button().tabIndex === 0;
        const serialized = window.ouro.getValue() === next;
        await sleep(1700);
        const persistent = marks();
        scroller.scrollTop = paragraph(30).getBoundingClientRect().top + scroller.scrollTop - 100;
        await sleep(150);
        const unseenSurvives = marks();
        button().click();
        await sleep(150);
        const jumped = paragraph(55).getBoundingClientRect().top >= 48
          && paragraph(55).getBoundingClientRect().bottom < window.innerHeight;
        const reachedStays = marks();
        scroller.scrollTop = 0;
        await sleep(150);
        const cleared = marks();
        const controlCleared = button().hidden;
        window.ouro.reloadValue(next.replace("Paragraph 20 says something worth reading.\n\n", ""));
        await sleep(500);
        const deleted = document.querySelectorAll(".ouro-change-deletion").length;
        window.ouro.setMode("sv");
        await sleep(600);
        const sourceHidden = marks() === 0 && button().hidden;
        window.ouro.setMode("ir");
        await sleep(600);
        const modeRestored = document.querySelectorAll(".ouro-change-deletion").length;
        window.ouro.reloadValue(next.replace("Paragraph 40 says", "Paragraph 40 LATE says"));
        window.ouro.setValue("Another document.\n");
        await sleep(600);
        return { initial, two, unchangedScroll, navigation, serialized, persistent, unseenSurvives,
          jumped, reachedStays, cleared, controlCleared, deleted, sourceHidden, modeRestored,
          staleCleared: marks() === 0 && button().hidden };
        """#
        webView.callAsyncJavaScript(script, arguments: ["original": Self.original], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("margin script failed: \(result)") }
            self.record("opening a document adds no margin cues", (r["initial"] as? Int) == 0, "\(r)")
            self.record("independent agent edits get separate cues without scrolling", (r["two"] as? Int) == 2 && (r["unchangedScroll"] as? Bool) == true, "\(r)")
            self.record("off-screen changes have a keyboard-accessible Next change button", (r["navigation"] as? Bool) == true, "\(r)")
            self.record("margin cues do not change saved Markdown", (r["serialized"] as? Bool) == true, "\(r)")
            self.record("margin cues outlast the paste glow", (r["persistent"] as? Int) == 2, "\(r)")
            self.record("scrolling past a reached cue preserves an unseen cue", (r["unseenSurvives"] as? Int) == 1, "\(r)")
            self.record("Next change reveals a cue without dismissing it", (r["jumped"] as? Bool) == true && (r["reachedStays"] as? Int) == 1, "\(r)")
            self.record("scrolling past the last reached cue clears navigation", (r["cleared"] as? Int) == 0 && (r["controlCleared"] as? Bool) == true, "\(r)")
            self.record("deletion marks its gap", (r["deleted"] as? Int) == 1, "\(r)")
            self.record("mode switches hide source cues and restore rendered anchors", (r["sourceHidden"] as? Bool) == true && (r["modeRestored"] as? Int) == 1, "\(r)")
            self.record("new document cancels pending old-document cues", (r["staleCleared"] as? Bool) == true, "\(r)")
            self.sourceAndReflowCases()
        }
    }

    private func sourceAndReflowCases() {
        let script = Self.probe + #"""
        window.ouro.setValue("Alpha.\n\nBeta.\n\nGamma.\n");
        await sleep(400);
        window.ouro.setMode("sv");
        await sleep(500);
        window.ouro.reloadValue("Alpha.\n\nBeta agent.\n\nGamma.\n");
        await sleep(20);
        window.ouro.applyEdit("Alpha local.\n\nBeta agent.\n\nGamma.\n");
        await sleep(400);
        window.ouro.setMode("ir");
        await sleep(500);
        const sourceMarks = document.querySelectorAll(".ouro-change-mark").length;
        window.ouro.setValue("Alpha.\n\nBeta.\n\nGamma.\n");
        await sleep(300);
        window.ouro.reloadValue("Alpha.\n\nBeta agent.\n\nGamma.\n");
        window.ouro.applyEdit("Alpha local.\n\nBeta agent.\n\nGamma.\n");
        window.ouro.reloadValue("Alpha local.\n\nBeta agent.\n\nGamma agent.\n");
        await sleep(400);
        const consecutiveMarks = document.querySelectorAll(".ouro-change-mark").length;
        window.ouro.setValue("Alpha.\n\nBeta.\n\nGamma.\n");
        await sleep(300);
        window.ouro.reloadValue("Alpha.\n\nBeta agent.\n\nGamma.\n");
        const editorRoot = document.querySelector("#editor .vditor-ir .vditor-reset");
        editorRoot.focus();
        const firstText = document.createTreeWalker(editorRoot.querySelector("p"), NodeFilter.SHOW_TEXT).nextNode();
        const caret = document.createRange();
        caret.setStart(firstText, 5); caret.collapse(true);
        getSelection().removeAllRanges(); getSelection().addRange(caret);
        const inserted = document.execCommand("insertText", false, " local");
        const typed = window.ouro.getValue();
        window.ouro.reloadValue(typed.replace("Gamma.", "Gamma agent."));
        await sleep(400);
        const typingWorked = inserted && typed.includes("Alpha local.");
        const typingMarks = document.querySelectorAll(".ouro-change-mark").length;
        const svg = btoa('<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4" fill="blue"/></svg>');
        const imageDoc = "![pixel](data:image/svg+xml;base64," + svg + ")\n\nCue old.\n";
        window.ouro.setValue(imageDoc);
        await sleep(400);
        window.ouro.reloadValue(imageDoc.replace("Cue old.", "Cue agent."));
        await sleep(400);
        const root = document.querySelector("#editor .vditor-ir .vditor-reset");
        const target = [...root.querySelectorAll("p")].find((p) => p.textContent.indexOf("Cue agent.") === 0);
        const image = root.querySelector("img");
        const mark = document.querySelector(".ouro-change-mark");
        if (!target || !image || !mark) { return { sourceMarks, consecutiveMarks, typingMarks, typingWorked, missingImage: true }; }
        const oldTop = target.getBoundingClientRect().top;
        image.style.height = "240px";
        await sleep(200);
        const targetTop = target.getBoundingClientRect().top;
        const markerTop = document.querySelector(".ouro-change-mark").getBoundingClientRect().top;
        return { sourceMarks, consecutiveMarks, typingMarks, typingWorked, reflowMoved: targetTop > oldTop + 100, reflowAligned: Math.abs(targetTop - markerTop) < 2 };
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let r = value as? [String: Any] else { self.fail("source/reflow script failed: \(result)") }
            self.record("source-mode local edits are not attributed to an agent", (r["sourceMarks"] as? Int) == 1, "\(r)")
            self.record("consecutive reloads exclude local edits made while rendering settles", (r["consecutiveMarks"] as? Int) == 2, "\(r)")
            self.record("consecutive reloads exclude real typing before Vditor's input callback", (r["typingWorked"] as? Bool) == true && (r["typingMarks"] as? Int) == 2, "\(r)")
            self.record("late image reflow keeps the cue beside its passage", (r["reflowMoved"] as? Bool) == true && (r["reflowAligned"] as? Bool) == true, "\(r)")
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
