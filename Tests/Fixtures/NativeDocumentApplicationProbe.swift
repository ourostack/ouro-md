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
        let applicationLog = output.appendingPathComponent("application-events.log")
        guard FileManager.default.createFile(atPath: applicationLog.path, contents: nil) else { exit(1) }
        let log = try FileHandle(forWritingTo: applicationLog)
        defer { try? log.close() }
        app.standardError = log
        try app.run()
        defer {
            if app.isRunning { app.terminate(); app.waitUntilExit() }
        }
        let pid = app.processIdentifier
        func ownedWindows() -> [[String: Any]] {
            guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                    as? [[String: Any]] else {
                fputs("Could not enumerate the probe application's native windows\n", stderr)
                exit(1)
            }
            return windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
        }
        var windows: [[String: Any]] = []
        for _ in 0..<100 {
            windows = ownedWindows()
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
        func snapshotAX(_ element: AXUIElement, depth: Int) -> [String: Any] {
            var result: [String: Any] = [:]
            for name in [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
                   let string = value as? String { result[name] = string }
            }
            for name in [kAXEnabledAttribute, kAXValueAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
                   let number = value as? NSNumber { result[name] = number }
            }
            if depth > 0 {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                   let list = children as? [AXUIElement] {
                    result["children"] = list.map { snapshotAX($0, depth: depth - 1) }
                }
            }
            return result
        }
        try JSONSerialization.data(withJSONObject: snapshotAX(application, depth: 7), options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-accessibility.json"))
        let point = CGPoint(x: x + 240, y: y + 25)
        guard let hover = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { exit(1) }
        hover.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 1)
        func click(_ point: CGPoint) {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                     mouseCursorPosition: point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                   mouseCursorPosition: point, mouseButton: .left) else { exit(1) }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.1)
            up.post(tap: .cghidEventTap)
        }
        var hit: AXUIElement?
        let hitStatus = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit)
        if let hit {
            try JSONSerialization.data(withJSONObject: [
                "status": hitStatus.rawValue, "element": snapshotAX(hit, depth: 2)
            ], options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("filename-hit.json"))
        }
        click(point)
        Thread.sleep(forTimeInterval: 3)
        windows = ownedWindows()
        let onscreen = Process()
        onscreen.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let width = bounds["Width"] as? Double ?? 0
        let height = bounds["Height"] as? Double ?? 0
        guard width > 0, height > 0 else { exit(1) }
        onscreen.arguments = ["-x", "-o", "-R\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))",
                              output.appendingPathComponent("document-controls-onscreen.png").path]
        try onscreen.run()
        onscreen.waitUntilExit()
        guard onscreen.terminationStatus == 0 else { exit(1) }
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
        try JSONSerialization.data(withJSONObject: [
            "ownedWindowsAfterClick": windows, "accessibilityStatus": accessibility.rawValue,
            "clickPoint": ["x": point.x, "y": point.y]
        ], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("filename-click.json"))
        var focused: CFTypeRef?
        try JSONSerialization.data(withJSONObject: snapshotAX(application, depth: 9), options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-popover-accessibility.json"))
        let focusedStatus = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusedStatus == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            fputs("Native filename field was not accessible\n", stderr)
            exit(3)
        }
        let field = unsafeBitCast(focused, to: AXUIElement.self)
        func containingWindow(of element: AXUIElement) -> AXUIElement {
            var current = element
            for _ in 0..<16 {
                var role: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
                   [kAXWindowRole, "AXPopover"].contains(role as? String ?? "") { return current }
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                      let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                    fputs("Native focused controls have no accessible containing window\n", stderr)
                    exit(5)
                }
                current = unsafeBitCast(parent, to: AXUIElement.self)
            }
            fputs("Native focused control ancestry did not reach a window\n", stderr)
            exit(5)
        }
        var focusedRole: CFTypeRef?
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &focusedRole) == .success,
              focusedRole as? String == kAXTextFieldRole,
              AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &focusedValue) == .success,
              focusedValue as? String == URL(fileURLWithPath: file).lastPathComponent else {
            fputs("Native Name field did not open after the filename click\n", stderr)
            exit(2)
        }
        try JSONSerialization.data(withJSONObject: snapshotAX(containingWindow(of: field), depth: 9), options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-popover-accessibility.json"))
        let renamedFile = URL(fileURLWithPath: file).deletingLastPathComponent()
            .appendingPathComponent("Revised field notes.md")
        let originalBytes = try Data(contentsOf: URL(fileURLWithPath: file))
        guard let selectDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let selectUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false),
              let textDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let textUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { exit(3) }
        selectDown.flags = .maskCommand
        selectUp.flags = .maskCommand
        selectDown.post(tap: .cghidEventTap)
        selectUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.2)
        let name = Array("Revised field notes.md".utf16)
        textDown.keyboardSetUnicodeString(stringLength: name.count, unicodeString: name)
        textUp.keyboardSetUnicodeString(stringLength: name.count, unicodeString: name)
        textDown.post(tap: .cghidEventTap)
        textUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.2)
        guard let enterDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let enterUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else { exit(3) }
        enterDown.post(tap: .cghidEventTap)
        enterUp.post(tap: .cghidEventTap)
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: renamedFile.path) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try JSONSerialization.data(withJSONObject: [
            "directory": try FileManager.default.contentsOfDirectory(atPath: renamedFile.deletingLastPathComponent().path),
            "applicationRunning": app.isRunning,
            "terminationStatus": app.isRunning ? -1 : app.terminationStatus,
            "terminationReason": app.isRunning ? -1 : app.terminationReason.rawValue,
            "accessibility": snapshotAX(application, depth: 9)
        ], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("rename-outcome.json"))
        guard FileManager.default.fileExists(atPath: renamedFile.path),
              !FileManager.default.fileExists(atPath: file),
              try Data(contentsOf: renamedFile) == originalBytes else {
            if app.isRunning {
                let sample = Process()
                sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                sample.arguments = ["\(pid)", "2", "-file", output.appendingPathComponent("native-rename.sample.txt").path]
                try sample.run()
                sample.waitUntilExit()
            }
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
        var lockResults: [Bool] = []
        var lockPoint: CGPoint?
        guard let closeDown = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
              let closeUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { exit(5) }
        closeDown.post(tap: .cghidEventTap)
        closeUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.5)
        for shouldLock in [true, false] {
            click(point)
            Thread.sleep(forTimeInterval: 1)
            func findLock(_ element: AXUIElement) -> AXUIElement? {
                var role: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                   role as? String == kAXCheckBoxRole {
                    return element
                }
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                   let list = children as? [AXUIElement] {
                    for child in list { if let found = findLock(child) { return found } }
                }
                return nil
            }
            var currentFocus: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &currentFocus) == .success,
                  let currentFocus, CFGetTypeID(currentFocus) == AXUIElementGetTypeID() else { exit(5) }
            let controls: AXUIElement
            if let lockPoint {
                var hit: AXUIElement?
                guard AXUIElementCopyElementAtPosition(application, Float(lockPoint.x), Float(lockPoint.y), &hit) == .success,
                      let hit else {
                    fputs("Native locked document checkbox could not be hit-tested\n", stderr)
                    exit(5)
                }
                controls = hit
            } else {
                controls = containingWindow(of: unsafeBitCast(currentFocus, to: AXUIElement.self))
            }
            try JSONSerialization.data(withJSONObject: snapshotAX(controls, depth: 9), options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("lock-\(shouldLock)-controls.json"))
            guard let lock = findLock(controls) else {
                fputs("Native focused document controls have no lock affordance\n", stderr)
                exit(5)
            }
            try JSONSerialization.data(withJSONObject: snapshotAX(lock, depth: 1), options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("lock-\(shouldLock)-before.json"))
            var position: CFTypeRef?
            var size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(lock, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(lock, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size,
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { exit(5) }
            var origin = CGPoint.zero
            var extent = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &origin),
                  AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent) else { exit(5) }
            let checkboxPoint = CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)
            lockPoint = checkboxPoint
            click(checkboxPoint)
            Thread.sleep(forTimeInterval: 1)
            try JSONSerialization.data(withJSONObject: snapshotAX(application, depth: 9), options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("lock-\(shouldLock)-accessibility.json"))
            guard let commitDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
                  let commitUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else { exit(5) }
            commitDown.post(tap: .cghidEventTap)
            commitUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 1)
            let immutable = try FileManager.default.attributesOfItem(atPath: renamedFile.path)[.immutable] as? Bool == true
            lockResults.append(immutable)
            try JSONSerialization.data(withJSONObject: ["actualImmutableStates": lockResults], options: [.prettyPrinted])
                .write(to: output.appendingPathComponent("native-lock-results.json"))
            guard immutable == shouldLock else {
                fputs("Native popover lock action did not produce the expected file protection state\n", stderr)
                exit(5)
            }
            guard let escapeDown = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
                  let escapeUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { exit(5) }
            escapeDown.post(tap: .cghidEventTap)
            escapeUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}
