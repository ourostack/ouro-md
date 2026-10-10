import AppKit
import ApplicationServices
import WebKit
import XCTest
@testable import OuroMD

@MainActor
final class NativeAccessibilityPreferenceTests: XCTestCase {
    func testHostedNativePreferencesAndAccessibilityExposure() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_ACCESSIBILITY_PROOF"] == "1",
                          "never change preferences or present windows on the operator's Mac")
        let output = URL(fileURLWithPath: env["OURO_ACCESSIBILITY_OUTPUT"] ?? ".build/accessibility-proof")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let expectedMotion = env["OURO_EXPECT_REDUCE_MOTION"] == "1"
        let expectedTransparency = env["OURO_EXPECT_REDUCE_TRANSPARENCY"] == "1"
        let workspace = NSWorkspace.shared
        var evidence: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "expectedMotion": expectedMotion, "expectedTransparency": expectedTransparency,
            "nativeMotion": workspace.accessibilityDisplayShouldReduceMotion,
            "nativeTransparency": workspace.accessibilityDisplayShouldReduceTransparency,
            "voiceOverTraversal": "not exercised; AX exposure is not VoiceOver traversal"
        ]
        defer {
            try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("accessibility.json"))
        }
        let propagated = workspace.accessibilityDisplayShouldReduceMotion == expectedMotion
            && workspace.accessibilityDisplayShouldReduceTransparency == expectedTransparency
        evidence["preferencesPropagated"] = propagated
        try XCTSkipUnless(propagated, "hosted preference write did not reach NSWorkspace; no qualification claimed")
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Harbor field notes.md")
        let controller = DocumentWindowController(filePath: fixture.path, selfTest: false, useAutosave: false)
        defer { controller.window.delegate = nil; controller.window.close() }
        controller.model.setSidebarVisible(true)
        controller.show(cascadeFrom: nil)
        func findWeb(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { findWeb($0) }.first
        }
        var web: WKWebView?
        for _ in 0..<200 {
            NSApp.updateWindows()
            if controller.model.isReady, let content = controller.window.contentView {
                web = findWeb(content)
                if web != nil { break }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let editor = try XCTUnwrap(web)
        try await Task.sleep(for: .seconds(1))
        let reducedMotion = try await editor.evaluateJavaScript("matchMedia('(prefers-reduced-motion: reduce)').matches") as? Bool
        evidence["webReducedMotion"] = reducedMotion ?? false
        XCTAssertEqual(reducedMotion, expectedMotion, "the real WebKit media query must follow the native preference")
        let bodyText = try await editor.evaluateJavaScript("document.body.textContent.includes('A thoughtful first visit')") as? Bool
        XCTAssertEqual(bodyText, true)

        // Traverse accessibilityChildren only, never ordinary subviews or labels.
        var nodes: [[String: String]] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: Any, depth: Int) {
            guard depth < 30, let reference = object as AnyObject? else { return }
            guard seen.insert(ObjectIdentifier(reference)).inserted else { return }
            let role = reference.accessibilityRole?()?.rawValue ?? ""
            let label = reference.accessibilityLabel?() ?? ""
            let title = reference.accessibilityTitle?() ?? ""
            nodes.append(["role": role, "label": label, "title": title])
            for child in reference.accessibilityChildren?() ?? [] { visit(child, depth: depth + 1) }
        }
        visit(controller.window, depth: 0)
        evidence["nativeAXNodes"] = nodes
        XCTAssertTrue(nodes.contains { $0["role"] == NSAccessibility.Role.button.rawValue },
                      "native controls must be in the actual accessibility hierarchy")
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
        evidence["crossProcessAXStatus"] = status.rawValue
        evidence["crossProcessAXTrusted"] = AXIsProcessTrusted()
        evidence["crossProcessAXWindowCount"] = (windows as? [Any])?.count ?? 0
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", "\(controller.window.windowNumber)",
                             output.appendingPathComponent("preference-window.png").path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
        evidence["verdict"] = "native preference propagation, WK media query and native AX exposure checked; not VoiceOver traversal"
    }
}
