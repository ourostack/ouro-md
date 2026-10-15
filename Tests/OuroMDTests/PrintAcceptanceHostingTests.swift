import Foundation
import AppKit
import XCTest
import PDFKit
import WebKit
@testable import OuroMD

private final class ProfiledPrintHTMLWebView: WKWebView {
    var profileRequests = 0
    var delayProfile = false
    var pendingProfile: ((Any?, Error?) -> Void)?

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        guard javaScriptString.contains("entered:entered") else {
            completionHandler?("<p>PROFILED-HTML-TOKEN</p>", nil)
            return
        }
        let now = floor(Date().timeIntervalSince1970 * 1_000)
        profileRequests += 1
        if delayProfile {
            pendingProfile = completionHandler
            return
        }
        completionHandler?(["body": "<p>PROFILED-HTML-TOKEN</p>", "entered": now, "finished": now, "profile": ["render_html": 3.0, "normalize_headings": 2.0]], nil)
    }
}

@MainActor
final class PrintAcceptanceHostingTests: XCTestCase {
    func testCancelledHTMLRequestDoesNotPublishLatePreparationMetrics() async throws {
        let parent = NonActivatingHeadlessHostWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.alphaValue = 0
        defer { parent.close() }
        let editor = ProfiledPrintHTMLWebView()
        editor.delayProfile = true
        parent.contentView = editor
        let coordinator = EditorWebView.Coordinator(model: AppModel(), printSettingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()))
        coordinator.webView = editor
        coordinator.printPresentation = .headless
        coordinator.profilePrintLayout = true
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "headless-late-html-profile")
        defer { try? FileManager.default.removeItem(at: scratch) }
        var completions = 0
        coordinator.exportPDF(to: scratch.appendingPathComponent("unused.pdf")) { _ in completions += 1 }
        let session = try XCTUnwrap(PrintLayoutSession.activeSession(for: parent))
        defer { session.panelForTesting.close() }
        let root = try XCTUnwrap(session.panelForTesting.contentView)
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while editor.pendingProfile == nil, ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        let pending = try XCTUnwrap(editor.pendingProfile)
        let holds = PreparedPrintDocument.retainedCountForTesting
        descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }?.performClick(nil)
        try await Task.sleep(nanoseconds: 10_000_000)
        let now = floor(Date().timeIntervalSince1970 * 1_000)
        pending(["body": "<p>Retired HTML</p>", "entered": now, "finished": now, "profile": ["render_html": 3.0, "normalize_headings": 2.0]], nil)
        editor.pendingProfile = nil
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(coordinator.printPreparationProfile.isEmpty, "Retired measurements must not contaminate a later print request.")
        XCTAssertEqual(PreparedPrintDocument.retainedCountForTesting, holds)
        XCTAssertEqual(completions, 1)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(session.panelForTesting.isVisible)
        XCTAssertNil(parent.attachedSheet)
    }

    func testOrdinaryHTMLAcquisitionRetainsItsStringOnlyBridge() {
        let editor = ProfiledPrintHTMLWebView()
        let coordinator = EditorWebView.Coordinator(model: AppModel())
        coordinator.webView = editor
        var body: String?
        coordinator.getHTML { body = $0 }
        XCTAssertEqual(body, "<p>PROFILED-HTML-TOKEN</p>")
        XCTAssertEqual(editor.profileRequests, 0)
        XCTAssertTrue(coordinator.printPreparationProfile.isEmpty)
    }

    func testProfiledHTMLSeparatesQueueConversionTransferAndFontWork() async throws {
        let parent = NonActivatingHeadlessHostWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.alphaValue = 0
        defer { parent.close() }
        let editor = ProfiledPrintHTMLWebView()
        parent.contentView = editor
        let coordinator = EditorWebView.Coordinator(model: AppModel(), printSettingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()))
        coordinator.webView = editor
        coordinator.printPresentation = .headless
        coordinator.profilePrintLayout = true
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "headless-html-profile")
        defer { try? FileManager.default.removeItem(at: scratch) }
        coordinator.exportPDF(to: scratch.appendingPathComponent("unused.pdf")) { _ in }
        let session = try XCTUnwrap(PrintLayoutSession.activeSession(for: parent))
        defer { session.panelForTesting.close() }
        let root = try XCTUnwrap(session.panelForTesting.contentView)
        defer { descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }?.performClick(nil) }
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !descendants(of: root).compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue.hasPrefix("Preview ready —") }), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let preview = try XCTUnwrap(descendants(of: root).compactMap { $0 as? PDFView }.first)
        XCTAssertTrue(preview.document?.string?.contains("PROFILED-HTML-TOKEN") == true)
        XCTAssertEqual(editor.profileRequests, 1, "Profiling must not acquire HTML a second time.")
        let profile = coordinator.printPreparationProfile
        for code in ["html_queue", "html_render", "html_normalize", "html_return_transfer", "font_resources", "typography_snapshot", "html_callback"] {
            XCTAssertNotNil(profile[code], "Missing fixed numeric preparation step: \(code)")
            XCTAssertGreaterThanOrEqual(profile[code] ?? -1, 0)
        }
        XCTAssertEqual(profile["html_render"], 3)
        XCTAssertEqual(profile["html_normalize"], 2)
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(session.panelForTesting.isVisible)
        XCTAssertNil(parent.attachedSheet)
    }

    func testCaptureBatchFailureAndCancellationRetireUIImmediately() async throws {
        let parent = NonActivatingHeadlessHostWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.alphaValue = 0
        defer { parent.close() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "headless-capture-retirement")
        defer { try? FileManager.default.removeItem(at: scratch) }
        var phaseObserver: (@MainActor (PrintPreviewPhase) -> Void)?
        var shouldFail = false
        var rawCaptures: [Int] = []
        var completions = 0
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { _, _, observer in
            phaseObserver = observer
            while !shouldFail { try await Task.sleep(nanoseconds: 1_000_000) }
            throw PrintLayoutSession.SessionError.missingPreview
        }, parentWindow: parent, action: .export(scratch.appendingPathComponent("unused.pdf"), { _ in completions += 1 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in }, onPhase: { phase in
            if case .capturingPages(let completed, _) = phase { rawCaptures.append(completed) }
        }, presentation: .headless)
        defer { session.panelForTesting.close() }
        session.begin()
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while phaseObserver == nil, ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        let observer = try XCTUnwrap(phaseObserver)
        let root = try XCTUnwrap(session.panelForTesting.contentView)
        let progress = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSProgressIndicator }.first)
        observer(.capturingPages(completed: 0, total: 200))
        observer(.capturingPages(completed: 1, total: 200))
        XCTAssertEqual(progress.doubleValue, 1, "First progress must not wait for the batch interval.")
        for completed in 2...200 { observer(.capturingPages(completed: completed, total: 200)) }
        XCTAssertEqual(rawCaptures, Array(0...200))
        XCTAssertEqual(progress.doubleValue, 200, "Final capture must flush immediately.")
        shouldFail = true
        let retry = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Retry" })
        while retry.isHidden, ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(retry.isHidden)
        XCTAssertEqual(progress.doubleValue, 0, "Failure must retire complete-looking progress immediately.")
        let status = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.stringValue == PrintLayoutSession.SessionError.missingPreview.localizedDescription })
        let cancel = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Cancel" })
        cancel.performClick(nil)
        observer(.capturingPages(completed: 75, total: 200))
        observer(.ready)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(rawCaptures, Array(0...200), "Late callbacks from a retired session must not escape to consumers.")
        XCTAssertEqual(progress.doubleValue, 0)
        XCTAssertEqual(status.stringValue, PrintLayoutSession.SessionError.missingPreview.localizedDescription)
        XCTAssertEqual(completions, 1)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(session.panelForTesting.isVisible)
        XCTAssertNil(parent.attachedSheet)
    }

    func testCaptureProgressCoalescesUIWithoutDroppingRawPhasesOrPages() async throws {
        weak var observedSession: PrintLayoutSession?
        var captures: [Int] = []
        var statuses: [String] = []
        var progressValues: [Double] = []
        var firstPageBeforeSecondCapture = false
        let started = ProcessInfo.processInfo.systemUptime
        let fixture = try await makeNavigationFixture(pageCount: 200, onPhase: { phase in
            if case .capturingPages(let completed, let total) = phase {
                XCTAssertEqual(total, 200)
                captures.append(completed)
            }
            if let root = observedSession?.panelForTesting.contentView {
                let views = self.descendants(of: root)
                if case .capturingPages(completed: 2, total: _) = phase {
                    firstPageBeforeSecondCapture = views.compactMap { $0 as? PDFView }.first?.document?.pageCount == 1
                }
                if let status = views.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue.contains("Preparing page") }) {
                    statuses.append(status.stringValue)
                }
                if let progress = views.compactMap({ $0 as? NSProgressIndicator }).first {
                    progressValues.append(progress.doubleValue)
                }
            }
        }, onSession: { observedSession = $0 })
        defer { disposeNavigationFixture(fixture) }
        try await waitForNavigationReady(fixture)
        XCTAssertTrue(firstPageBeforeSecondCapture, "The first captured page must display before the second capture, not wait for a UI batch.")
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let statusChanges = zip(statuses, statuses.dropFirst()).filter { $0 != $1 }.count
        let progressChanges = zip(progressValues, progressValues.dropFirst()).filter { $0 != $1 }.count
        let maximumRefreshes = Int(ceil(elapsed / 0.05)) + 8
        print("capture UI measurement: raw=\(captures.count) statusChanges=\(statusChanges) progressChanges=\(progressChanges) elapsed=\(elapsed)s maximumRefreshes=\(maximumRefreshes)")
        XCTAssertEqual(captures, Array(0...200), "Raw typed phase delivery must remain exact.")
        XCTAssertLessThanOrEqual(statusChanges, maximumRefreshes, "Fast capture should not redraw status for every page.")
        XCTAssertLessThanOrEqual(progressChanges, maximumRefreshes, "Fast capture should not redraw the progress bar for every page.")
        let pdf = try XCTUnwrap(fixture.preview.document)
        XCTAssertEqual(pdf.pageCount, 200)
        for index in 0..<200 {
            XCTAssertTrue(pdf.page(at: index)?.string?.contains("Owned page \(index + 1)") == true)
        }
        let root = try XCTUnwrap(fixture.session.panelForTesting.contentView)
        let progress = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSProgressIndicator }.first)
        XCTAssertEqual(progress.doubleValue, 200, "Ready must immediately flush final progress.")
        XCTAssertFalse(fixture.parent.isVisible)
        XCTAssertFalse(fixture.session.panelForTesting.isVisible)
        XCTAssertNil(fixture.parent.attachedSheet)
    }

    func testInitialPreviewFitsTheWholePageInsideItsViewport() async throws {
        let fixture = try await makeNavigationFixture()
        defer { disposeNavigationFixture(fixture) }
        let page = try XCTUnwrap(fixture.preview.currentPage)
        let rendered = fixture.preview.convert(page.bounds(for: .mediaBox), from: page)
        let viewport = fixture.preview.bounds
        XCTAssertGreaterThan(viewport.width, 100)
        XCTAssertGreaterThan(viewport.height, 100)
        XCTAssertLessThanOrEqual(rendered.width, viewport.width + 1, "Initial fit must show the entire page width, not merely set autoScales.")
        XCTAssertLessThanOrEqual(rendered.height, viewport.height + 1, "Initial fit must show the entire page height.")
        XCTAssertGreaterThanOrEqual(rendered.minX, viewport.minX - 1)
        XCTAssertGreaterThanOrEqual(rendered.minY, viewport.minY - 1)
        XCTAssertLessThanOrEqual(rendered.maxX, viewport.maxX + 1)
        XCTAssertLessThanOrEqual(rendered.maxY, viewport.maxY + 1)
    }

    func testInitialFitIncludesPaperLargerThanTheDefaultZoomMinimum() async throws {
        let fixture = try await makeNavigationFixture(paperSize: NSSize(width: 2384, height: 3370))
        defer { disposeNavigationFixture(fixture) }
        let page = try XCTUnwrap(fixture.preview.currentPage)
        let rendered = fixture.preview.convert(page.bounds(for: .mediaBox), from: page)
        XCTAssertLessThanOrEqual(rendered.width, fixture.preview.bounds.width + 1)
        XCTAssertLessThanOrEqual(rendered.height, fixture.preview.bounds.height + 1)
    }

    func testZoomButtonsDisableAtTheirConfiguredBounds() async throws {
        let fixture = try await makeNavigationFixture()
        defer { disposeNavigationFixture(fixture) }
        let root = try XCTUnwrap(fixture.session.panelForTesting.contentView)
        let zoomOut = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Zoom out" })
        let zoomIn = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Zoom in" })
        zoomOut.performClick(nil)
        for _ in 0..<60 { zoomOut.performClick(nil) }
        XCTAssertEqual(fixture.preview.scaleFactor, 0.2, accuracy: 0.001)
        XCTAssertFalse(zoomOut.isEnabled, "A clamped action must not remain available as a dead click.")
        XCTAssertTrue(zoomIn.isEnabled)
        for _ in 0..<60 { zoomIn.performClick(nil) }
        XCTAssertEqual(fixture.preview.scaleFactor, 4, accuracy: 0.001)
        XCTAssertFalse(zoomIn.isEnabled)
        XCTAssertTrue(zoomOut.isEnabled)
    }

    func testZoomButtonsFollowDirectPreviewScaleChanges() async throws {
        let fixture = try await makeNavigationFixture()
        defer { disposeNavigationFixture(fixture) }
        try await waitForNavigationReady(fixture)
        let root = try XCTUnwrap(fixture.session.panelForTesting.contentView)
        let zoomOut = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Zoom out" })
        let zoomIn = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Zoom in" })
        try await Task.sleep(nanoseconds: 50_000_000)
        fixture.preview.autoScales = false
        fixture.preview.scaleFactor = 0.2
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(zoomOut.isEnabled, "Scale changes outside our buttons must refresh their availability.")
        XCTAssertTrue(zoomIn.isEnabled)
        fixture.preview.scaleFactor = 4
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(zoomIn.isEnabled)
        XCTAssertTrue(zoomOut.isEnabled)
    }

    func testManualZoomAndSelectedPageSurviveHeadlessSettingsReplacement() async throws {
        let fixture = try await makeNavigationFixture()
        defer { disposeNavigationFixture(fixture) }
        try await waitForNavigationReady(fixture)
        let previous = try XCTUnwrap(fixture.preview.document)
        fixture.preview.go(to: try XCTUnwrap(previous.page(at: 5)))
        fixture.preview.autoScales = false
        fixture.preview.scaleFactor = 0.8
        let root = try XCTUnwrap(fixture.session.panelForTesting.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        XCTAssertTrue(fixture.preview.document === previous)
        try await waitForNavigationReady(fixture)
        let replacement = try XCTUnwrap(fixture.preview.document)
        XCTAssertFalse(replacement === previous)
        XCTAssertFalse(fixture.preview.autoScales)
        XCTAssertEqual(fixture.preview.scaleFactor, 0.8, accuracy: 0.001)
        XCTAssertEqual(replacement.index(for: try XCTUnwrap(fixture.preview.currentPage)), 5)
    }

    private typealias NavigationFixture = (parent: NonActivatingHeadlessHostWindow, prepared: PreparedPrintDocument, session: PrintLayoutSession, preview: PDFView, scratch: URL)

    private func waitForNavigationReady(_ fixture: NavigationFixture) async throws {
        let root = try XCTUnwrap(fixture.session.panelForTesting.contentView)
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !descendants(of: root).compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue.hasPrefix("Preview ready —") }), ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(descendants(of: root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("Preview ready —") })
    }

    private func makeNavigationFixture(paperSize: NSSize = NSSize(width: 612, height: 792), pageCount: Int = 20, onPhase: (@MainActor (PrintPreviewPhase) -> Void)? = nil, onSession: ((PrintLayoutSession) -> Void)? = nil) async throws -> NavigationFixture {
        var settings = PrintLayoutSettings.default
        settings.headingBreakLevel = 2
        settings.citationMode = .originalLinks
        let info = NSPrintInfo()
        info.paperSize = paperSize
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: (1...pageCount).map { "<h2>Owned page \($0)</h2><p>Navigation stays available while the remaining pages prepare.</p>" }.joined(), title: "Navigation polish", baseURL: nil, settings: settings, printInfo: info)
        var transferred = false
        defer { if !transferred { prepared.releaseHold() } }
        let parent = NonActivatingHeadlessHostWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.alphaValue = 0
        defer { if !transferred { parent.close() } }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "headless-navigation")
        defer { if !transferred { try? FileManager.default.removeItem(at: scratch) } }
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .export(scratch.appendingPathComponent("unused.pdf"), { _ in }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, onPhase: onPhase, presentation: .headless)
        onSession?(session)
        session.begin()
        let root = try XCTUnwrap(session.panelForTesting.contentView)
        root.layoutSubtreeIfNeeded()
        let preview = try XCTUnwrap(descendants(of: root).compactMap { $0 as? PDFView }.first)
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while preview.document?.pageCount ?? 0 == 0, ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertGreaterThan(preview.document?.pageCount ?? 0, 0)
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(session.panelForTesting.isVisible)
        XCTAssertNil(parent.attachedSheet)
        transferred = true
        return (parent, prepared, session, preview, scratch)
    }

    private func disposeNavigationFixture(_ fixture: NavigationFixture) {
        if let root = fixture.session.panelForTesting.contentView {
            descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }?.performClick(nil)
        }
        fixture.session.panelForTesting.close()
        fixture.prepared.releaseHold()
        fixture.parent.close()
        try? FileManager.default.removeItem(at: fixture.scratch)
    }

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
