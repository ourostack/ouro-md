import AppKit
import QuartzCore
import Vision
import WebKit
import XCTest
@testable import OuroMD

/// Real-window media, never a WK snapshot or a composited demonstration.
@MainActor
final class NativeSiteMediaCaptureTests: XCTestCase {
    func testHostedPublicDocumentActions() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_SITE_MEDIA"] == "1",
                          "interactive capture is forbidden on the operator's Mac")
        let output = URL(fileURLWithPath: env["OURO_SITE_MEDIA_OUTPUT"] ?? ".build/site-media").standardizedFileURL
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Harbor field notes.md")
        let original = try String(contentsOf: fixture, encoding: .utf8)
        let document = output.appendingPathComponent("Harbor field notes.md")
        try original.write(to: document, atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(at: fixture.deletingLastPathComponent().appendingPathComponent("Harbor route.svg"),
                                        to: output.appendingPathComponent("Harbor route.svg"))
        if env["OURO_SITE_MEDIA_STANDARD_PROFILE"] == "1" {
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                           "a preference write alone is not evidence of the actual native capture profile")
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let controller = DocumentWindowController(filePath: document.path, selfTest: false, useAutosave: false)
        controller.model.autoSaveEnabled = false
        defer {
            controller.model.teardown()
            controller.window.delegate = nil
            controller.window.close()
        }
        controller.window.setContentSize(NSSize(width: 1120, height: 800))
        controller.show(cascadeFrom: nil)
        let web = try await readyEditor(controller)
        XCTAssertEqual(controller.model.currentURL, document)
        try await wait(web, "document.body.textContent.includes('A thoughtful first visit')")
        try await wait(web, "Array.from(document.images).some(i => i.alt === 'A sketch of the fictional harbor walking loop' && i.complete && i.naturalWidth > 0)")
        for _ in 0..<100 {
            if controller.model.outlineItems.count > 5 { break }
            pump()
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(controller.model.isDirty)
        XCTAssertGreaterThan(controller.model.outlineItems.count, 5)
        controller.revealSidebar(mode: .outline)
        try await Task.sleep(for: .seconds(1))
        var records: [[String: Any]] = []
        var heroText: [String: [String]] = [:]
        var heroOCRErrors: [String: String] = [:]
        let epoch = ProcessInfo.processInfo.systemUptime
        func capture(_ scene: String, _ theme: String, _ index: Int) async throws {
            pump()
            controller.window.contentView?.displayIfNeeded()
            CATransaction.flush()
            let filename = "\(scene)-\(theme)-\(String(format: "%03d", index)).png"
            let url = output.appendingPathComponent(filename)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", "\(controller.window.windowNumber)", url.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let state = try await web.evaluateJavaScript("""
            ({scroll:scrollY, viewport:innerHeight, theme:document.body.className,
              marks:document.querySelectorAll('.ouro-change-mark').length,
              nextVisible:!!document.getElementById('ouro-next-change') && !document.getElementById('ouro-next-change').hidden,
              glow:!!(window.CSS && CSS.highlights && CSS.highlights.get('ouro-change')),
              mapTop:document.querySelector('img[alt="A sketch of the fictional harbor walking loop"]').getBoundingClientRect().top,
              mapBottom:document.querySelector('img[alt="A sketch of the fictional harbor walking loop"]').getBoundingClientRect().bottom,
              text:document.querySelector('.vditor-ir .vditor-reset').textContent})
            """)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            records.append(["filename": filename, "scene": scene, "theme": theme,
                            "time": ProcessInfo.processInfo.systemUptime - epoch,
                            "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
                            "state": state ?? NSNull(), "windowKey": controller.window.isKeyWindow,
                            "outlineCount": controller.model.outlineItems.count,
                            "sidebarVisible": controller.model.sidebarVisible,
                            "nativeDirty": controller.model.isDirty,
                            "applicationActive": NSApplication.shared.isActive])
        }
        defer {
            try? JSONSerialization.data(withJSONObject: [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "records": records,
                "heroRecognizedBodyText": heroText,
                "heroOCRErrors": heroOCRErrors,
                "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "captureKind": "screencapture-owned-native-window"
            ], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("capture.json"))
        }
        for theme in ["quartz", "graphite"] {
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
            try await Task.sleep(for: .seconds(2))
            try await capture("hero", theme, 0)
            let url = output.appendingPathComponent("hero-\(theme)-000.png")
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Exclude the real sidebar and title so they cannot conceal a blank WK body.
            let frame = web.convert(web.bounds, to: nil)
            request.regionOfInterest = CGRect(x: (frame.minX + 8) / controller.window.frame.width, y: 0.05,
                                             width: (frame.width - 16) / controller.window.frame.width, height: 0.83)
            do {
                try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
            } catch {
                heroOCRErrors[theme] = String(describing: error)
                if env["OURO_SITE_MEDIA_REQUIRE_BODY_PAINT"] == "1" {
                    XCTFail("native document OCR verification unavailable: \(error)")
                }
            }
            let recognized = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            heroText[theme] = recognized
            if env["OURO_SITE_MEDIA_REQUIRE_BODY_PAINT"] == "1" {
                XCTAssertTrue(recognized.joined(separator: " ").contains("thoughtful first visit"),
                              "native screenshot must contain readable fixture content, not just live DOM/AX/sidebar")
                XCTAssertTrue(recognized.joined(separator: " ").contains("Weekend rhythm"))
            }
        }
        if env["OURO_SITE_MEDIA_RENDERER_DIAGNOSTICS"] == "1" {
            // A region capture tests WindowServer's on-screen composition path,
            // independently of screencapture's per-window layer capture.
            let frame = controller.window.frame
            let screen = try XCTUnwrap(controller.window.screen)
            let region = "\(Int(frame.minX)),\(Int(screen.frame.maxY - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-R", region, output.appendingPathComponent("diagnostic-onscreen-region.png").path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            controller.window.toolbar?.isVisible = false
            try await Task.sleep(for: .seconds(2))
            try await capture("diagnostic-no-toolbar", "graphite", 0)
            controller.window.toolbar?.isVisible = true
            controller.window.setContentSize(NSSize(width: 1121, height: 801))
            try await Task.sleep(for: .seconds(2))
            try await capture("diagnostic-resized", "graphite", 0)
            controller.window.setContentSize(NSSize(width: 1120, height: 800))
        }
        controller.model.setTheme(id: "quartz")
        controller.syncChrome()
        _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
        try await Task.sleep(for: .seconds(1))
        for index in 0..<40 {
            _ = try await web.evaluateJavaScript("window.scrollTo(0,\(index * 25))")
            try await Task.sleep(for: .milliseconds(100))
            try await capture("scroll", "quartz", index)
        }
        let offset = try await web.evaluateJavaScript("scrollY") as? Double ?? 0
        XCTAssertGreaterThan(offset, 900, "motion must be real document scrolling")
        _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
        try await Task.sleep(for: .seconds(1))
        let initialMarks = try await web.evaluateJavaScript("document.querySelectorAll('.ouro-change-mark').length") as? Int
        XCTAssertEqual(initialMarks, 0,
                       "unchanged-file negative control")
        try await capture("reload", "quartz", 0)
        let changed = original.replacingOccurrences(of: "Keep sentences short", with: "Keep the language warm and sentences short")
            .replacingOccurrences(of: "ready after the route review", with: "ready on Saturday after the route review")
        try changed.write(to: document, atomically: true, encoding: .utf8)
        try await wait(web, "window.ouro.getValue().includes('ready on Saturday')")
        XCTAssertFalse(controller.model.isDirty, "must be a real clean file-watcher reload")
        try await wait(web, "document.querySelectorAll('.ouro-change-mark').length >= 2")
        let reloadScroll = try await web.evaluateJavaScript("scrollY") as? Double ?? -1
        XCTAssertEqual(reloadScroll, 0, accuracy: 1)
        for index in 1..<25 {
            if index == 12 {
                // Activate the actual accessible control, not the reload/mark implementation.
                _ = try await web.evaluateJavaScript("document.getElementById('ouro-next-change').click()")
            }
            try await Task.sleep(for: .milliseconds(100))
            try await capture("reload", "quartz", index)
        }
        let nextScroll = try await web.evaluateJavaScript("scrollY") as? Double ?? 0
        XCTAssertGreaterThan(nextScroll, 0)
        _ = try await web.evaluateJavaScript("""
        (() => {
          window.scrollTo(0,0);
          const p = [...document.querySelectorAll('.vditor-ir .vditor-reset p')]
            .find(p => p.textContent.startsWith('Begin at the old lighthouse.'));
          document.querySelector('.vditor-ir .vditor-reset').focus();
          const range = document.createRange(); range.selectNodeContents(p); range.collapse(false);
          getSelection().removeAllRanges(); getSelection().addRange(range);
        })()
        """)
        controller.window.makeFirstResponder(web)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(" Bring a notebook and leave room for discovery.", forType: .string)
        try await capture("paste", "quartz", 0)
        let sent = NSApplication.shared.sendAction(#selector(NSText.paste(_:)), to: web, from: nil)
        XCTAssertTrue(sent, "the real WK native Paste responder must accept the action")
        try await wait(web, "window.ouro.getValue().includes('Bring a notebook')")
        for _ in 0..<100 {
            if controller.model.isDirty { break }
            pump()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(controller.model.isDirty)
        for index in 1..<25 {
            try await Task.sleep(for: .milliseconds(70))
            try await capture("paste", "quartz", index)
        }
    }

    private func readyEditor(_ controller: DocumentWindowController) async throws -> WKWebView {
        func find(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<200 {
            pump()
            if controller.model.isReady, let content = controller.window.contentView,
               let web = find(content) { return web }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "NativeSiteMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: "real editor never became ready"])
    }

    private func wait(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<150 {
            pump()
            if try await web.evaluateJavaScript("!!(\(condition))") as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("actual UI state not reached: \(condition)")
        throw NSError(domain: "NativeSiteMedia", code: 2)
    }

    private func pump() {
        let app = NSApplication.shared
        for _ in 0..<3 {
            if let event = app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.005),
                                         inMode: .default, dequeue: true) { app.sendEvent(event) }
            app.updateWindows()
        }
    }
}
