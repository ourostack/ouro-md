import AppKit
import WebKit
import QuartzCore

@MainActor
@available(macOS 26, *)
final class FullscreenGlassProbe: NSObject, NSApplicationDelegate {
    var controller: DocumentWindowController!
    var rows: [[String: Any]] = []
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OURO_FULLSCREEN_OUTPUT"] ?? ".build/fullscreen-proof")

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
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
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
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
            var completed = false
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                                                                  object: controller.window, queue: .main) { _ in
                MainActor.assumeIsolated { completed = true }
            }
            controller.window.toggleFullScreen(nil)
            for _ in 0..<200 {
                if completed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            NotificationCenter.default.removeObserver(observer)
            rows.append(["transition": "enter", "completed": completed, "theme": theme])
            try save()
            guard completed else { throw NSError(domain: "Fullscreen enter never completed", code: 2) }
            try await Task.sleep(for: .seconds(2))
            try await capture(theme: theme, state: "fullscreen-pinned", web: web)
            NSApplication.shared.presentationOptions.insert(.autoHideToolbar)
            CGWarpMouseCursorPosition(CGPoint(x: 500, y: 500))
            try await Task.sleep(for: .seconds(3))
            try await capture(theme: theme, state: "fullscreen-hidden", web: web)
            CGWarpMouseCursorPosition(CGPoint(x: 500, y: 0))
            try await Task.sleep(for: .seconds(3))
            try await capture(theme: theme, state: "fullscreen-revealed", web: web)
            NSApplication.shared.presentationOptions.remove(.autoHideToolbar)
            completed = false
            let exitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                                                      object: controller.window, queue: .main) { _ in
                MainActor.assumeIsolated { completed = true }
            }
            controller.window.toggleFullScreen(nil)
            for _ in 0..<200 {
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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", image.path]
            try process.run()
            process.waitUntilExit()
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
                         "windows": NSApp.windows.map { ["number": $0.windowNumber, "frame": NSStringFromRect($0.frame),
                                                         "class": "\(type(of: $0))", "visible": $0.isVisible] }])
            try save()
        }
    }
}
