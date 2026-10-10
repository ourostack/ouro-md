import AppKit
import QuartzCore
import WebKit
import XCTest
@testable import OuroMD

/// Characterization only. This does not attach a document to production windows.
/// An AppKit-owned run loop distinguishes renderer/Space failures from XCTest
/// event-pumping failures. Never run the interactive branch on an operator host.
@MainActor
final class NativeDocumentPolishProbeTests: XCTestCase {
    func testHostedDocumentControlsAndCompletedFullscreenPaint() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["GITHUB_ACTIONS"] == "true" && env["OURO_NATIVE_POLISH_PROBE"] == "1")
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        var failure: Error?
        Task { @MainActor in
            do { try await probe() } catch { failure = error }
            NSApp.stop(nil)
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                                            modifierFlags: [], timestamp: 0, windowNumber: 0,
                                            context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(wake, atStart: true)
            }
        }
        NSApp.run()
        if let failure { throw failure }
    }

    private func probe() async throws {
        let output = URL(fileURLWithPath: ".build/native-document-polish")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let url = output.appendingPathComponent("Harbor field notes.md")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("Harbor field notes.md"), to: url)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("Harbor route.svg"),
                                        to: output.appendingPathComponent("Harbor route.svg"))
        let controller = DocumentWindowController(filePath: url.path, selfTest: false, useAutosave: false)
        controller.model.autoSaveEnabled = false
        defer {
            controller.model.teardown()
            controller.window.delegate = nil
            controller.window.close()
        }
        controller.window.setContentSize(NSSize(width: 1120, height: 800))
        controller.show(cascadeFrom: nil)
        func editor(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        for _ in 0..<200 {
            if controller.model.isReady { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let web = try XCTUnwrap(editor(try XCTUnwrap(controller.window.contentView)))
        XCTAssertTrue(controller.model.isReady)
        var records: [[String: Any]] = []
        defer {
            try? JSONSerialization.data(withJSONObject: [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "records": records,
                "cleanup": "model.teardown; clear delegate; close exact window"
            ], options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("probe.json"))
        }
        func capture(_ name: String) async throws {
            try await Task.sleep(for: .seconds(1))
            controller.window.contentView?.displayIfNeeded()
            CATransaction.flush()
            let screen = try XCTUnwrap(controller.window.screen)
            let rect = controller.window.frame
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // Fullscreen chrome may be in a separate native auxiliary window.
            // Bound the capture to this owned window's region on a disposable host.
            process.arguments = ["-x", "-R",
                                 "\(Int(rect.minX)),\(Int(screen.frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))",
                                 output.appendingPathComponent("\(name).png").path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let state = try await web.evaluateJavaScript("""
                ({scroll:scrollY, viewport:innerHeight, text:document.body.textContent,
                  imageLoaded:Array.from(document.images).some(i=>i.complete&&i.naturalWidth>0)})
                """)
            var glassFrames: [[String: Any]] = []
            func inspect(_ view: NSView) {
                if view.identifier?.rawValue == "OuroMDDocumentHeaderBackdrop" {
                    glassFrames.append(["frame": NSStringFromRect(view.convert(view.bounds, to: nil)),
                                        "hidden": view.isHidden, "windowNumber": view.window?.windowNumber ?? -1])
                }
                view.subviews.forEach(inspect)
            }
            if let content = controller.window.contentView { inspect(content) }
            records.append(["name": name, "fullscreen": controller.window.styleMask.contains(.fullScreen),
                            "toolbarVisible": controller.window.toolbar?.isVisible ?? false,
                            "windowFrame": NSStringFromRect(rect),
                            "contentLayout": NSStringFromRect(controller.window.contentLayoutRect),
                            "webFrame": NSStringFromRect(web.convert(web.bounds, to: nil)),
                            "glass": glassFrames, "dom": state ?? NSNull(),
                            "presentationOptions": NSApp.presentationOptions.rawValue])
        }
        for autosaves in [false, true] {
            let document: ProbeDocument = autosaves ? AutosavingProbeDocument() : ProbeDocument()
            document.fileURL = url
            document.fileType = "net.daringfireball.markdown"
            document.fileModificationDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            document.contents = try Data(contentsOf: url)
            let nativeController = NSWindowController(window: controller.window)
            document.addWindowController(nativeController)
            NSDocumentController.shared.addDocument(document)
            defer {
                NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
                document.removeWindowController(nativeController)
                NSDocumentController.shared.removeDocument(document)
                document.close()
            }
            document.rename(nil)
            try await capture("native-title-autosaves-\(autosaves)")
            for (index, owned) in NSApp.windows.filter({ $0.isVisible && $0 !== controller.window }).enumerated() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", "\(owned.windowNumber)",
                                     output.appendingPathComponent("native-title-\(autosaves)-aux-\(index).png").path]
                try process.run()
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0)
            }
            records.append(["name": "native-title-association-\(autosaves)",
                            "windowControllerDocumentMatches": nativeController.document === document,
                            "windowControllerMatches": controller.window.windowController === nativeController,
                            "windowForSheetMatches": document.windowForSheet === controller.window,
                            "writableTypes": document.writableTypes(for: .saveOperation),
                            "visibleWindows": NSApp.windows.filter(\.isVisible).map {
                                ["title": $0.title, "frame": NSStringFromRect($0.frame),
                                 "number": $0.windowNumber, "key": $0.isKeyWindow] as [String: Any]
                            },
                            "documentEdited": document.isDocumentEdited,
                            "documentLocked": document.isLocked])
        }
        // A native-only positive control avoids inferring a system limitation
        // from our existing SwiftUI/document-window composition.
        do {
            let document = try AutosavingProbeDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = NSTextField(labelWithString: "Public fictional Harbor document — native NSDocument control")
            let nativeController = NSWindowController(window: window)
            document.addWindowController(nativeController)
            NSDocumentController.shared.addDocument(document)
            defer {
                NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
                document.removeWindowController(nativeController)
                NSDocumentController.shared.removeDocument(document)
                window.close()
                document.close()
                controller.window.makeKeyAndOrderFront(nil)
            }
            window.center()
            nativeController.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            document.rename(nil)
            try await Task.sleep(for: .seconds(2))
            for (index, owned) in NSApp.windows.filter({ $0.isVisible && $0 !== controller.window }).enumerated() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", "\(owned.windowNumber)",
                                     output.appendingPathComponent("native-positive-control-\(index).png").path]
                try process.run()
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0)
            }
            records.append(["name": "native-positive-control",
                            "windowForSheetMatches": document.windowForSheet === window,
                            "documentURL": document.fileURL?.path ?? "",
                            "visibleWindows": NSApp.windows.filter(\.isVisible).map {
                                ["title": $0.title, "frame": NSStringFromRect($0.frame),
                                 "number": $0.windowNumber, "key": $0.isKeyWindow] as [String: Any]
                            }])
        }
        for theme in ["quartz", "graphite"] {
            controller.model.setTheme(id: theme)
            controller.syncChrome()
            _ = try await web.evaluateJavaScript("""
                (()=>{const image=document.querySelector('img[alt="A sketch of the fictional harbor walking loop"]');
                if(image) window.scrollTo(0,scrollY+image.getBoundingClientRect().top+80)})()
                """)
            try await capture("windowed-\(theme)")
            var entered = false
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                                                                  object: controller.window, queue: .main) { _ in
                MainActor.assumeIsolated { entered = true }
            }
            controller.window.toggleFullScreen(nil)
            for _ in 0..<200 {
                if entered { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            NotificationCenter.default.removeObserver(observer)
            records.append(["name": "enter-\(theme)", "completedNotification": entered])
            if entered {
                try await capture("fullscreen-default-\(theme)")
                // Native fullscreen options distinguish pinned from auto-hidden
                // toolbars; setting toolbar.isVisible=false alone does not.
                NSApp.presentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock, .autoHideToolbar]
                try await capture("fullscreen-autohidden-\(theme)")
                if let reveal = NSEvent.mouseEvent(with: .mouseMoved,
                                                   location: NSPoint(x: controller.window.frame.midX,
                                                                     y: controller.window.frame.maxY - 1),
                                                   modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: controller.window.windowNumber, context: nil,
                                                   eventNumber: 0, clickCount: 0, pressure: 0) {
                    NSApp.postEvent(reveal, atStart: false)
                }
                try await capture("fullscreen-reveal-attempt-\(theme)")
                NSApp.presentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]
                try await capture("fullscreen-pinned-\(theme)")
                var exited = false
                let exitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                                                           object: controller.window, queue: .main) { _ in
                    MainActor.assumeIsolated { exited = true }
                }
                controller.window.toggleFullScreen(nil)
                for _ in 0..<200 {
                    if exited { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                NotificationCenter.default.removeObserver(exitObserver)
                records.append(["name": "exit-\(theme)", "completedNotification": exited])
                guard exited else { throw ProbeError.transitionIncomplete }
            } else {
                // Do not call the early fullScreen style-mask bit proof.
                break
            }
        }
    }

    private enum ProbeError: Error { case transitionIncomplete }
}

@MainActor
private class ProbeDocument: NSDocument {
    var contents = Data()
    override class var readableTypes: [String] { ["net.daringfireball.markdown"] }
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        ["net.daringfireball.markdown"]
    }
    override func data(ofType typeName: String) throws -> Data { contents }
    override func read(from data: Data, ofType typeName: String) throws {
        // This characterization invokes init(contentsOf:) on the main actor;
        // it never opts into NSDocument concurrent reading.
        MainActor.assumeIsolated { contents = data }
    }
}

@MainActor
private final class AutosavingProbeDocument: ProbeDocument {
    override class var autosavesInPlace: Bool { true }
    override class var preservesVersions: Bool { false }
}
