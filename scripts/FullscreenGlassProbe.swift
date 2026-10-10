import AppKit
import WebKit
import QuartzCore

@MainActor
final class FullscreenPresentationDelegate: NSObject, NSWindowDelegate {
    let base: DocumentWindowController
    var autoHideToolbar = false
    init(base: DocumentWindowController) { self.base = base }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || base.responds(to: selector) }
    override func forwardingTarget(for selector: Selector!) -> Any? { base }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions options: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        var result = options
        if autoHideToolbar { result.insert(.autoHideToolbar) } else { result.remove(.autoHideToolbar) }
        return result
    }
}

@MainActor
@available(macOS 26, *)
final class FullscreenGlassProbe: NSObject, NSApplicationDelegate {
    var controller: DocumentWindowController!
    var presentationDelegate: FullscreenPresentationDelegate!
    var fullscreenBackdrop: NSGlassEffectView?
    var rows: [[String: Any]] = []
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OURO_FULLSCREEN_OUTPUT"] ?? ".build/fullscreen-proof")

    func start(controller: DocumentWindowController) {
        self.controller = controller
        presentationDelegate = FullscreenPresentationDelegate(base: controller)
        controller.window.delegate = presentationDelegate
        controller.window.collectionBehavior.insert(.fullScreenPrimary)
        controller.window.setContentSize(NSSize(width: 1000, height: 700))
        controller.show(cascadeFrom: nil)
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try await probe()
                try save()
                exit(0)
            } catch {
                rows.append(["error": "\(error)"])
                try? save()
                if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { print(text) }
                print("FULLSCREEN PROBE FAILURE: \(error)")
                exit(1)
            }
        }
    }

    func save() throws {
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("measurements.json"))
    }

    func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let value = view as? T { return value }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    func probe() async throws {
        let content = controller.window.contentView!
        for _ in 0..<300 {
            if controller.model.isReady && find(WKWebView.self, in: content) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard controller.model.isReady, let web = find(WKWebView.self, in: content) else {
            throw NSError(domain: "Editor never ready", code: 1)
        }
        for theme in ["quartz", "graphite"] {
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            controller.model.bridge?.setMarkdown((1...30).map {
                "## Passage \($0)\n\nMoving document backdrop \($0). Native controls must remain readable."
            }.joined(separator: "\n\n"))
            try await Task.sleep(for: .seconds(2))
            _ = try await web.evaluateJavaScript("""
            Array.from(document.querySelector(".vditor-ir .vditor-reset").children).forEach((n,i)=>{
              n.style.minHeight="240px";
              n.style.setProperty("background",i%4<2?"#ee6655":"#3388ee","important");
            });
            """)
            try await capture(theme: theme, state: "windowed", web: web)
            rows.append(["beforeEnterActive": NSApp.isActive, "key": controller.window.isKeyWindow,
                         "collectionBehavior": controller.window.collectionBehavior.rawValue])
            var completed = false
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                                                                  object: controller.window, queue: .main) { _ in
                MainActor.assumeIsolated { completed = true }
            }
            controller.window.toggleFullScreen(nil)
            for _ in 0..<600 {
                if completed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            NotificationCenter.default.removeObserver(observer)
            rows.append(["transition": "enter", "completed": completed, "theme": theme,
                         "style": controller.window.styleMask.rawValue,
                         "frame": NSStringFromRect(controller.window.frame),
                         "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                         "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency])
            try save()
            guard completed else { throw NSError(domain: "Fullscreen enter never completed", code: 2) }
            try await Task.sleep(for: .seconds(2))
            try await capture(theme: theme, state: "fullscreen-pinned", web: web)
            if let toolbarWindow = controller.truthToolbarItem?.view?.window, toolbarWindow !== controller.window {
                rows.append(["toolbarViews": describe(toolbarWindow.contentView!), "theme": theme])
                if let anchor = controller.truthToolbarItem?.view {
                    var foreground = anchor
                    while let parent = foreground.superview, foreground.bounds.width < toolbarWindow.contentView!.bounds.width - 1 {
                        foreground = parent
                    }
                    if let host = foreground.superview {
                        let glass = NSGlassEffectView(frame: host.bounds)
                        glass.style = .regular
                        glass.contentView = NSView()
                        glass.autoresizingMask = [.width, .height]
                        host.addSubview(glass, positioned: .below, relativeTo: foreground)
                        fullscreenBackdrop = glass
                    }
                }
            }
            try await capture(theme: theme, state: "fullscreen-transparent-titlebar", web: web)
            try await transition(fullscreen: false)
            presentationDelegate.autoHideToolbar = true
            try await transition(fullscreen: true)
            if let toolbarWindow = controller.truthToolbarItem?.view?.window, toolbarWindow !== controller.window {
                toolbarWindow.titlebarAppearsTransparent = true
            }
            movePointer(to: CGPoint(x: 500, y: 500))
            try await Task.sleep(for: .seconds(3))
            try await capture(theme: theme, state: "fullscreen-hidden", web: web)
            movePointer(to: CGPoint(x: 500, y: 1))
            try await Task.sleep(for: .seconds(3))
            try await capture(theme: theme, state: "fullscreen-revealed", web: web)
            presentationDelegate.autoHideToolbar = false
            completed = false
            let exitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                                                      object: controller.window, queue: .main) { _ in
                MainActor.assumeIsolated { completed = true }
            }
            controller.window.toggleFullScreen(nil)
            for _ in 0..<600 {
                if completed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            NotificationCenter.default.removeObserver(exitObserver)
            rows.append(["transition": "exit", "completed": completed, "theme": theme])
            try save()
            guard completed else { throw NSError(domain: "Fullscreen exit never completed", code: 3) }
            try await capture(theme: theme, state: "restored", web: web)
        }
    }

    func describe(_ view: NSView) -> [String: Any] {
        var result: [String: Any] = ["class": "\(type(of: view))", "frame": NSStringFromRect(view.frame),
                                     "opaque": view.isOpaque, "alpha": view.alphaValue,
                                     "children": view.subviews.map { self.describe($0) }]
        if let effect = view as? NSVisualEffectView {
            result["material"] = effect.material.rawValue
            result["blending"] = effect.blendingMode.rawValue
        }
        return result
    }

    func transition(fullscreen: Bool) async throws {
        var completed = false
        let name = fullscreen ? NSWindow.didEnterFullScreenNotification : NSWindow.didExitFullScreenNotification
        let observer = NotificationCenter.default.addObserver(forName: name, object: controller.window, queue: .main) { _ in
            MainActor.assumeIsolated { completed = true }
        }
        controller.window.toggleFullScreen(nil)
        for _ in 0..<200 {
            if completed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        NotificationCenter.default.removeObserver(observer)
        guard completed else { throw NSError(domain: "Requested fullscreen transition did not complete", code: 6) }
        try await Task.sleep(for: .seconds(2))
    }

    func movePointer(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    func captureImage(destination: URL, kind: String, window: Int, region: String = "") async throws {
        let id = UUID().uuidString
        let request: [String: Any] = ["id": id, "pid": ProcessInfo.processInfo.processIdentifier,
                                     "kind": kind, "window": window, "region": region,
                                     "destination": destination.path]
        try JSONSerialization.data(withJSONObject: request)
            .write(to: output.appendingPathComponent("capture-request.json"), options: .atomic)
        for _ in 0..<600 {
            if let data = try? Data(contentsOf: output.appendingPathComponent("capture-response.json")),
               let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               response["id"] as? String == id {
                guard response["status"] as? Int == 0 else {
                    throw NSError(domain: "Native runner capture failed: \(response["stderr"] ?? "")", code: 4)
                }
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "Native runner capture timed out", code: 5)
    }

    func capture(theme: String, state: String, web: WKWebView) async throws {
        for (color, index) in [("warm", 1), ("cool", 3)] {
            let geometry = try await web.evaluateJavaScript("""
            (() => {
              const n=document.querySelector(".vditor-ir .vditor-reset").children[\(index)];
              window.scrollTo(0,scrollY+n.getBoundingClientRect().top+80);
              return {text:n.textContent, color:getComputedStyle(n).backgroundColor,scroll:scrollY};
            })()
            """)
            try await Task.sleep(for: .seconds(2))
            let window = controller.window
            let glass = find(NSGlassEffectView.self, in: window.contentView!)
            let image = output.appendingPathComponent("\(theme)-\(state)-\(color).png")
            try await captureImage(destination: image, kind: "window", window: window.windowNumber)
            if window.styleMask.contains(.fullScreen), let screen = window.screen {
                let region = "\(Int(window.frame.minX)),\(Int(screen.frame.maxY-window.frame.maxY)),\(Int(window.frame.width)),\(Int(window.frame.height))"
                let onscreen = output.appendingPathComponent("\(theme)-\(state)-\(color)-onscreen.png")
                try await captureImage(destination: onscreen, kind: "region", window: window.windowNumber, region: region)
                guard NSBitmapImageRep(data: try Data(contentsOf: onscreen)) != nil else {
                    throw NSError(domain: "Composited capture failed", code: 5)
                }
            }
            let bitmap = NSBitmapImageRep(data: try Data(contentsOf: image))!
            var rgb = [Double](repeating: 0, count: 3), count = 0.0, colored = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in stride(from: 100, to: bitmap.pixelsWide - 100, by: 4) {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if y >= 12 && y < 38 && x >= 320 && x < 800 {
                        rgb[0] += c.redComponent * 255; rgb[1] += c.greenComponent * 255
                        rgb[2] += c.blueComponent * 255; count += 1
                    }
                    if y > 100 && max(c.redComponent, c.blueComponent) - c.greenComponent > 0.2 { colored += 1 }
                }
            }
            rows.append(["theme": theme, "state": state, "color": color,
                         "headerRGB": rgb.map { $0 / max(1,count) }, "coloredBodyPixels": colored,
                         "geometry": geometry, "webTop": web.convert(web.bounds, to: nil).maxY,
                         "layoutTop": window.contentLayoutRect.maxY,
                         "contentTop": window.contentView!.convert(window.contentView!.bounds, to: nil).maxY,
                         "glassFrame": glass.map { NSStringFromRect($0.convert($0.bounds, to: nil)) } ?? "absent",
                         "glassWindow": glass?.window?.windowNumber ?? -1,
                         "window": window.windowNumber, "titlebarTransparent": window.titlebarAppearsTransparent,
                         "presentation": NSApp.presentationOptions.rawValue,
                         "effectivePresentation": NSApp.currentSystemPresentationOptions.rawValue,
                         "mouse": NSStringFromPoint(NSEvent.mouseLocation),
                         "windows": NSApp.windows.map { ["number": $0.windowNumber, "frame": NSStringFromRect($0.frame),
                                                         "class": "\(type(of: $0))", "visible": $0.isVisible,
                                                         "transparent": $0.titlebarAppearsTransparent, "opaque": $0.isOpaque,
                                                         "alpha": $0.alphaValue, "occluded": !$0.occlusionState.contains(.visible),
                                                         "background": "\($0.backgroundColor)",
                                                         "style": $0.styleMask.rawValue] }])
            try save()
        }
    }
}
