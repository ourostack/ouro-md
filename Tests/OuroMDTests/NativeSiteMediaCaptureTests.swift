import AppKit
import OuroMDCore
import QuartzCore
import Vision
import WebKit
import XCTest
@testable import OuroMD

/// A shared-file story captured only in a disposable hosted desktop session.
@MainActor
final class NativeSiteMediaCaptureTests: XCTestCase {
    func testHostedPublicDocumentActions() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_SITE_MEDIA"] == "1",
                          "never present windows or capture an operator's desktop")
        XCTAssertEqual(OuroMDRelease.version, "0.9.97")
        let releasedCommit = try XCTUnwrap(env["OURO_SITE_MEDIA_RELEASE_COMMIT"])
        let output = URL(fileURLWithPath: env["OURO_SITE_MEDIA_OUTPUT"] ?? ".build/site-media").standardizedFileURL
        let sample = output.appendingPathComponent("shared-plan", isDirectory: true)
        try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let document = sample.appendingPathComponent("Launch plan.md")
        let original = try String(contentsOf: fixtures.appendingPathComponent("Launch plan.md"), encoding: .utf8)
        try original.write(to: document, atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("Harbor route.svg"),
                                        to: sample.appendingPathComponent("Harbor route.svg"))
        try git(["-c", "init.defaultBranch=main", "init"], in: sample)
        try git(["config", "user.name", "Harbor Example"], in: sample)
        try git(["config", "user.email", "harbor-example@example.invalid"], in: sample)
        try git(["config", "core.quotePath", "false"], in: sample)
        try git(["add", "--", "Launch plan.md", "Harbor route.svg"], in: sample)
        try git(["-c", "commit.gpgsign=false", "commit", "-m", "Fictional launch plan baseline"], in: sample)
        let baselineHead = try git(["rev-parse", "HEAD"], in: sample)
        XCTAssertEqual(try git(["status", "--porcelain=v1"], in: sample), "")
        try original.write(to: output.appendingPathComponent("01-committed-plan.md"), atomically: true, encoding: .utf8)
        if env["OURO_SITE_MEDIA_STANDARD_PROFILE"] == "1" {
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let controller = DocumentWindowController(filePath: document.path, selfTest: false, useAutosave: false)
        controller.model.setAutoSave(true)
        controller.model.setTextScale(1.25)
        defer {
            controller.model.teardown()
            controller.window.delegate = nil
            controller.window.close()
        }
        controller.window.setContentSize(NSSize(width: 800, height: 720))
        controller.show(cascadeFrom: nil)
        let web = try await readyEditor(controller)
        try await wait(web, "document.body.textContent.includes('Harbor launch plan')")
        XCTAssertEqual(controller.model.currentURL, document)
        XCTAssertFalse(controller.model.sidebarVisible)
        XCTAssertEqual(controller.model.documentTruth.state, .trackedClean)
        XCTAssertEqual(controller.model.documentTruth.repositoryRoot, sample.path)

        var records: [[String: Any]] = []
        var recognizedHeroes: [String: [String]] = [:]
        var pasteVideo: [String: Any] = [:]
        var story: [String: Any] = [
            "baselineHead": baselineHead, "baselineFile": "01-committed-plan.md",
            "humanAction": "Native Paste replaces ordinary feedback; the app autosaves the same Markdown file.",
            "agentAction": "Read the human-saved bytes, then atomically revise the invitation and support hours in that same file.",
            "automaticCommit": false
        ]
        let epoch = ProcessInfo.processInfo.systemUptime
        defer {
            try? JSONSerialization.data(withJSONObject: [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "version": OuroMDRelease.version, "releasedProductionCommit": releasedCommit,
                "records": records, "heroRecognizedBodyText": recognizedHeroes,
                "pasteVideo": pasteVideo, "story": story,
                "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "captureKind": "screencapture-owned-native-window"
            ], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("capture.json"))
        }
        func capture(_ scene: String, _ theme: String, _ index: Int) async throws {
            pump()
            XCTAssertFalse(controller.model.sidebarVisible, "no empty Outline sidebar in any website scene")
            XCTAssertEqual(controller.window.appearance?.name, theme == "graphite" ? .darkAqua : .aqua)
            let split = try XCTUnwrap(controller.window.contentViewController as? NSSplitViewController)
            XCTAssertTrue(split.splitViewItems[0].isCollapsed, "actual native sidebar must be closed")
            XCTAssertFalse(controller.model.statusBarVisible, "no redundant floating status clutter")
            XCTAssertEqual(try git(["rev-parse", "HEAD"], in: sample), baselineHead,
                           "the story must never imply an automatic commit")
            let porcelain = try git(["status", "--porcelain=v1", "--", "Launch plan.md"], in: sample)
            let statusButton = try XCTUnwrap(controller.truthToolbarItem?.view as? NSButton)
            let nativeStatus = statusButton.attributedTitle.string
            if scene == "hero" || scene == "scroll" || (scene == "paste" && index == 0) {
                XCTAssertEqual(porcelain, "")
                XCTAssertEqual(controller.model.documentTruth.state, .trackedClean)
                XCTAssertEqual(nativeStatus, "Committed")
            } else if scene == "reload" || (scene == "paste" && index == 24) {
                XCTAssertTrue(porcelain.hasPrefix(" M "))
                XCTAssertEqual(controller.model.documentTruth.state, .trackedModified)
                XCTAssertEqual(nativeStatus, "Modified")
                XCTAssertFalse(controller.model.isDirty, "saved editor buffer and modified Git file are different states")
            }
            controller.window.contentView?.displayIfNeeded()
            CATransaction.flush()
            let filename = "\(scene)-\(theme)-\(String(format: "%03d", index)).png"
            let url = output.appendingPathComponent(filename)
            try captureWindow(controller.window, to: url)
            let state = try await web.evaluateJavaScript("""
            ({scroll:scrollY, viewport:innerHeight,
              marks:document.querySelectorAll('.ouro-change-mark').length,
              visibleMarks:[...document.querySelectorAll('.ouro-change-mark')].filter(n => {
                const r=n.getBoundingClientRect(); return r.height>0 && r.top<innerHeight && r.bottom>0;
              }).length,
              nextVisible:!!document.getElementById('ouro-next-change') && !document.getElementById('ouro-next-change').hidden,
              glow:!!(CSS.highlights && CSS.highlights.get('ouro-change')),
              text:document.querySelector('.vditor-ir .vditor-reset').textContent})
            """)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            let statusRect = statusButton.convert(statusButton.bounds, to: nil)
            records.append([
                "filename": filename, "scene": scene, "theme": theme,
                "time": ProcessInfo.processInfo.systemUptime - epoch,
                "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
                "state": state ?? NSNull(), "sidebarVisible": controller.model.sidebarVisible,
                "editorZoom": controller.model.zoom, "nativeDirty": controller.model.isDirty,
                "nativeStatus": nativeStatus, "fullStatus": controller.model.documentTruthDisplayLabel,
                "gitPorcelain": porcelain, "gitHead": baselineHead,
                "statusCrop": ["x": max(0, statusRect.minX - 8),
                               "y": max(0, controller.window.frame.height - statusRect.maxY - 8),
                               "width": statusRect.width + 16, "height": statusRect.height + 16],
                "windowKey": controller.window.isKeyWindow, "applicationActive": NSApplication.shared.isActive
            ])
        }

        for theme in ["quartz", "graphite"] {
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
            try await Task.sleep(for: .seconds(2))
            try await capture("hero", theme, 0)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output.appendingPathComponent("hero-\(theme)-000.png"))))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.regionOfInterest = CGRect(x: 0.04, y: 0.05, width: 0.92, height: 0.86)
            try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
            let text = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            recognizedHeroes[theme] = text
            XCTAssertTrue(text.joined(separator: " ").contains("Invitation"), "actual readable native document, not just DOM")
            XCTAssertTrue(text.joined(separator: " ").contains("Decisions"))
        }
        controller.model.setTheme(id: "quartz")
        controller.syncChrome()
        _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
        await pumpUntil(ProcessInfo.processInfo.systemUptime + 1)
        for index in 0..<24 {
            _ = try await web.evaluateJavaScript("window.scrollTo(0,\(index * 20))")
            try await Task.sleep(for: .milliseconds(100))
            try await capture("scroll", "quartz", index)
        }
        _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
        let feedback = "Make the invitation warmer, and put opening-week support hours in the plan."
        let selected = try await web.evaluateJavaScript("""
        (() => {
          const root = document.querySelector('.vditor-ir .vditor-reset');
          const p = [...root.querySelectorAll('p')].find(p => p.textContent === 'Make the first invitation clearer.');
          root.focus(); const range = document.createRange(); range.selectNodeContents(p);
          getSelection().removeAllRanges(); getSelection().addRange(range);
          return getSelection().toString() === 'Make the first invitation clearer.';
        })()
        """)
        XCTAssertEqual(selected as? Bool, true)
        controller.window.makeFirstResponder(web)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(feedback, forType: .string)
        try await capture("paste", "quartz", 0)
        let recorder = Process()
        recorder.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        recorder.arguments = ["-x", "-v", "-V", "8", "-l", "\(controller.window.windowNumber)",
                              output.appendingPathComponent("paste-native.mov").path]
        try recorder.run()
        defer { if recorder.isRunning { recorder.terminate() } }
        let recordingStart = ProcessInfo.processInfo.systemUptime
        await pumpUntil(recordingStart + 2)
        XCTAssertTrue(recorder.isRunning)
        pasteVideo["actionAfterRecorderLaunch"] = ProcessInfo.processInfo.systemUptime - recordingStart
        XCTAssertTrue(NSApp.sendAction(#selector(NSText.paste(_:)), to: web, from: nil))
        await pumpUntil(ProcessInfo.processInfo.systemUptime + 0.25)
        pasteVideo["glowObservedAfterNativePaste"] = try await web.evaluateJavaScript("!!(CSS.highlights && CSS.highlights.get('ouro-change'))") as? Bool ?? false
        pasteVideo["feedback"] = try await web.evaluateJavaScript("window.__ouroLastChangeFlash") ?? NSNull()
        for index in 1..<24 {
            try await Task.sleep(for: .milliseconds(70))
            try await capture("paste", "quartz", index)
        }
        for _ in 0..<150 {
            pump()
            if !controller.model.isDirty,
               (try String(contentsOf: document, encoding: .utf8)).contains(feedback) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await capture("paste", "quartz", 24)
        let humanSaved = try String(contentsOf: document, encoding: .utf8)
        XCTAssertTrue(humanSaved.contains(feedback), "agent must read the actual autosaved human edit")
        try humanSaved.write(to: output.appendingPathComponent("02-human-saved-plan.md"), atomically: true, encoding: .utf8)
        story["humanSavedFile"] = "02-human-saved-plan.md"
        story["humanGitDiff"] = try git(["diff", "--", "Launch plan.md"], in: sample)
        await pumpUntil(recordingStart + 9)
        XCTAssertFalse(recorder.isRunning)
        if recorder.isRunning { recorder.terminate(); recorder.waitUntilExit() }
        XCTAssertEqual(recorder.terminationStatus, 0)
        pasteVideo["recordingExitStatus"] = recorder.terminationStatus
        pasteVideo["recordingFile"] = "paste-native.mov"

        _ = try await web.evaluateJavaScript("getSelection().removeAllRanges(); window.scrollTo(0,0)")
        await pumpUntil(ProcessInfo.processInfo.systemUptime + 1)
        let initialMarks = try await web.evaluateJavaScript("document.querySelectorAll('.ouro-change-mark').length") as? Int ?? -1
        XCTAssertEqual(initialMarks, 0, "ordinary human edit is not an unseen external-agent cue")
        try await capture("reload", "quartz", 0)
        // This is the agent's input: bytes read from the exact human-saved file.
        let agentInput = try String(contentsOf: document, encoding: .utf8)
        XCTAssertEqual(agentInput, humanSaved)
        let agentRevision = agentInput
            .replacingOccurrences(of: "Join us for the garden opening. Take a short walk, share a cup of tea, and tell us what would make your next visit easier.",
                                  with: "You're invited to a quiet garden morning. Come for a walk and a cup of tea; help us make the next visit even better.")
            .replacingOccurrences(of: "The welcome desk will answer questions during opening week. Confirm its hours before sending the invitation.",
                                  with: "The welcome desk is open 9–11 each morning during opening week. Ask the host at the garden gate for help.")
        XCTAssertNotEqual(agentRevision, agentInput)
        try agentRevision.write(to: document, atomically: true, encoding: .utf8)
        try agentRevision.write(to: output.appendingPathComponent("03-agent-revised-plan.md"), atomically: true, encoding: .utf8)
        story["agentInputFile"] = "02-human-saved-plan.md"
        story["agentResultFile"] = "03-agent-revised-plan.md"
        story["agentGitDiff"] = try git(["diff", "--", "Launch plan.md"], in: sample)
        try await wait(web, "window.ouro.getValue().includes('welcome desk is open 9–11')")
        try await wait(web, "document.querySelectorAll('.ouro-change-mark').length >= 2")
        let scroll = try await web.evaluateJavaScript("scrollY") as? Double ?? -1
        XCTAssertEqual(scroll, 0, accuracy: 1, "external revision must preserve the person's reading position")
        for index in 1..<25 {
            if index == 12 {
                let enabled = try await web.evaluateJavaScript("!document.getElementById('ouro-next-change').hidden") as? Bool
                XCTAssertEqual(enabled, true)
                _ = try await web.evaluateJavaScript("document.getElementById('ouro-next-change').click()")
            }
            try await Task.sleep(for: .milliseconds(100))
            try await capture("reload", "quartz", index)
        }
        let revisedScroll = try await web.evaluateJavaScript("scrollY") as? Double ?? 0
        XCTAssertGreaterThan(revisedScroll, 0)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], in: sample), baselineHead)
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
        guard process.terminationStatus == 0 else { throw NSError(domain: "SiteMediaGit", code: Int(process.terminationStatus)) }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
    }

    private func captureWindow(_ window: NSWindow, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
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
        throw NSError(domain: "NativeSiteMedia", code: 1)
    }

    private func wait(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<150 {
            pump()
            if try await web.evaluateJavaScript("!!(\(condition))") as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("actual shared-document UI state not reached: \(condition)")
        throw NSError(domain: "NativeSiteMedia", code: 2)
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
