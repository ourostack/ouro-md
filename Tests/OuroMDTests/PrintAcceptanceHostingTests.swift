import Foundation
import AppKit
import XCTest
import PDFKit
import WebKit
@testable import OuroMD

@MainActor
final class PrintAcceptanceHostingTests: XCTestCase {
    func testSyntheticPrintPreviewStateScreenshotsOnIsolatedCI() async throws {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
            throw XCTSkip("Native screenshot proof runs only on the isolated CI desktop.")
        }
        let parent = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.title = "Owned synthetic print preview proof"
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        parent.makeKeyAndOrderFront(nil)
        defer { parent.close() }
        let artifacts = try PrintLayoutTestPaths.makeScratchDirectory(label: "preview-state-screenshots")
        var attempts = 0
        var failInitialLoad = false
        var phaseObserver: (@MainActor (PrintPreviewPhase) -> Void)?
        var settings = PrintLayoutSettings.default
        settings.headingBreakLevel = 2
        let session = PrintLayoutSession(settings: settings, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            attempts += 1
            phaseObserver = observer
            if attempts == 1 {
                while !failInitialLoad { try await Task.sleep(nanoseconds: 10_000_000) }
                throw PrintLayoutSession.SessionError.missingPreview
            }
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h2>Harbor notes</h2><p>A readable synthetic page.</p><h2>Route planning</h2><p>Keep this page available while settings change.</p>", title: "Preview states", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .export(artifacts.appendingPathComponent("unused.pdf"), { _ in }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in })
        session.begin()
        let root = try XCTUnwrap(session.panelForTesting.contentView)
        func capture(_ state: String) async throws {
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            let output = artifacts.appendingPathComponent("\(state).png")
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(session.panelForTesting.windowNumber), output.path]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
            XCTAssertGreaterThan(try Data(contentsOf: output).count, 1_000)
        }
        func waitFor(_ condition: () -> Bool) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while !condition(), ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertTrue(condition())
        }
        func button(_ title: String) -> NSButton? {
            descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == title }
        }
        func ready() -> Bool {
            descendants(of: root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("Preview ready —") }
        }
        try await capture("loading")
        try await waitFor { phaseObserver != nil }
        phaseObserver?(.capturingPages(completed: 1, total: 3))
        try await capture("capture-progress")
        failInitialLoad = true
        try await waitFor { button("Retry")?.isHidden == false }
        try await capture("failure-retry")
        button("Retry")?.performClick(nil)
        try await waitFor { ready() }
        try await capture("ready")
        let preview = try XCTUnwrap(descendants(of: root).compactMap { $0 as? PDFView }.first)
        let previous = try XCTUnwrap(preview.document)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        XCTAssertTrue(preview.document === previous)
        XCTAssertFalse(ready())
        try await capture("updating-previous-preview")
        button("Cancel")?.performClick(nil)
        print("owned isolated-CI print state screenshots: \(artifacts.path)")
    }

    func testThemeReferenceReadsTheActiveModeNotAnEmptyInactiveEditor() async throws {
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Mode reference fixture</p>", title: "Active mode reference", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        _ = try await prepared.webView.evaluateJavaScript("""
        document.body.innerHTML='<style>.vditor-ir .vditor-reset{font:20px Georgia}.vditor-ir h1{font-size:40px}</style><div class="vditor-wysiwyg" style="display:none"><div class="vditor-reset"></div></div><div class="vditor-ir"><div class="vditor-reset"><h1>Active heading</h1></div></div>';
        """)
        let typography = try await prepared.webView.evaluateJavaScript(EditorSurfaceTester.appliedEditorTypographyScript(mode: "ir")) as? [String: Any]
        XCTAssertEqual(typography?["headingScale"] as? Double, 2)
        XCTAssertTrue((typography?["fontFamily"] as? String)?.contains("Georgia") == true)
    }

    func testContentAuditRecognizesOnlyVerifiedCellWordLineWraps() throws {
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("Boehringer", pageTexts: ["Verified Bo\nehringer record"], verifiedCells: ["Verified Boehringer record"]), 1)
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("Boehringer", pageTexts: ["Bo\nehringer"], verifiedCells: ["Boehringer"]), 0)
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("Boehringer", pageTexts: ["Bo ehringer"], verifiedCells: ["Boehringer"]), 0)
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("office", pageTexts: ["of\nfice"], verifiedCells: ["Unrelated content"]), 0)
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("Boehringer", pageTexts: ["SummaryBo\nehringer"], verifiedCells: ["Boehringer"]), 0)
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("Boehringer", pageTexts: ["Boehringer"], verifiedCells: ["Boehringer"]), 0)
    }

    func testWrappedWordCreditMustBelongToTheVerifiedCellText() throws {
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("office", pageTexts: ["Delivery office record\nof\nfice"], verifiedCells: ["Delivery office record"]), 0)
        XCTAssertEqual(try EditorSurfaceTester.wrappedCellWordCount("office", pageTexts: ["Delivery of\nfice record"], verifiedCells: ["Delivery office record"]), 1)
    }

    func testPrivateAcceptanceUsesNoPresentationInsteadOfAnOffscreenSheet() {
        withAcceptanceFile("/tmp/print-acceptance-hosting-fixture.md") {
            XCTAssertEqual(EditorSurfaceTester().printPresentation, .headless)
        }
    }

    func testHeadlessExportNeverOrdersAWindowOrAttachesASheet() async throws {
        let parent = NonActivatingHeadlessHostWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 760, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.alphaValue = 0
        defer { parent.close() }
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>HEADLESS-EXPORT-TOKEN</p>", title: "No presentation", baseURL: nil, settings: .default)
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "no-presentation")
        defer { try? FileManager.default.removeItem(at: scratch); prepared.releaseHold() }
        let output = scratch.appendingPathComponent("headless.pdf")
        var result: Result<Bool, Error>?
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .export(output, { result = $0 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, presentation: .headless)
        session.begin()
        XCTAssertNil(parent.attachedSheet)
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(session.panelForTesting.isVisible)
        XCTAssertEqual(session.panelForTesting.alphaValue, 0)
        XCTAssertFalse(session.panelForTesting.canBecomeKey)
        XCTAssertFalse(session.panelForTesting.canBecomeMain)
        let root = try XCTUnwrap(session.panelForTesting.contentView)
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while ProcessInfo.processInfo.systemUptime < deadline {
            if descendants(of: root).compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue.hasPrefix("Preview ready —") }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let export = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Export PDF" })
        export.performClick(nil)
        while result == nil, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard case .success(true)? = result else { return XCTFail("Headless export did not complete.") }
        XCTAssertTrue(PDFDocument(url: output)?.string?.contains("HEADLESS-EXPORT-TOKEN") == true)
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(session.panelForTesting.isVisible)
        XCTAssertNil(parent.attachedSheet)
        XCTAssertFalse(prepared.webView.window?.canBecomeKey == true)
    }

    private func descendants(of root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { descendants(of: $0) }
    }

    func testExplicitPrintAcceptanceDoesNotRequireEditorActivation() {
        withAcceptanceFile("/tmp/print-acceptance-hosting-fixture.md") {
            XCTAssertFalse(EditorSurfaceTester().requiresFocusedEditor, "A print-only acceptance run must not take focus from the operator's desktop.")
        }
    }

    func testGeneralSurfaceJourneyRetainsItsFocusedEditorRequirement() {
        withAcceptanceFile(nil) {
            XCTAssertTrue(EditorSurfaceTester().requiresFocusedEditor, "Focused editing scenarios remain assigned to the isolated native runner.")
        }
    }

    func testExplicitPrintAcceptanceProhibitsImplicitApplicationActivation() {
        withAcceptanceFile("/tmp/print-acceptance-hosting-fixture.md") {
            XCTAssertEqual(EditorSurfaceTester().activationPolicy, .prohibited, "Merely avoiding an explicit activate call does not prevent a sheet from activating the process.")
        }
    }

    private func withAcceptanceFile(_ value: String?, body: () -> Void) {
        let key = "OURO_PRINT_ACCEPTANCE_FILE"
        let previous = ProcessInfo.processInfo.environment[key]
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        if let value {
            XCTAssertEqual(setenv(key, value, 1), 0)
        } else {
            XCTAssertEqual(unsetenv(key), 0)
        }
        body()
    }
}
