import AppKit
import OuroMDCore
import QuartzCore
import WebKit
import XCTest
@testable import OuroMD

/// Two short website dramatizations on an agent's plan for importing recipes into Spoonjoy,
/// captured only in a disposable hosted desktop session:
/// - typing: the document grows as if typed and renders as it goes;
/// - agent: an outside writer fills the empty Test recipes table and ticks two checklist items.
@MainActor
final class NativeSiteMediaPeriscopeTests: XCTestCase {
    private var records: [[String: Any]] = []
    private let windowSize = NSSize(width: 840, height: 630)
    private let textScale = 1.1

    func testHostedPeriscopeDramatizations() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_SITE_MEDIA"] == "1",
                          "never present windows or capture an operator's desktop")
        let output = URL(fileURLWithPath: env["OURO_SITE_MEDIA_OUTPUT"] ?? ".build/site-media")
            .standardizedFileURL.appendingPathComponent("periscope", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let full = try String(contentsOf: fixtures.appendingPathComponent("Recipe import plan.md"), encoding: .utf8)
        defer {
            try? JSONSerialization.data(withJSONObject: [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "version": OuroMDRelease.version,
                "window": ["width": windowSize.width, "height": windowSize.height, "textScale": textScale],
                "records": records,
                "captureKind": "screencapture-owned-native-window"
            ], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("capture.json"))
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        for theme in ["quartz", "graphite"] {
            try await typingClip(theme: theme, full: full, fixtures: fixtures, output: output)
            try await agentClip(theme: theme, full: full, fixtures: fixtures, output: output)
        }
    }

    // MARK: - Clip A: renders as you type

    private func typingClip(theme: String, full: String, fixtures: URL, output: URL) async throws {
        let sample = output.appendingPathComponent("typing-\(theme)", isDirectory: true)
        try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
        let typedStart = try XCTUnwrap(full.range(of: "## At a glance"))
        let typedEnd = try XCTUnwrap(full.range(of: "## Test recipes"))
        let start = String(full[..<typedStart.lowerBound])
        let typed = String(full[typedStart.lowerBound..<typedEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let document = sample.appendingPathComponent("Recipe import plan.md")
        try start.write(to: document, atomically: true, encoding: .utf8)
        try initRepository(sample, committing: [])

        let (controller, web) = try await open(document, theme: theme, until: "Recipe import")
        defer { close(controller) }
        _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")

        let steps = typingSteps(start: start, typed: typed)
        let total = steps.reduce(0.0) { $0 + $1.delay }
        let movie = output.appendingPathComponent("typing-\(theme).mov")
        let (recorder, recordingStart) = try startRecorder(controller.window, to: movie, seconds: Int(total * 1.8 + 9))
        defer { if recorder.isRunning { recorder.terminate() } }
        await pumpUntil(recordingStart + 1.8)
        let typingStart = ProcessInfo.processInfo.systemUptime - recordingStart
        for step in steps {
            _ = try await web.evaluateJavaScript("""
            (function (md, caret) {
              window.ouro.setValue(md);
              var root = document.querySelector('.vditor-ir .vditor-reset');
              var sel = getSelection();
              if (caret && root) {
                var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                var last = null;
                while (walker.nextNode()) { if (walker.currentNode.nodeValue.trim()) { last = walker.currentNode; } }
                root.focus();
                var range = document.createRange();
                if (last) { range.setStart(last, last.nodeValue.length); } else { range.selectNodeContents(root); range.collapse(false); }
                range.collapse(true);
                sel.removeAllRanges(); sel.addRange(range);
              } else if (!caret) { sel.removeAllRanges(); }
              var s = document.scrollingElement;
              if (s.scrollHeight > s.clientHeight) { s.scrollTop = s.scrollHeight; }
              return true;
            })(\(jsString(step.markdown)), \(step.caret))
            """)
            await pumpUntil(ProcessInfo.processInfo.systemUptime + step.delay)
        }
        let typingEnd = ProcessInfo.processInfo.systemUptime - recordingStart
        // Let the diagram settle into view.
        for _ in 0..<8 {
            _ = try await web.evaluateJavaScript("window.scrollTo({top: document.scrollingElement.scrollHeight, behavior: 'smooth'})")
            await pumpUntil(ProcessInfo.processInfo.systemUptime + 0.25)
        }
        let rendered = try await web.evaluateJavaScript("""
        ({tables: document.querySelectorAll('.vditor-ir .vditor-reset table').length,
          diagrams: document.querySelectorAll('.vditor-ir .vditor-reset svg').length,
          text: document.querySelector('.vditor-ir .vditor-reset').textContent.slice(0, 2000)})
        """)
        try await finishRecorder(recorder)
        try captureWindow(controller.window, to: output.appendingPathComponent("typing-\(theme)-poster.png"))
        let value = try await web.evaluateJavaScript("window.ouro.getValue()") as? String ?? ""
        XCTAssertTrue(value.contains("Ari reviews"), "the typed document must reach the diagram")
        records.append([
            "clip": "typing", "theme": theme, "movie": movie.lastPathComponent,
            "poster": "typing-\(theme)-poster.png", "steps": steps.count,
            "typingStartInMovie": typingStart, "typingEndInMovie": typingEnd,
            "rendered": rendered ?? NSNull(),
            "nativeStatus": statusText(controller),
            "method": "Each step sets the editor's Markdown to a longer prefix of the fixture through window.ouro.setValue, then places the caret at the end."
        ])
    }

    private struct Step { let markdown: String; let delay: Double; let caret: Bool }

    private func typingSteps(start: String, typed: String) -> [Step] {
        var steps: [Step] = []
        var acc = start
        let lines = typed.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line == "```mermaid" {
                var body: [String] = []
                var cursor = index + 1
                while cursor < lines.count, lines[cursor] != "```" { body.append(lines[cursor]); cursor += 1 }
                // The diagram grows one complete line at a time, so every render is a valid graph.
                for count in 2...max(2, body.count) {
                    let block = "```mermaid\n" + body.prefix(count).joined(separator: "\n") + "\n```\n"
                    steps.append(Step(markdown: acc + block, delay: 0.7, caret: false))
                }
                acc += "```mermaid\n" + body.joined(separator: "\n") + "\n```\n"
                index = cursor + 1
                continue
            }
            if line.hasPrefix("| ---") {
                acc += line + "\n"
                steps.append(Step(markdown: acc, delay: 0.25, caret: true))
            } else if line.isEmpty {
                acc += "\n"
                steps.append(Step(markdown: acc, delay: 0.12, caret: true))
            } else {
                var chunk = ""
                for character in line {
                    chunk.append(character)
                    if chunk.count == 3 {
                        acc += chunk; chunk = ""
                        steps.append(Step(markdown: acc, delay: 0.04, caret: true))
                    }
                }
                acc += chunk + "\n"
                steps.append(Step(markdown: acc, delay: 0.16, caret: true))
            }
            index += 1
        }
        return steps
    }

    // MARK: - Clip B: an agent's edit lands while you read

    private func agentClip(theme: String, full: String, fixtures: URL, output: URL) async throws {
        let sample = output.appendingPathComponent("agent-\(theme)", isDirectory: true)
        try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
        let document = sample.appendingPathComponent("Recipe import plan.md")
        try full.write(to: document, atomically: true, encoding: .utf8)
        try initRepository(sample, committing: ["Recipe import plan.md"])

        let (controller, web) = try await open(document, theme: theme, until: "Test recipes")
        defer { close(controller) }
        let geometry = """
        (function () {
          var root = document.querySelector('.vditor-ir .vditor-reset');
          var h = [...root.querySelectorAll('h2')].find(function (n) { return n.textContent.includes('Test recipes'); });
          var s = document.scrollingElement;
          var top = h.getBoundingClientRect().top + s.scrollTop - 14;
          return Math.max(0, Math.min(top, s.scrollHeight - s.clientHeight));
        })()
        """
        let target = try await web.evaluateJavaScript(geometry) as? Double ?? 0
        _ = try await web.evaluateJavaScript("window.scrollTo(0, \(max(0, target - 240)))")
        await pumpUntil(ProcessInfo.processInfo.systemUptime + 1.5)

        let movie = output.appendingPathComponent("agent-\(theme).mov")
        let (recorder, recordingStart) = try startRecorder(controller.window, to: movie, seconds: 12)
        defer { if recorder.isRunning { recorder.terminate() } }
        await pumpUntil(recordingStart + 1.6)
        _ = try await web.evaluateJavaScript("window.scrollTo({top: \(target), behavior: 'smooth'})")
        await pumpUntil(recordingStart + 4.0)

        let before = try String(contentsOf: document, encoding: .utf8)
        let emptyRows = "|  |  |  |  |\n|  |  |  |  |\n|  |  |  |  |\n"
        XCTAssertTrue(before.contains(emptyRows))
        let revised = before
            .replacingOccurrences(of: emptyRows, with: """
            | Mushroom risotto | 9 | 12 of 12 | Clean |
            | Sourdough focaccia | 11 | 9 of 10 | Guessed "a pinch" of salt |
            | Weeknight dal | 7 | 10 of 10 | Clean |

            """)
            .replacingOccurrences(of: "- [ ] Run the test recipes", with: "- [x] Run the test recipes")
            .replacingOccurrences(of: "- [ ] Place ingredients on their steps", with: "- [x] Place ingredients on their steps")
        XCTAssertNotEqual(revised, before)
        let agentWrite = ProcessInfo.processInfo.systemUptime - recordingStart
        try revised.write(to: document, atomically: true, encoding: .utf8)
        try revised.write(to: output.appendingPathComponent("agent-revised.md"), atomically: true, encoding: .utf8)
        try await wait(web, "window.ouro.getValue().includes('Sourdough focaccia')")
        let landed = ProcessInfo.processInfo.systemUptime - recordingStart
        try await wait(web, "document.querySelectorAll('.ouro-change-mark').length >= 1")
        let state = try await web.evaluateJavaScript("""
        ({scroll: scrollY, marks: document.querySelectorAll('.ouro-change-mark').length,
          checked: document.querySelectorAll('.vditor-ir .vditor-reset input[type=checkbox]:checked').length})
        """)
        try await finishRecorder(recorder)
        try captureWindow(controller.window, to: output.appendingPathComponent("agent-\(theme)-poster.png"))
        records.append([
            "clip": "agent", "theme": theme, "movie": movie.lastPathComponent,
            "poster": "agent-\(theme)-poster.png",
            "agentWriteInMovie": agentWrite, "editVisibleInMovie": landed,
            "state": state ?? NSNull(), "nativeStatus": statusText(controller),
            "method": "An atomic write to the open file from outside the editor; the app's file watcher reloads it in place."
        ])
    }

    // MARK: - Helpers

    private func open(_ document: URL, theme: String, until text: String) async throws -> (DocumentWindowController, WKWebView) {
        let controller = DocumentWindowController(filePath: document.path, selfTest: false, useAutosave: false)
        controller.model.setTextScale(textScale)
        controller.window.setContentSize(windowSize)
        controller.show(cascadeFrom: nil)
        let web = try await readyEditor(controller)
        controller.model.setTheme(id: theme)
        controller.syncChrome()
        try await wait(web, "document.body.textContent.includes(\(jsString(text)))")
        await pumpUntil(ProcessInfo.processInfo.systemUptime + 2.5)
        XCTAssertEqual(controller.window.appearance?.name, theme == "graphite" ? .darkAqua : .aqua)
        return (controller, web)
    }

    private func close(_ controller: DocumentWindowController) {
        controller.model.teardown()
        controller.window.delegate = nil
        controller.window.close()
        pump()
    }

    private func statusText(_ controller: DocumentWindowController) -> String {
        (controller.truthToolbarItem?.view as? NSButton)?.attributedTitle.string ?? ""
    }

    private func startRecorder(_ window: NSWindow, to url: URL, seconds: Int) throws -> (Process, Double) {
        let recorder = Process()
        recorder.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        recorder.arguments = ["-x", "-v", "-V", "\(seconds)", "-l", "\(window.windowNumber)", url.path]
        try recorder.run()
        return (recorder, ProcessInfo.processInfo.systemUptime)
    }

    private func finishRecorder(_ recorder: Process) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while recorder.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            await pumpUntil(ProcessInfo.processInfo.systemUptime + 0.2)
        }
        if recorder.isRunning { recorder.terminate(); recorder.waitUntilExit() }
        XCTAssertEqual(recorder.terminationStatus, 0)
    }

    private func initRepository(_ directory: URL, committing files: [String]) throws {
        try git(["-c", "init.defaultBranch=main", "init"], in: directory)
        try git(["config", "user.name", "Demo Agent"], in: directory)
        try git(["config", "user.email", "agent@demo.invalid"], in: directory)
        try git(["config", "core.quotePath", "false"], in: directory)
        if !files.isEmpty { try git(["add", "--"] + files, in: directory) }
        try git(["-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Recipe import plan baseline"], in: directory)
    }

    private func jsString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let json = String(data: data, encoding: .utf8)!
        return String(json.dropFirst().dropLast())
    }

    @discardableResult private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "PeriscopeMediaGit", code: Int(process.terminationStatus)) }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
    }

    private func captureWindow(_ window: NSWindow, to url: URL) throws {
        controllerFlush(window)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func controllerFlush(_ window: NSWindow) {
        pump()
        window.contentView?.displayIfNeeded()
        CATransaction.flush()
    }

    private func readyEditor(_ controller: DocumentWindowController) async throws -> WKWebView {
        func find(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<200 {
            pump()
            if controller.model.isReady, let view = controller.window.contentView, let web = find(view) { return web }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "PeriscopeMedia", code: 1)
    }

    private func wait(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<150 {
            pump()
            if try await web.evaluateJavaScript("!!(\(condition))") as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("periscope UI state not reached: \(condition)")
        throw NSError(domain: "PeriscopeMedia", code: 2)
    }

    private func pumpUntil(_ deadline: Double) async {
        while ProcessInfo.processInfo.systemUptime < deadline {
            pump()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func pump() {
        for _ in 0..<3 {
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.005),
                                          inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            NSApp.updateWindows()
        }
    }
}
