import AppKit
import ApplicationServices
import CoreGraphics

@main
enum NativeDocumentApplicationProbe {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true",
              let executable = environment["OURO_DOCUMENT_PROBE_EXECUTABLE"],
              let file = environment["OURO_DOCUMENT_PROBE_FILE"],
              let outputPath = environment["OURO_DOCUMENT_PROBE_OUTPUT"] else { exit(64) }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = Process()
        app.executableURL = URL(fileURLWithPath: executable)
        app.arguments = [file]
        app.environment = environment
        try app.run()
        defer {
            if app.isRunning { app.terminate(); app.waitUntilExit() }
        }
        let pid = app.processIdentifier
        func ownedWindows() -> [[String: Any]] {
            guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                    as? [[String: Any]] else { return [] }
            return windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
        }
        var windows: [[String: Any]] = []
        for _ in 0..<100 {
            windows = ownedWindows()
            guard windows.contains(where: { ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }) else {
                fputs("Native document popover did not open\n", stderr)
                exit(2)
            }
            if windows.contains(where: { ($0[kCGWindowLayer as String] as? Int) == 0 }) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard let window = windows.first(where: { ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double else { exit(1) }
        Thread.sleep(forTimeInterval: 3)
        let application = AXUIElementCreateApplication(pid)
        var attributes: CFTypeRef?
        let accessibility = AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &attributes)
        let point = CGPoint(x: x + 240, y: y + 25)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { exit(1) }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 3)
        windows = ownedWindows()
        for (index, owned) in windows.enumerated() {
            guard let number = owned[kCGWindowNumber as String] as? Int else { continue }
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", "\(number)",
                                 output.appendingPathComponent("document-controls-\(index).png").path]
            try capture.run()
            capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { exit(1) }
        }
        var focused: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusedStatus == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            fputs("Native filename field was not accessible\n", stderr)
            exit(3)
        }
        let field = unsafeBitCast(focused, to: AXUIElement.self)
        let renamedFile = URL(fileURLWithPath: file).deletingLastPathComponent()
            .appendingPathComponent("Revised field notes.md")
        let originalBytes = try Data(contentsOf: URL(fileURLWithPath: file))
        guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString,
                                          "Revised field notes.md" as CFString) == .success else { exit(3) }
        guard let enterDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let enterUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else { exit(3) }
        enterDown.post(tap: .cghidEventTap)
        enterUp.post(tap: .cghidEventTap)
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: renamedFile.path) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard FileManager.default.fileExists(atPath: renamedFile.path),
              !FileManager.default.fileExists(atPath: file),
              try Data(contentsOf: renamedFile) == originalBytes else {
            fputs("Native rename did not preserve the original file bytes and identity\n", stderr)
            exit(4)
        }
        Thread.sleep(forTimeInterval: 1)
        let renamedWindows = ownedWindows()
        guard renamedWindows.contains(where: {
            ($0[kCGWindowName as String] as? String)?.contains("Revised field notes") == true
        }) else {
            fputs("Native rename did not synchronize the application title\n", stderr)
            exit(4)
        }
        try JSONSerialization.data(withJSONObject: [
            "ownedWindows": windows,
            "accessibilityStatus": accessibility.rawValue,
            "clickPoint": ["x": point.x, "y": point.y],
            "fixture": URL(fileURLWithPath: file).lastPathComponent,
            "renamedWindows": renamedWindows, "nativeRenamePreservedBytes": true
        ], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("application-probe.json"))
    }
}
