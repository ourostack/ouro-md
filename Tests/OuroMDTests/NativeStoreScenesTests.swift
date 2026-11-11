import AppKit
import QuartzCore
import WebKit
import XCTest
@testable import OuroMD

/// Photographs the Mac App Store scenes in the real app window: the Lantern Night folder in
/// distribution/app-store/scenes, opened in a DocumentWindowController, captured with screencapture.
/// scripts/store-frames/render.mjs puts each scene in its frame with the caption from
/// distribution/app-store/frames/spec.json. Runs only in a disposable hosted job (store-scenes.yml).
@MainActor
final class NativeStoreScenesTests: XCTestCase {
    func testStoreScenes() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_STORE_SCENES"] == "1",
                          "never present windows or capture an operator's desktop")
        let output = URL(fileURLWithPath: env["OURO_STORE_SCENES_OUTPUT"] ?? ".build/store-scenes").standardizedFileURL
        let scenes = output.appendingPathComponent("mac", isDirectory: true)
        try FileManager.default.createDirectory(at: scenes, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("distribution/app-store/scenes/Lantern Night")
        let project = output.appendingPathComponent("Lantern Night", isDirectory: true)
        if FileManager.default.fileExists(atPath: project.path) {
            try FileManager.default.trashItem(at: project, resultingItemURL: nil)
        }
        try FileManager.default.copyItem(at: source, to: project)
        let plan = project.appendingPathComponent("Plan.md")
        let points = try windowSize(env["OURO_STORE_WINDOW"] ?? "1440x900")

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let controller = DocumentWindowController(filePath: plan.path, selfTest: false, useAutosave: false)
        controller.model.setTextScale(1.1)
        defer {
            controller.model.teardown()
            controller.window.delegate = nil
            controller.window.close()
        }
        controller.show(cascadeFrom: nil)
        // The hosted screen can be smaller than the window. setFrame does not constrain to the screen, and
        // screencapture -l reads the window's own backing store, so the part past the screen edge is captured too.
        let screen = try XCTUnwrap(controller.window.screen ?? NSScreen.main)
        controller.window.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.maxY - points.height,
                                          width: points.width, height: points.height), display: true)
        let web = try await readyEditor(controller)
        try await wait(web, "document.body.textContent.includes('Lantern Night')")
        controller.model.openFolder(project)

        var records: [[String: Any]] = []
        defer {
            let info: [String: Any] = [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "screenPoints": [screen.frame.width, screen.frame.height],
                "screenScale": screen.backingScaleFactor,
                "windowPoints": [controller.window.frame.width, controller.window.frame.height],
                "windowScale": controller.window.backingScaleFactor,
                "scenes": records
            ]
            try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("scenes.json"))
        }
        func capture(_ scene: String) async throws {
            await settle(1.2)
            controller.window.contentView?.displayIfNeeded()
            CATransaction.flush()
            let url = scenes.appendingPathComponent("\(scene).png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", "\(controller.window.windowNumber)", url.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, scene)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)), scene)
            XCTAssertEqual(Double(bitmap.pixelsWide) / Double(bitmap.pixelsHigh), points.width / points.height,
                           accuracy: 0.02, "\(scene) is the whole window, not a clipped part of it")
            records.append(["scene": scene, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
                            "theme": controller.model.theme.id, "sidebar": controller.model.sidebarVisible,
                            "sidebarMode": controller.model.sidebarMode.rawValue])
        }
        func theme(_ id: String) async {
            controller.model.setTheme(id: id)
            controller.syncChrome()
            await settle(0.8)
        }
        func sidebar(_ mode: SidebarMode?) async {
            if let mode {
                controller.revealSidebar(mode: mode)
            } else if controller.model.sidebarVisible {
                controller.toggleSidebar()
            }
            await settle(0.8)
        }

        // 1. The agent's plan, read as a finished page, with its outline.
        await theme("quartz")
        await sidebar(.outline)
        _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
        try await capture("plan-outline")

        // 2. The agent rewrites the file on disk; Ouro MD marks what changed and keeps the reader's place.
        await sidebar(.files)
        let before = try String(contentsOf: plan, encoding: .utf8)
        let revised = before
            .replacingOccurrences(of: "Come down to Harbor Street on Friday night. Bring a lantern if you have one; we will have spares at the gate.",
                                  with: "You're invited to Harbor Street this Friday at dusk. Bring a lantern, or borrow one of ours at the gate.")
            .replacingOccurrences(of: "- One quiet corner with chairs and no speakers.",
                                  with: "- One quiet corner with chairs, tea and no speakers.")
        XCTAssertNotEqual(revised, before)
        try revised.write(to: plan, atomically: true, encoding: .utf8)
        try await wait(web, "window.ouro.getValue().includes('borrow one of ours')")
        try await wait(web, "document.querySelectorAll('.ouro-change-mark').length >= 2")
        try await capture("agent-change")

        // 3. Search the whole folder.
        await sidebar(.search)
        controller.model.searchQuery = "lantern"
        controller.model.runFolderSearch()
        for _ in 0..<100 where controller.model.searching || controller.model.searchResults.isEmpty {
            await settle(0.1)
        }
        XCTAssertFalse(controller.model.searchResults.isEmpty, "search finds the lanterns")
        try await capture("folder-search")

        // 4. The command palette, asked for themes.
        await sidebar(nil)
        controller.model.showCommandPalette()
        controller.model.commandPaletteQuery = "theme"
        try await capture("command-palette")
        controller.model.closeCommandPalette()

        // 5. The same page in the other three themes.
        for id in ["graphite", "manuscript", "newsprint"] {
            await theme(id)
            await sidebar(id == "graphite" ? .outline : nil)
            _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
            try await capture("theme-\(id)")
        }
        XCTAssertEqual(records.count, 7)
    }

    private func windowSize(_ text: String) throws -> NSSize {
        let parts = text.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { throw NSError(domain: "StoreScenes", code: 2) }
        return NSSize(width: parts[0], height: parts[1])
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
        throw NSError(domain: "StoreScenes", code: 1)
    }

    private func wait(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<150 {
            pump()
            if try await web.evaluateJavaScript("!!(\(condition))") as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("timed out waiting for \(condition)")
    }

    private func settle(_ seconds: Double) async {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
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
