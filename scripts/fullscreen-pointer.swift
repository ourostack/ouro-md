import AppKit
guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]), let y = Double(CommandLine.arguments[2]) else { exit(2) }
let point = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(point)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
        mouseButton: .left)?.post(tap: .cghidEventTap)
