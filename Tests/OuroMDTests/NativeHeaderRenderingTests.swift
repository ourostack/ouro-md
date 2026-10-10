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
        let output = URL(fileURLWithPath: env["OURO_HEADER_OUTPUT"] ?? ".build/header-rendering", isDirectory: true)
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
        var sampledHeaders: [[Double]] = []
        for theme in ["quartz", "graphite"] {
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            let document = (1...30).map {
                "## Passage \($0)\n\nMoving document backdrop \($0). Native title and toolbar controls must remain readable."
            }.joined(separator: "\n\n")
            controller.model.bridge?.setMarkdown(document)
            try await Task.sleep(for: .seconds(1))
            let prepared = try await web.evaluateJavaScript("""
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
            XCTAssertEqual(prepared as? Bool, true, "capture requires actual rendered document text and contrasting colors")
            var headerMeans: [[Double]] = []
            for (name, index) in [("warm", 1), ("cool", 3)] {
                _ = try await web.evaluateJavaScript("""
                (() => {
                  const node = document.querySelector(".vditor-ir .vditor-reset").children[\(index)];
                  window.scrollTo(0, scrollY + node.getBoundingClientRect().top + 80);
                })()
                """)
                try await Task.sleep(for: .seconds(1))
                pumpNativeApplicationEvents()
                let geometry = try await web.evaluateJavaScript("""
                ({scroll:scrollY, viewport:innerHeight,
                  sampleTop:document.querySelector(".vditor-ir .vditor-reset").children[\(index)].getBoundingClientRect().top,
                  sampleBottom:document.querySelector(".vditor-ir .vditor-reset").children[\(index)].getBoundingClientRect().bottom,
                  sampleColor:getComputedStyle(document.querySelector(".vditor-ir .vditor-reset").children[\(index)]).backgroundColor})
                """)
                let values = try XCTUnwrap(geometry as? [String: Any])
                XCTAssertGreaterThan(values["scroll"] as? Double ?? 0, 0)
                XCTAssertLessThan(values["sampleTop"] as? Double ?? 0, -52)
                XCTAssertGreaterThan(values["sampleBottom"] as? Double ?? 0, 0)
                let snapshot = try await web.takeSnapshot(configuration: nil)
                let webBitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(snapshot.tiffRepresentation)))
                try XCTUnwrap(webBitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("\(theme)-\(name)-web.png"))
                content.displayIfNeeded()
                CATransaction.flush()
                let imageURL = output.appendingPathComponent("\(theme)-\(name)-window.png")
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", "\(controller.window.windowNumber)", imageURL.path]
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: imageURL)))
                let header = meanRGB(bitmap, region: NSRect(x: 320, y: 12, width: 480, height: 26))
                headerMeans.append(header)
                let frame = web.convert(web.bounds, to: nil)
                measurements.append(["theme": theme, "state": name, "headerRGB": header,
                                     "coloredBodyPixels": coloredPixels(bitmap),
                                     "webHeight": web.bounds.height, "webTop": frame.maxY,
                                     "contentLayoutTop": controller.window.contentLayoutRect.maxY,
                                     "layout": values, "applicationActive": NSApplication.shared.isActive,
                                     "windowKey": controller.window.isKeyWindow])
            }
            sampledHeaders.append(headerMeans[0])
            sampledHeaders.append(headerMeans[1])
        }
        try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("measurements.json"))
        let liveBodyPaints = measurements.allSatisfy { ($0["coloredBodyPixels"] as? Int ?? 0) > 1000 }
        if env["OURO_HEADER_REQUIRE_LIVE_PAINT"] == "1" {
            XCTAssertTrue(liveBodyPaints, "blank native captures cannot certify glass, even when WK snapshots paint")
            for index in stride(from: 0, to: sampledHeaders.count, by: 2) {
                let change = zip(sampledHeaders[index], sampledHeaders[index + 1]).map { abs($0 - $1) }.max() ?? 0
                if underlap {
                    XCTAssertGreaterThan(change, 5, "the native header must visibly sample moving document colors")
                } else {
                    XCTAssertLessThan(change, 3, "released flat chrome is the unchanged-header negative control")
                }
            }
        }
    }

    private func pumpNativeApplicationEvents() {
        let app = NSApplication.shared
        for _ in 0..<10 {
            if let event = app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.05),
                                         inMode: .default, dequeue: true) { app.sendEvent(event) }
            app.updateWindows()
        }
    }

    private func meanRGB(_ bitmap: NSBitmapImageRep, region: NSRect) -> [Double] {
        var sum = [Double](repeating: 0, count: 3), count = 0.0
        for y in Int(region.minY)..<min(bitmap.pixelsHigh, Int(region.maxY)) {
            for x in Int(region.minX)..<min(bitmap.pixelsWide, Int(region.maxX)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                sum[0] += color.redComponent * 255
                sum[1] += color.greenComponent * 255
                sum[2] += color.blueComponent * 255
                count += 1
            }
        }
        return sum.map { $0 / max(1, count) }
    }

    private func coloredPixels(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in stride(from: 80, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 100, to: min(900, bitmap.pixelsWide), by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if max(color.redComponent, color.blueComponent) - color.greenComponent > 0.2 { count += 1 }
            }
        }
        return count
    }
}
