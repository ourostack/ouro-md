import AppKit
import QuartzCore
import SwiftUI
import WebKit
import XCTest
@testable import OuroMD

/// Interactive rendering is strictly confined to the dedicated hosted job.
@MainActor
final class NativeHeaderRenderingTests: XCTestCase {
    func testHostedNativeHeaderShowsRealContentWithoutReflectingDocumentEdges() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_HEADER_RENDERING"] == "1",
                          "never present test windows on an operator's Mac")
        try XCTSkipUnless(SystemDesign.usesGlass)
        if env["OURO_HEADER_STANDARD_PROFILE"] == "1" {
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        }

        @available(macOS 26, *)
        private struct HeaderProbeBackdrop: NSViewRepresentable {
            func makeNSView(context: Context) -> NSGlassEffectView {
                let view = HeaderProbeGlass()
                view.style = .regular
                view.cornerRadius = 0
                view.contentView = NSView()
                view.identifier = NSUserInterfaceItemIdentifier("OuroMDDocumentHeaderBackdrop")
                view.setAccessibilityElement(false)
                return view
            }

            func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
        }

        @available(macOS 26, *)
        private final class HeaderProbeGlass: NSGlassEffectView {
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let output = URL(fileURLWithPath: env["OURO_HEADER_OUTPUT"] ?? ".build/header-rendering", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let expectsGlass = env["OURO_HEADER_EXPECT_GLASS"] != "0"
        let probesPublicViewport = env["OURO_HEADER_PUBLIC_VIEWPORT_PROBE"] == "1"
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        defer { controller.window.close() }
        controller.window.setContentSize(NSSize(width: 1000, height: 700))
        if probesPublicViewport, #available(macOS 26, *) {
            controller.window.contentView = NSHostingView(rootView: GeometryReader { geometry in
                ZStack(alignment: .top) {
                    EditorWebView(model: controller.model)
                        .ignoresSafeArea(.container, edges: .top)
                    VStack(spacing: 0) {
                        HeaderProbeBackdrop().frame(height: geometry.safeAreaInsets.top)
                        Spacer(minLength: 0)
                    }
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
                }
            })
        }
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
        let nativeHeaderInset = controller.window.frame.height - controller.window.contentLayoutRect.maxY
        if probesPublicViewport, #available(macOS 26, *) {
            web.obscuredContentInsets = .zero
            _ = try await web.evaluateJavaScript("""
            (() => {
              const css = document.createElement("style");
              css.textContent = "html{scroll-padding-top:\(nativeHeaderInset / web.pageZoom)px!important}body{padding-top:\(nativeHeaderInset / web.pageZoom)px!important}";
              document.head.appendChild(css);
            })()
            """)
        }
        if expectsGlass, #available(macOS 26, *) {
            func panel(in view: NSView) -> NSGlassEffectView? {
                if let glass = view as? NSGlassEffectView,
                   glass.identifier?.rawValue == "OuroMDDocumentHeaderBackdrop" { return glass }
                return view.subviews.lazy.compactMap { panel(in: $0) }.first
            }
            let glass = try XCTUnwrap(panel(in: content), "capture the actual production glass, not raw extended content")
            let band = glass.convert(glass.bounds, to: nil)
            XCTAssertEqual(band.minY, controller.window.contentLayoutRect.maxY, accuracy: 1)
            XCTAssertEqual(band.maxY, content.convert(content.bounds, to: nil).maxY, accuracy: 1)
            XCTAssertEqual(glass.style, .regular)
            XCTAssertNil(glass.hitTest(NSPoint(x: glass.bounds.midX, y: glass.bounds.midY)))
            XCTAssertFalse(glass.isAccessibilityElement())
            let sidebar = try XCTUnwrap(controller.window.toolbar?.items.first)
            let action = try XCTUnwrap(sidebar.action)
            let before = controller.model.sidebarVisible
            XCTAssertTrue(NSApplication.shared.sendAction(action, to: sidebar.target, from: sidebar))
            XCTAssertNotEqual(controller.model.sidebarVisible, before, "native toolbar action must not be intercepted by the panel")
            XCTAssertTrue(NSApplication.shared.sendAction(action, to: sidebar.target, from: sidebar))
            XCTAssertEqual(controller.model.sidebarVisible, before)
        }
        var measurements: [[String: Any]] = []
        var sampledHeaders: [[Double]] = []
        for theme in ["quartz", "graphite"] {
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            controller.model.bridge?.setMarkdown("# HEADER ECHO FIXTURE\n\nOnly synthetic document content.")
            try await Task.sleep(for: .seconds(1))
            var topHeaders: [[Double]] = []
            for marked in [false, true] {
                let geometry = try await web.evaluateJavaScript("""
                (() => {
                  const root = document.querySelector(".vditor-ir .vditor-reset");
                  if (!root || !root.textContent.includes("HEADER ECHO FIXTURE")) { return null; }
                  const first = root.firstElementChild;
                  first.style.cssText = "margin:0;min-height:200px;font-size:48px;";
                  first.style.setProperty("margin", "0", "important");
                  first.style.setProperty("background", \(marked ? "\"#ee2211\"" : "getComputedStyle(document.body).backgroundColor"), "important");
                  first.style.setProperty("color", \(marked ? "\"black\"" : "\"transparent\""), "important");
                  window.scrollTo(0, 0);
                  return {scroll:scrollY, firstTop:first.getBoundingClientRect().top,
                    firstBottom:first.getBoundingClientRect().bottom, viewport:innerHeight};
                })()
                """)
                let values = try XCTUnwrap(geometry as? [String: Any])
                XCTAssertEqual(values["scroll"] as? Double, 0, "the regression must be at true scroll-top")
                XCTAssertEqual(try XCTUnwrap(values["firstTop"] as? Double),
                               30 + (probesPublicViewport ? nativeHeaderInset / web.pageZoom : 0), accuracy: 1,
                               "the fixture must occupy the document edge below the header, not evade the mirrored region")
                try await Task.sleep(for: .seconds(1))
                pumpNativeApplicationEvents()
                let state = marked ? "top-marked" : "top-blank"
                let bitmap = try captureWindow(controller.window, to: output.appendingPathComponent("\(theme)-\(state)-window.png"))
                let header = meanRGB(bitmap, region: headerRegion(in: bitmap, window: controller.window))
                topHeaders.append(header)
                measurements.append(["theme": theme, "state": state, "headerRGB": header,
                                     "layout": values, "coloredBodyPixels": coloredPixels(bitmap)])
                if marked && env["OURO_HEADER_REQUIRE_LIVE_PAINT"] == "1" {
                    XCTAssertGreaterThan(coloredPixels(bitmap), 1000, "a blank native capture cannot certify no text echo")
                }
            }
            let topChange = zip(topHeaders[0], topHeaders[1]).map { abs($0 - $1) }.max() ?? 0
            if env["OURO_HEADER_REQUIRE_LIVE_PAINT"] == "1" {
                if env["OURO_HEADER_EXPECT_ECHO"] == "1" {
                    XCTAssertGreaterThan(topChange, 5, "the known-bad reflected-edge release must expose its false backdrop")
                } else {
                    XCTAssertLessThan(topChange, 3, "content entirely below the header must not be mirrored into it at scroll-top")
                }
            }
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
                let bitmap = try captureWindow(controller.window, to: imageURL)
                let header = meanRGB(bitmap, region: headerRegion(in: bitmap, window: controller.window))
                headerMeans.append(header)
                let frame = web.convert(web.bounds, to: nil)
                measurements.append(["theme": theme, "state": name, "headerRGB": header,
                                     "coloredBodyPixels": coloredPixels(bitmap),
                                     "webHeight": web.bounds.height, "webTop": frame.maxY,
                                     "contentLayoutTop": controller.window.contentLayoutRect.maxY,
                                     "layout": values, "applicationActive": NSApplication.shared.isActive,
                                     "windowKey": controller.window.isKeyWindow])
                if env["OURO_HEADER_ONSCREEN_DIAGNOSTIC"] == "1" {
                    let screen = try XCTUnwrap(controller.window.screen)
                    let rect = controller.window.frame
                    let region = "\(Int(rect.minX)),\(Int(screen.frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
                    let regionURL = output.appendingPathComponent("\(theme)-\(name)-onscreen.png")
                    let onscreen = Process()
                    onscreen.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    onscreen.arguments = ["-x", "-R", region, regionURL.path]
                    try onscreen.run()
                    onscreen.waitUntilExit()
                    XCTAssertEqual(onscreen.terminationStatus, 0)
                    let pixels = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: regionURL)))
                    measurements[measurements.count - 1]["onscreenColoredBodyPixels"] = coloredPixels(pixels)
                    measurements[measurements.count - 1]["onscreenHeaderRGB"] = meanRGB(pixels, region: headerRegion(in: pixels, window: controller.window))
                }
            }
            sampledHeaders.append(headerMeans[0])
            sampledHeaders.append(headerMeans[1])
        }
        if probesPublicViewport {
            controller.model.bridge?.setMarkdown((1...80).map { "Native caret paragraph \($0)." }.joined(separator: "\n\n"))
            try await Task.sleep(for: .seconds(1))
            var caretStates: [[String: Any]] = []
            for avoidsHeader in [false, true] {
                let inset = avoidsHeader ? nativeHeaderInset / web.pageZoom : 0
                _ = try await web.evaluateJavaScript("""
                (() => {
                  document.documentElement.style.setProperty("scroll-padding-top", "\(inset)px", "important");
                  const root = document.querySelector(".vditor-ir .vditor-reset");
                  const node = root.children[30].firstChild;
                  root.focus({preventScroll:true});
                  const range = document.createRange();
                  range.setStart(node, 2); range.collapse(true);
                  const selection = getSelection();
                  selection.removeAllRanges(); selection.addRange(range);
                  window.scrollTo(0, scrollY + range.getBoundingClientRect().top - \(nativeHeaderInset / web.pageZoom + 5));
                })()
                """)
                XCTAssertTrue(controller.window.makeFirstResponder(web))
                for _ in 0..<12 {
                    let event = try XCTUnwrap(NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: controller.window.windowNumber, context: nil,
                        characters: "\u{F700}", charactersIgnoringModifiers: "\u{F700}",
                        isARepeat: false, keyCode: 126
                    ))
                    controller.window.sendEvent(event)
                    pumpNativeApplicationEvents()
                    try await Task.sleep(for: .milliseconds(100))
                }
                let result = try await web.evaluateJavaScript("""
                (() => {
                  const selection = getSelection(), range = selection.getRangeAt(0), rect = range.getBoundingClientRect();
                  return {top:rect.top,bottom:rect.bottom,height:rect.height,scroll:scrollY,
                    text:selection.anchorNode.textContent,offset:selection.anchorOffset,
                    paragraph:Array.from(document.querySelector(".vditor-ir .vditor-reset").children)
                      .indexOf(selection.anchorNode.parentElement.closest("p"))};
                })()
                """)
                var values = try XCTUnwrap(result as? [String: Any])
                values["avoidsHeader"] = avoidsHeader
                caretStates.append(values)
                XCTAssertGreaterThan(try XCTUnwrap(values["height"] as? Double), 0)
                let paragraph = try XCTUnwrap(values["paragraph"] as? Int)
                XCTAssertGreaterThanOrEqual(paragraph, 0)
                XCTAssertLessThan(paragraph, 30, "native arrow input must actually move the caret")
                if avoidsHeader {
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(values["top"] as? Double),
                                               nativeHeaderInset / web.pageZoom - 1,
                                               "standard scroll-padding must keep native keyboard editing below the glass")
                } else {
                    XCTAssertLessThan(try XCTUnwrap(values["top"] as? Double),
                                      nativeHeaderInset / web.pageZoom - 5,
                                      "the unprotected control must expose native caret occlusion")
                }
            }
            measurements[0]["publicViewportCaretProbe"] = caretStates
        }
        if expectsGlass && !probesPublicViewport && env["OURO_HEADER_REQUIRE_FULLSCREEN"] == "1", #available(macOS 26, *) {
            var fullscreenStates: [[String: Any]] = []
            for fullscreen in [true, false] {
                var completed = false
                let notification = fullscreen ? NSWindow.didEnterFullScreenNotification : NSWindow.didExitFullScreenNotification
                let observer = NotificationCenter.default.addObserver(forName: notification,
                                                                      object: controller.window, queue: .main) { _ in
                    MainActor.assumeIsolated { completed = true }
                }
                controller.window.toggleFullScreen(nil)
                for _ in 0..<40 {
                    pumpNativeApplicationEvents()
                    if completed { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                NotificationCenter.default.removeObserver(observer)
                XCTAssertTrue(completed, "wait for AppKit's completed transition, not its early style-mask change")
                XCTAssertEqual(controller.window.styleMask.contains(.fullScreen), fullscreen)
                for visible in [false, true] {
                    controller.window.toolbar?.isVisible = visible
                    for _ in 0..<20 {
                        pumpNativeApplicationEvents()
                        content.layoutSubtreeIfNeeded()
                        var editingTop = web.convert(web.bounds, to: nil).maxY
                        editingTop -= web.obscuredContentInsets.top
                        if abs(editingTop - controller.window.contentLayoutRect.maxY) <= 1 { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    let top = web.convert(web.bounds, to: nil).maxY - web.obscuredContentInsets.top
                    XCTAssertEqual(top, controller.window.contentLayoutRect.maxY, accuracy: 1,
                                   "fullscreen and hidden-toolbar transitions must update real editing bounds")
                    let viewport = try await web.evaluateJavaScript("""
                    (() => {
                      const cue = document.createElement("div");
                      cue.style.cssText = "position:fixed;top:0;width:1px;height:1px";
                      document.body.appendChild(cue);
                      const result = {height:innerHeight, fixedTop:cue.getBoundingClientRect().top};
                      cue.remove();
                      return result;
                    })()
                    """) as? [String: Double]
                    let coordinates = try XCTUnwrap(viewport)
                    XCTAssertEqual(try XCTUnwrap(coordinates["height"]),
                                   (web.bounds.height - web.obscuredContentInsets.top) / web.pageZoom, accuracy: 1)
                    XCTAssertEqual(try XCTUnwrap(coordinates["fixedTop"]), 0, accuracy: 1)
                    fullscreenStates.append(["fullscreen": fullscreen, "toolbarVisible": visible,
                                             "webTop": top, "nativeLayoutTop": controller.window.contentLayoutRect.maxY,
                                             "viewport": coordinates])
                }
            }
            measurements[0]["fullscreenStates"] = fullscreenStates
        }
        measurements[0]["publicViewportProbe"] = probesPublicViewport
        measurements[0]["fullscreenVerificationRequired"] = !probesPublicViewport && env["OURO_HEADER_REQUIRE_FULLSCREEN"] == "1"
        measurements[0]["nativeReduceMotion"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        measurements[0]["nativeReduceTransparency"] = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("measurements.json"))
        let liveBodyPaints = measurements.filter { ($0["state"] as? String)?.hasPrefix("top-") != true }
            .allSatisfy { ($0["coloredBodyPixels"] as? Int ?? 0) > 1000 }
        if env["OURO_HEADER_REQUIRE_LIVE_PAINT"] == "1" {
            XCTAssertTrue(liveBodyPaints, "blank native captures cannot certify glass, even when WK snapshots paint")
            for index in stride(from: 0, to: sampledHeaders.count, by: 2) {
                let change = zip(sampledHeaders[index], sampledHeaders[index + 1]).map { abs($0 - $1) }.max() ?? 0
                if expectsGlass && env["OURO_HEADER_EXPECT_OPAQUE"] != "1" {
                    XCTAssertGreaterThan(change, 5, "real document content passing behind glass must remain visible; an opaque band is not a fix")
                } else {
                    XCTAssertLessThan(change, 3, "the flat or opaque control must remain distinguishable from real document translucency")
                }
            }
        }
    }

    private func captureWindow(_ window: NSWindow, to url: URL) throws -> NSBitmapImageRep {
        window.contentView?.displayIfNeeded()
        CATransaction.flush()
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
        return try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
    }

    private func headerRegion(in bitmap: NSBitmapImageRep, window: NSWindow) -> NSRect {
        func panel(in view: NSView) -> NSView? {
            if view.identifier?.rawValue == "OuroMDDocumentHeaderBackdrop" { return view }
            return view.subviews.lazy.compactMap { panel(in: $0) }.first
        }
        let band: NSRect
        if let content = window.contentView, let glass = panel(in: content) {
            band = glass.convert(glass.bounds, to: nil)
        } else {
            band = NSRect(x: 0, y: window.contentLayoutRect.maxY, width: window.frame.width,
                          height: window.frame.height - window.contentLayoutRect.maxY)
        }
        XCTAssertGreaterThan(band.height, 0)
        let scaleX = CGFloat(bitmap.pixelsWide) / window.frame.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / window.frame.height
        return NSRect(x: (band.minX + band.width * 0.32) * scaleX,
                      y: (window.frame.height - band.maxY + band.height * 0.25) * scaleY,
                      width: band.width * 0.48 * scaleX, height: band.height * 0.5 * scaleY)
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
