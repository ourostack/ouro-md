import AppKit
import QuartzCore
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
        let output = URL(fileURLWithPath: env["OURO_SITE_MEDIA_OUTPUT"] ?? ".build/site-media")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Harbor field notes.md")
        let original = try String(contentsOf: fixture, encoding: .utf8)
        let document = output.appendingPathComponent("Harbor field notes.md")
        try original.write(to: document, atomically: true, encoding: .utf8)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let controller = DocumentWindowController(filePath: document.path, selfTest: false, useAutosave: false)
        controller.model.autoSaveEnabled = false
        controller.model.setSidebarVisible(true)
        controller.model.setSidebarMode(.outline)
        defer {
            controller.window.delegate = nil
            controller.window.close()
        }
        controller.window.setContentSize(NSSize(width: 1120, height: 800))
        controller.show(cascadeFrom: nil)
        let web = try await readyEditor(controller)
        XCTAssertEqual(controller.model.currentURL, document)
        try await wait(web, "document.body.textContent.includes('A thoughtful first visit')")
        XCTAssertFalse(controller.model.isDirty)
        XCTAssertGreaterThan(controller.model.outlineItems.count, 5)
        var records: [[String: Any]] = []
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
              text:document.querySelector('.vditor-ir .vditor-reset').textContent})
            """)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            records.append(["filename": filename, "scene": scene, "theme": theme,
                            "time": ProcessInfo.processInfo.systemUptime - epoch,
                            "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
                            "state": state ?? NSNull(), "windowKey": controller.window.isKeyWindow,
                            "applicationActive": NSApplication.shared.isActive])
        }
        defer {
            try? JSONSerialization.data(withJSONObject: [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "records": records,
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
          p.focus();
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
