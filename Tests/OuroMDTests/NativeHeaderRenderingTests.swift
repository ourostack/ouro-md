import AppKit
import QuartzCore
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

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let output = URL(fileURLWithPath: env["OURO_HEADER_OUTPUT"] ?? ".build/header-rendering", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let expectsGlass = env["OURO_HEADER_EXPECT_GLASS"] != "0"
        let expectsUnderlap = expectsGlass && env["OURO_HEADER_EXPECT_ECHO"] != "1" && env["OURO_HEADER_EXPECT_OPAQUE"] != "1"
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
        controller.model.setTextScale(1)
        let cssHeaderInset = Double((controller.window.frame.height - controller.window.contentLayoutRect.maxY) / web.pageZoom)
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
        defer {
            do {
                try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("measurements.json"), options: .atomic)
            } catch {
                XCTFail("could not retain native header measurements: \(error)")
            }
        }
        var sampledHeaders: [[Double]] = []
        for (theme, mode) in [("quartz", "ir"), ("graphite", "ir"), ("quartz", "sv"), ("graphite", "sv")] {
            let selector = mode == "ir" ? ".vditor-ir .vditor-reset" : ".vditor-sv"
            let prefix = "\(theme)-\(mode)"
            controller.model.setMode(mode)
            try await Task.sleep(for: .seconds(1))
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            controller.model.bridge?.setMarkdown("# HEADER ECHO FIXTURE\n\nOnly synthetic document content.")
            try await Task.sleep(for: .seconds(1))
            var topHeaders: [[Double]] = []
            for marked in [false, true] {
                let geometry = try await web.evaluateJavaScript("""
                (() => {
                  const root = document.querySelector("\(selector)");
                  if (!root || !root.textContent.includes("HEADER ECHO FIXTURE")) { return null; }
                  const first = root.firstElementChild;
                  first.style.cssText = "display:block;margin:0;min-height:200px;font-size:48px;";
                  first.style.setProperty("margin", "0", "important");
                  first.style.setProperty("background", \(marked ? "\"#ee2211\"" : "getComputedStyle(document.body).backgroundColor"), "important");
                  first.style.setProperty("color", \(marked ? "\"black\"" : "\"transparent\""), "important");
                  [document.documentElement, document.body, root].forEach(node => { node.scrollTop = 0; });
                  return {scroll:scrollY + document.body.scrollTop, firstTop:first.getBoundingClientRect().top,
                    firstBottom:first.getBoundingClientRect().bottom, viewport:innerHeight};
                })()
                """)
                let values = try XCTUnwrap(geometry as? [String: Any])
                XCTAssertEqual(values["scroll"] as? Double, 0, "the regression must be at true scroll-top")
                XCTAssertEqual(try XCTUnwrap(values["firstTop"] as? Double),
                               30.0 + (expectsUnderlap ? cssHeaderInset : 0.0), accuracy: 1,
                               "the fixture must occupy the document edge below the header, not evade the mirrored region")
                try await Task.sleep(for: .seconds(1))
                pumpNativeApplicationEvents()
                let state = marked ? "top-marked" : "top-blank"
                let bitmap = try captureWindow(controller.window, to: output.appendingPathComponent("\(prefix)-\(state)-window.png"))
                let header = meanRGB(bitmap, region: headerRegion(in: bitmap, window: controller.window))
                topHeaders.append(header)
                measurements.append(["theme": theme, "mode": mode, "state": state, "headerRGB": header,
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
            let prepared = try await evaluate("""
            (() => {
              const root = document.querySelector("\(selector)");
              if (!root || !root.textContent.includes("Moving document backdrop")) { throw new Error("scroll fixture did not render in \(mode)"); }
              const nodes = Array.from(root.matches(".vditor-sv") ? root.querySelectorAll("span[data-type='text']") : root.children);
              if (nodes.length < 4) { throw new Error("scroll fixture needs text passages; root children=" + root.children.length + ", passages=" + nodes.length); }
              nodes.forEach((node, i) => {
                node.style.display = "block";
                node.style.minHeight = "200px";
                node.style.setProperty("background", i % 4 < 2 ? "#ee6655" : "#3388ee", "important");
              });
              window.__ouroHeaderFixtureNodes = nodes;
              return getComputedStyle(nodes[1]).backgroundColor === "rgb(238, 102, 85)"
                && getComputedStyle(nodes[3]).backgroundColor === "rgb(51, 136, 238)";
            })()
            """, in: web, phase: "\(prefix) prepare scrolling fixture")
            XCTAssertEqual(prepared as? Bool, true, "capture requires actual rendered document text and contrasting colors")
            var headerMeans: [[Double]] = []
            for (name, index) in [("warm", 1), ("cool", 3)] {
                _ = try await evaluate("""
                (() => {
                  const node = window.__ouroHeaderFixtureNodes[\(index)];
                  window.scrollTo(0, scrollY + node.getBoundingClientRect().top + 80);
                })()
                """, in: web, phase: "\(prefix) \(name) scroll")
                try await Task.sleep(for: .seconds(1))
                pumpNativeApplicationEvents()
                let geometry = try await evaluate("""
                ({scroll:scrollY, viewport:innerHeight,
                  sampleTop:window.__ouroHeaderFixtureNodes[\(index)].getBoundingClientRect().top,
                  sampleBottom:window.__ouroHeaderFixtureNodes[\(index)].getBoundingClientRect().bottom,
                  sampleColor:getComputedStyle(window.__ouroHeaderFixtureNodes[\(index)]).backgroundColor})
                """, in: web, phase: "\(prefix) \(name) geometry")
                let values = try XCTUnwrap(geometry as? [String: Any])
                XCTAssertGreaterThan(values["scroll"] as? Double ?? 0, 0)
                XCTAssertLessThan(values["sampleTop"] as? Double ?? 0, -52)
                XCTAssertGreaterThan(values["sampleBottom"] as? Double ?? 0, 0)
                content.displayIfNeeded()
                CATransaction.flush()
                let imageURL = output.appendingPathComponent("\(prefix)-\(name)-window.png")
                let bitmap = try captureWindow(controller.window, to: imageURL)
                let header = meanRGB(bitmap, region: headerRegion(in: bitmap, window: controller.window))
                headerMeans.append(header)
                let frame = web.convert(web.bounds, to: nil)
                measurements.append(["theme": theme, "mode": mode, "state": name, "headerRGB": header,
                                     "coloredBodyPixels": coloredPixels(bitmap),
                                     "webHeight": web.bounds.height, "webTop": frame.maxY,
                                     "contentLayoutTop": controller.window.contentLayoutRect.maxY,
                                     "layout": values, "applicationActive": NSApplication.shared.isActive,
                                     "windowKey": controller.window.isKeyWindow])
                if env["OURO_HEADER_ONSCREEN_DIAGNOSTIC"] == "1" {
                    let screen = try XCTUnwrap(controller.window.screen)
                    let rect = controller.window.frame
                    let region = "\(Int(rect.minX)),\(Int(screen.frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
                    let regionURL = output.appendingPathComponent("\(prefix)-\(name)-onscreen.png")
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
        if expectsUnderlap {
            let fixture = (1...80).map { "Native caret paragraph \($0)." }.joined(separator: "\n\n")
            var caretStates: [[String: Any]] = []
            for mode in ["ir", "sv"] {
                controller.model.setMode(mode)
                try await Task.sleep(for: .seconds(1))
                let selector = mode == "ir" ? ".vditor-ir .vditor-reset" : ".vditor-sv"
                for zoom in [0.75, 1.0, 2.0] {
                    controller.model.setTextScale(zoom)
                    controller.model.bridge?.setMarkdown(fixture)
                    try await Task.sleep(for: .seconds(1))
                    let inset = Double(controller.window.frame.height - controller.window.contentLayoutRect.maxY) / zoom
                    for avoidsHeader in [false, true] {
                        XCTAssertTrue(controller.window.makeFirstResponder(web))
                        let initial = try await evaluate("""
                        (() => {
                          const root = document.querySelector("\(selector)");
                          const scrollers = [document.documentElement, document.body, ...document.querySelectorAll("#editor .vditor-reset,.vditor-preview")];
                          scrollers.forEach(node => {
                            \(avoidsHeader ? "node.style.removeProperty('scroll-padding-top');" : "node.style.setProperty('scroll-padding-top','0px','important');")
                          });
                          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                          let node;
                          while ((node = walker.nextNode())) {
                            if (node.textContent.includes("Native caret paragraph 31.")) { break; }
                          }
                          if (!node) { throw new Error("native caret fixture did not render"); }
                          root.focus({preventScroll:true});
                          const range = document.createRange();
                          range.setStart(node, node.textContent.indexOf("Native caret paragraph 31.") + 2);
                          range.collapse(true);
                          const selection = getSelection();
                          selection.removeAllRanges(); selection.addRange(range);
                          const before = document.createRange();
                          before.selectNodeContents(root); before.setEnd(range.startContainer, range.startOffset);
                          window.__ouroNativeCaretOffset = before.toString().length;
                          window.scrollTo(0, scrollY + range.getBoundingClientRect().top - \(inset + 5));
                          return {top:range.getBoundingClientRect().top,scroll:scrollY};
                        })()
                        """, in: web, phase: "\(mode) zoom \(zoom) caret fixture protected=\(avoidsHeader)")
                        let initialValues = try XCTUnwrap(initial as? [String: Any])
                        XCTAssertEqual(try XCTUnwrap(initialValues["top"] as? Double), inset + 5, accuracy: 2,
                                       "position the real caret at the header before exercising native navigation")
                        var values: [String: Any] = [:]
                        var minimumTop = Double.greatestFiniteMagnitude
                        var steps = 0
                        for _ in 0..<(avoidsHeader ? 12 : 24) {
                            try sendKey("\u{F700}", code: 126, to: controller.window)
                            try await Task.sleep(for: .milliseconds(100))
                            let result = try await web.evaluateJavaScript("""
                            (() => {
                              const selection = getSelection(), range = selection.getRangeAt(0), rect = range.getBoundingClientRect();
                              const before = document.createRange();
                              before.selectNodeContents(document.querySelector("\(selector)"));
                              before.setEnd(range.startContainer, range.startOffset);
                              return {top:rect.top,bottom:rect.bottom,height:rect.height,scroll:scrollY,
                                moved:window.__ouroNativeCaretOffset - before.toString().length};
                            })()
                            """)
                            values = try XCTUnwrap(result as? [String: Any])
                            let top = try XCTUnwrap(values["top"] as? Double)
                            minimumTop = min(minimumTop, top)
                            steps += 1
                            if avoidsHeader {
                                XCTAssertGreaterThanOrEqual(top, inset - 1,
                                                           "every native navigation step must remain below the glass")
                            } else if top < inset - 5 {
                                break
                            }
                        }
                        values["initialTop"] = initialValues["top"]
                        values["minimumTop"] = minimumTop
                        values["steps"] = steps
                        values["mode"] = mode
                        values["zoom"] = zoom
                        values["avoidsHeader"] = avoidsHeader
                        caretStates.append(values)
                        XCTAssertGreaterThan(try XCTUnwrap(values["height"] as? Double), 0)
                        XCTAssertGreaterThan(try XCTUnwrap(values["moved"] as? Double), 0,
                                             "native arrow input must actually move the caret")
                        if avoidsHeader {
                            XCTAssertGreaterThanOrEqual(try XCTUnwrap(values["top"] as? Double), inset - 1,
                                                       "native keyboard editing must remain below the glass")
                            try sendKey("z", code: 6, to: controller.window)
                            let inserted = try await web.evaluateJavaScript("window.ouro.getValue().includes('z')")
                            XCTAssertEqual(inserted as? Bool, true, "native typing must edit the real Markdown buffer")
                            try sendKey("\u{F700}", code: 126, modifiers: .shift, to: controller.window)
                            let selected = try await web.evaluateJavaScript("getSelection().toString().length")
                            XCTAssertGreaterThan(try XCTUnwrap(selected as? Int), 0, "native selection must remain operable")
                        } else {
                            XCTAssertLessThan(try XCTUnwrap(values["top"] as? Double), inset - 5,
                                              "the unprotected control must expose native caret occlusion")
                        }
                    }
                }
            }
            measurements[0]["nativeCaretStates"] = caretStates
            controller.model.setMode("ir")
            controller.model.setTextScale(1)
            try await Task.sleep(for: .seconds(1))
            controller.model.bridge?.setMarkdown("# Opening\n\n" + fixture + "\n\n## Header target\n\n" + fixture)
            try await Task.sleep(for: .seconds(1))
            controller.model.bridge?.scrollToAnchor("header-target")
            try await Task.sleep(for: .seconds(1))
            let anchorTop = try await web.evaluateJavaScript("document.querySelector('.vditor-ir h2').getBoundingClientRect().top")
            XCTAssertEqual(try XCTUnwrap(anchorTop as? Double), cssHeaderInset, accuracy: 1,
                           "real document anchors must land below native chrome")
            controller.model.bridge?.find("Native caret paragraph 40.", backward: false, caseSensitive: false, wholeWord: false, regexp: false)
            try await Task.sleep(for: .seconds(1))
            let found = try await web.evaluateJavaScript("""
            (() => {
              const selection = getSelection(), rect = selection.getRangeAt(0).getBoundingClientRect();
              return {text:selection.toString(),top:rect.top,bottom:rect.bottom,viewport:innerHeight};
            })()
            """) as? [String: Any]
            let foundRange = try XCTUnwrap(found)
            XCTAssertEqual(foundRange["text"] as? String, "Native caret paragraph 40.")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(foundRange["top"] as? Double), cssHeaderInset - 1)
            XCTAssertLessThanOrEqual(try XCTUnwrap(foundRange["bottom"] as? Double),
                                     try XCTUnwrap(foundRange["viewport"] as? Double) - 32)
            measurements[0]["anchorTop"] = anchorTop
            measurements[0]["findRange"] = foundRange
        }
        if expectsUnderlap && env["OURO_HEADER_REQUIRE_FULLSCREEN"] == "1", #available(macOS 26, *) {
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
                        let cssInset = try await web.evaluateJavaScript("parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop)")
                        let editingTop = web.convert(web.bounds, to: nil).maxY - CGFloat(try XCTUnwrap(cssInset as? Double)) * web.pageZoom
                        if abs(editingTop - controller.window.contentLayoutRect.maxY) <= 1 { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    let cssInset = try await web.evaluateJavaScript("parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop)")
                    let header = try XCTUnwrap(cssInset as? Double)
                    let top = web.convert(web.bounds, to: nil).maxY - CGFloat(header) * web.pageZoom
                    XCTAssertEqual(top, controller.window.contentLayoutRect.maxY, accuracy: 1,
                                   "fullscreen and hidden-toolbar transitions must update real editing bounds")
                    let viewport = try await web.evaluateJavaScript("""
                    (() => {
                      const cue = document.createElement("div");
                      cue.style.cssText = "position:fixed;top:var(--ouro-header-inset,0px);width:1px;height:1px";
                      document.body.appendChild(cue);
                      const result = {height:innerHeight, fixedTop:cue.getBoundingClientRect().top};
                      cue.remove();
                      return result;
                    })()
                    """) as? [String: Double]
                    let coordinates = try XCTUnwrap(viewport)
                    XCTAssertEqual(try XCTUnwrap(coordinates["height"]),
                                   Double(web.bounds.height / web.pageZoom), accuracy: 1)
                    XCTAssertEqual(try XCTUnwrap(coordinates["fixedTop"]), header, accuracy: 1)
                    XCTAssertEqual(web.obscuredContentInsets.top, 0)
                    fullscreenStates.append(["fullscreen": fullscreen, "toolbarVisible": visible,
                                             "webTop": top, "nativeLayoutTop": controller.window.contentLayoutRect.maxY,
                                             "viewport": coordinates])
                }
            }
            measurements[0]["fullscreenStates"] = fullscreenStates
        }
        measurements[0]["fullscreenVerificationRequired"] = env["OURO_HEADER_REQUIRE_FULLSCREEN"] == "1"
        measurements[0]["nativeReduceMotion"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        measurements[0]["nativeReduceTransparency"] = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let liveBodyPaints = measurements.filter { ($0["state"] as? String)?.hasPrefix("top-") != true }
            .allSatisfy { ($0["coloredBodyPixels"] as? Int ?? 0) > 1000 }
        if env["OURO_HEADER_REQUIRE_LIVE_PAINT"] == "1" {
            XCTAssertTrue(liveBodyPaints, "blank native captures cannot certify glass")
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

    private func sendKey(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], to window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ))
        window.sendEvent(event)
        pumpNativeApplicationEvents()
    }

    private func evaluate(_ script: String, in web: WKWebView, phase: String) async throws -> Any {
        print("HEADER_PHASE begin \(phase)")
        do {
            let result = try await web.evaluateJavaScript(script)
            print("HEADER_PHASE end \(phase)")
            return result
        } catch {
            let detail = error as NSError
            print("HEADER_FAILURE \(phase): \(String(reflecting: type(of: error))) \(detail.domain) \(detail.code) \(detail.userInfo)")
            throw error
        }
    }

    private func captureWindow(_ window: NSWindow, to url: URL) throws -> NSBitmapImageRep {
        print("HEADER_CAPTURE begin \(url.lastPathComponent)")
        window.contentView?.displayIfNeeded()
        CATransaction.flush()
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        do {
            try capture.run()
        } catch {
            print("HEADER_CAPTURE_FAILURE \(url.lastPathComponent): \(String(reflecting: error))")
            throw error
        }
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        print("HEADER_CAPTURE end \(url.lastPathComponent)")
        return bitmap
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
