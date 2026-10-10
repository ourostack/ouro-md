import AppKit
import QuartzCore
import WebKit
import XCTest
@testable import OuroMD

/// Interactive rendering is strictly confined to the dedicated hosted job.
@MainActor
final class NativeHeaderRenderingTests: XCTestCase {
    func testHostedMovingDocumentBackdropBehindNativeHeader() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_HEADER_RENDERING"] == "1",
                          "never present test windows on an operator's Mac")
        try XCTSkipUnless(SystemDesign.usesGlass)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let output = URL(fileURLWithPath: env["OURO_HEADER_OUTPUT"] ?? ".build/header-rendering",
                         isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let underlap = env["OURO_HEADER_EXPECT_UNDERLAP"] != "0"
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }
        controller.window.setContentSize(NSSize(width: 1000, height: 700))
        controller.show(cascadeFrom: nil)
        pumpNativeApplicationEvents()
        let content = try XCTUnwrap(controller.window.contentView)
        func editor(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        for _ in 0..<200 {
            if controller.model.isReady && editor(in: content) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(controller.model.isReady, "must prove real editor readiness, not capture a blank body")
        let web = try XCTUnwrap(editor(in: content))
        var measurements: [[String: Any]] = []
        for theme in ["quartz", "graphite"] {
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            let document = (1...30).map {
                "## Passage \($0)\n\nMoving document backdrop \($0). Native title and toolbar controls must remain readable."
            }.joined(separator: "\n\n")
            controller.model.bridge?.setMarkdown(document)
            try await Task.sleep(for: .seconds(1))
            pumpNativeApplicationEvents()
            let preparation = try await web.evaluateJavaScript("""
            (() => {
              const root = document.querySelector(".vditor-ir .vditor-reset");
              if (!root || !root.textContent.includes("Moving document backdrop")) { return false; }
              Array.from(root.children).forEach((node, i) => {
                node.style.minHeight = "200px";
                node.style.setProperty("background", i % 4 < 2 ? "#ee6655" : "#3388ee", "important");
              });
              return getComputedStyle(root.children[1]).backgroundColor === "rgb(238, 102, 85)"
                && getComputedStyle(root.children[3]).backgroundColor === "rgb(51, 136, 238)";
            })()
            """)
            XCTAssertEqual(preparation as? Bool, true, "capture requires actual rendered document text")
            for (name, index) in [("warm", 1), ("cool", 3)] {
                _ = try await web.evaluateJavaScript("""
                (() => {
                  const node = document.querySelector(".vditor-ir .vditor-reset").children[\(index)];
                  window.scrollTo(0, scrollY + node.getBoundingClientRect().top + 80);
                })()
                """)
                try await Task.sleep(for: .seconds(1))
                let geometry = try await web.evaluateJavaScript("""
                ({scroll:scrollY, viewport:innerHeight, text:document.querySelector(".vditor-ir .vditor-reset").innerText,
                  sampleTop:document.querySelector(".vditor-ir .vditor-reset").children[\(index)].getBoundingClientRect().top,
                  sampleBottom:document.querySelector(".vditor-ir .vditor-reset").children[\(index)].getBoundingClientRect().bottom,
                  sampleColor:getComputedStyle(document.querySelector(".vditor-ir .vditor-reset").children[\(index)]).backgroundColor})
                """)
                let values = try XCTUnwrap(geometry as? [String: Any])
                XCTAssertGreaterThan(values["scroll"] as? Double ?? 0, 0, "the document must really scroll")
                XCTAssertLessThan(values["sampleTop"] as? Double ?? 0, -52,
                                  "the selected passage must span the native header sampling band")
                XCTAssertGreaterThan(values["sampleBottom"] as? Double ?? 0, 0)
                XCTAssertEqual(values["sampleColor"] as? String,
                               name == "warm" ? "rgb(238, 102, 85)" : "rgb(51, 136, 238)")
                let snapshot = try await web.takeSnapshot(configuration: nil)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(snapshot.tiffRepresentation)))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("\(theme)-\(name)-web.png"))
                content.displayIfNeeded()
                CATransaction.flush()
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", "\(controller.window.windowNumber)",
                                     output.appendingPathComponent("\(theme)-\(name)-window.png").path]
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0, "real native composition must be captured")
                // A separate compositor diagnostic distinguishes a missing
                // WebKit remote surface on a GPU-less runner from native glass.
                // It is explicitly labeled a raster proxy, never live WK proof.
                let proxy = try installRasterProxy(snapshot, web: web, content: content, underlap: underlap)
                proxy.display()
                CATransaction.flush()
                try await Task.sleep(for: .milliseconds(300))
                let composition = Process()
                composition.executableURL = capture.executableURL
                composition.arguments = ["-x", "-o", "-l", "\(controller.window.windowNumber)",
                                         output.appendingPathComponent("\(theme)-\(name)-raster-proxy-window.png").path]
                try composition.run()
                composition.waitUntilExit()
                XCTAssertEqual(composition.terminationStatus, 0)
                if underlap, #available(macOS 26, *) {
                    let panel = try XCTUnwrap(findBackdrop(in: content))
                    let originalParent = try XCTUnwrap(panel.superview)
                    let originalFrame = panel.frame
                    let rootFrame = panel.convert(panel.bounds, to: content)
                    panel.removeFromSuperview()
                    panel.frame = rootFrame
                    content.addSubview(panel, positioned: .above, relativeTo: nil)
                    panel.display()
                    CATransaction.flush()
                    try await Task.sleep(for: .milliseconds(300))
                    let rootComposition = Process()
                    rootComposition.executableURL = capture.executableURL
                    rootComposition.arguments = ["-x", "-o", "-l", "\(controller.window.windowNumber)",
                                                 output.appendingPathComponent("\(theme)-\(name)-root-panel-diagnostic-window.png").path]
                    try rootComposition.run()
                    rootComposition.waitUntilExit()
                    panel.removeFromSuperview()
                    originalParent.addSubview(panel)
                    panel.frame = originalFrame
                    XCTAssertEqual(rootComposition.terminationStatus, 0)
                }
                proxy.removeFromSuperview()
                let frame = web.convert(web.bounds, to: nil)
                let top = frame.maxY - controller.window.contentLayoutRect.maxY
                if underlap {
                    XCTAssertGreaterThan(top, 0)
                } else {
                    XCTAssertLessThanOrEqual(top, 1, "negative control must be the flat released layout")
                }
                measurements.append(["theme": theme, "state": name, "underlap": top,
                                     "webWidth": web.bounds.width, "webHeight": web.bounds.height,
                                     "layout": values, "title": controller.window.title,
                                     "applicationActive": NSApplication.shared.isActive,
                                     "windowKey": controller.window.isKeyWindow,
                                     "toolbarVisible": controller.window.toolbar?.isVisible ?? false])
            }

        }
        try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("measurements.json"))
    }

    private func pumpNativeApplicationEvents() {
        let app = NSApplication.shared
        for _ in 0..<10 {
            if let event = app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.05),
                                         inMode: .default, dequeue: true) {
                app.sendEvent(event)
            }
            app.updateWindows()
        }
    }

    private func installRasterProxy(_ snapshot: NSImage, web: WKWebView, content: NSView,
                                    underlap: Bool) throws -> NSImageView {
        let proxy = NSImageView()
        proxy.image = snapshot
        proxy.imageScaling = .scaleAxesIndependently
        if underlap {
            let glass = try XCTUnwrap(findBackdrop(in: content), "capture the production panel, never recreate it for proof")
            var ancestor = try XCTUnwrap(web.superview)
            var branch = glass
            while branch.superview !== ancestor {
                if let parent = branch.superview {
                    branch = parent
                } else {
                    ancestor = try XCTUnwrap(ancestor.superview)
                    branch = glass
                }
            }
            proxy.frame = web.convert(web.bounds, to: ancestor)
            ancestor.addSubview(proxy, positioned: .below, relativeTo: branch)
        } else {
            let parent = try XCTUnwrap(web.superview)
            proxy.frame = web.convert(web.bounds, to: parent)
            parent.addSubview(proxy, positioned: .above, relativeTo: web)
        }
        return proxy
    }

    private func findBackdrop(in view: NSView) -> NSView? {
        if view.identifier?.rawValue == "OuroMDDocumentHeaderBackdrop" { return view }
        return view.subviews.lazy.compactMap { self.findBackdrop(in: $0) }.first
    }
}
