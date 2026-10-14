import AppKit
import PDFKit
import WebKit
import XCTest
@testable import OuroMD

private final class NonActivatingChooserWindow: NSWindow {
    var requestedFront = false

    override func makeKeyAndOrderFront(_ sender: Any?) {
        requestedFront = true
    }
}

private final class DelayedPrintHTMLWebView: WKWebView {
    var htmlCompletion: ((Any?, Error?) -> Void)?

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        htmlCompletion = completionHandler
    }
}

@MainActor
final class PrintPreviewSessionTests: XCTestCase {
    func testSheetAndBusyProgressExistBeforeDelayedDocumentLoaderReturns() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        var loaderStarted = false
        var phases: [PrintPreviewPhase] = []
        var announcements: [String] = []
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            loaderStarted = true
            observer?(.extractingHTML)
            try await Task.sleep(nanoseconds: 200_000_000)
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>LOADED-TOKEN</p>", title: "Delayed", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), printPanelChooser: { _ in false }, reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, onPhase: { phases.append($0) }, announceAccessibilityPhase: { announcements.append($0) })
        session.begin()
        let sheet = try XCTUnwrap(parent.attachedSheet)
        XCTAssertFalse(loaderStarted, "The sheet must be constructed synchronously before the loader task starts.")
        let progress = try XCTUnwrap(sheet.contentView.flatMap { descendants(of: $0).compactMap { $0 as? NSProgressIndicator }.first })
        XCTAssertTrue(progress.isIndeterminate)
        XCTAssertEqual(progress.accessibilityLabel(), "Print preview progress")
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        XCTAssertEqual(phases.first, .extractingHTML)
        XCTAssertEqual(phases.last, .ready)
        XCTAssertFalse(progress.isIndeterminate)
        XCTAssertEqual(progress.doubleValue, progress.maxValue)
        XCTAssertEqual(Set(announcements).count, announcements.count)
        cancelSession(in: parent)
    }

    func testCancelDuringInitialLoadReleasesLateDocumentAndCompletesOnce() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        let originalHolds = PreparedPrintDocument.retainedCountForTesting
        var completions = 0
        var loaderStarted = false
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            loaderStarted = true
            try await Task.sleep(nanoseconds: 400_000_000)
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Cancelled</p>", title: "Cancel", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .export(URL(fileURLWithPath: "/tmp/must-not-export-refinement.pdf"), { _ in completions += 1 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in })
        session.begin()
        _ = try await waitUntil { loaderStarted }
        cancelSession(in: parent)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(completions, 1)
        XCTAssertNil(parent.attachedSheet)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
        XCTAssertEqual(PreparedPrintDocument.retainedCountForTesting, originalHolds)
    }

    func testDuplicateSessionDoesNotInvokeSecondLoader() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        var loads = 0
        let loader: PrintLayoutSession.DocumentLoader = { settings, info, observer in
            loads += 1
            try await Task.sleep(nanoseconds: 150_000_000)
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>One sheet</p>", title: "One", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }
        let first = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: loader, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in })
        let second = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: loader, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in })
        first.begin()
        second.begin()
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        XCTAssertEqual(loads, 1)
        XCTAssertTrue(PrintLayoutSession.activeSession(for: parent) === first)
        cancelSession(in: parent)
    }

    func testInitialFailureExposesRetryWithoutAutomaticallySubmitting() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        var attempts = 0
        var completed = false
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            attempts += 1
            if attempts == 1 { throw PrintLayoutSession.SessionError.missingPreview }
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>RETRY-TOKEN</p>", title: "Retry", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .export(URL(fileURLWithPath: "/tmp/must-not-auto-export-refinement.pdf"), { _ in completed = true }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in })
        session.begin()
        let failed = try await waitUntil { self.button(named: "Retry", in: parent)?.isHidden == false }
        XCTAssertTrue(failed)
        XCTAssertFalse(exportButton(in: parent)?.isEnabled == true)
        button(named: "Retry", in: parent)?.performClick(nil)
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(completed)
        XCTAssertTrue(button(named: "Retry", in: parent)?.isHidden == true)
        cancelSession(in: parent)
    }

    func testSettingsUpdateRetainsOldPreviewAndLatestNavigationAndZoom() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let body = (1...100).map { "<h2>Section \($0)</h2><p>CONTINUITY-\($0)-TOKEN</p>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Continuity", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let session = makeSession(prepared: prepared, parent: parent, output: URL(fileURLWithPath: "/tmp/continuity-not-exported.pdf"))
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        let preview = try XCTUnwrap(previewView(in: parent))
        let old = try XCTUnwrap(preview.document)
        preview.go(to: try XCTUnwrap(old.page(at: 65)))
        preview.autoScales = false
        preview.scaleFactor = 0.8
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        XCTAssertTrue(preview.document === old)
        XCTAssertTrue(descendants(of: root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Previous layout") })
        preview.go(to: try XCTUnwrap(old.page(at: 75)))
        let ready = try await waitUntil { self.previewIsReady(in: parent) && preview.document !== old }
        XCTAssertTrue(ready)
        let current = try XCTUnwrap(preview.document)
        XCTAssertEqual(preview.currentPage.map { current.index(for: $0) }, 75)
        XCTAssertFalse(preview.autoScales)
        XCTAssertEqual(preview.scaleFactor, 0.8, accuracy: 0.01)
        cancelSession(in: parent)
    }

    private func button(named title: String, in parent: NSWindow) -> NSButton? {
        parent.attachedSheet?.contentView.flatMap { descendants(of: $0).compactMap { $0 as? NSButton }.first { $0.title == title } }
    }

    func testInitialSettingsEditsReconcileWithoutExtractingHTMLAgain() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        var loads = 0
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            loads += 1
            try await Task.sleep(nanoseconds: 200_000_000)
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Initial edits</p>", title: "Initial edits", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in })
        session.begin()
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(session.prepared?.settings.fontSize, 14)
        cancelSession(in: parent)
    }

    func testFailedUpdateRestoresOldPreviewAndValidRetryDoesNotSubmit() async throws {
        let script = try XCTUnwrap(PrintLayoutScriptLoader.load()) + """
        ;(function(){var apply=window.OuroPrintLayout.apply;window.OuroPrintLayout.apply=function(){if(window.__ouroPrintLayoutConfig.fontSizeForTestFailure){throw new Error('Synthetic failure');}return apply();};})();
        """
        let failingScript = script.replacingOccurrences(of: "window.__ouroPrintLayoutConfig.fontSizeForTestFailure", with: "parseFloat(getComputedStyle(document.body).fontSize)>13")
        let prepared = try await PrintDocumentRenderer(scriptProvider: { failingScript }).prepareDocument(bodyHTML: "<p>Retained complete preview</p>", title: "Failure", baseURL: nil, settings: .default)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let session = makeSession(prepared: prepared, parent: parent, output: URL(fileURLWithPath: "/tmp/failed-update-not-exported.pdf"))
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        let preview = try XCTUnwrap(previewView(in: parent))
        let old = try XCTUnwrap(preview.document)
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        let failed = try await waitUntil { self.button(named: "Retry", in: parent)?.isHidden == false }
        XCTAssertTrue(failed)
        XCTAssertTrue(preview.document === old)
        XCTAssertFalse(exportButton(in: parent)?.isEnabled == true)
        font.stringValue = "invalid"
        button(named: "Retry", in: parent)?.performClick(nil)
        XCTAssertFalse(exportButton(in: parent)?.isEnabled == true)
        XCTAssertTrue(preview.document === old)
        font.stringValue = "12"
        _ = font.sendAction(font.action, to: font.target)
        button(named: "Retry", in: parent)?.performClick(nil)
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        XCTAssertTrue(button(named: "Retry", in: parent)?.isHidden == true)
        XCTAssertNotNil(parent.attachedSheet)
        cancelSession(in: parent)
    }

    func testFinalPaperChangeShowsCancellableProgressAndNeverSpoolsAfterCancel() async throws {
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Selected paper progress</p>", title: "Final paper", baseURL: nil, settings: .default)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        var chooserFinished = false
        var sawCancellableProgress = false
        var sawDisabledLayoutEdits = false
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), printPanelChooser: { info in
            info.orientation = info.orientation == .portrait ? .landscape : .portrait
            chooserFinished = true
            return true
        }, reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, onPhase: { phase in
            if chooserFinished, phase == .loadingHTML {
                sawCancellableProgress = parent.attachedSheet != nil && self.button(named: "Cancel", in: parent)?.isEnabled == true
                if let root = parent.attachedSheet?.contentView {
                    let fields = self.descendants(of: root).compactMap { $0 as? NSTextField }.filter(\.isEditable)
                    let choices = self.descendants(of: root).compactMap { $0 as? NSPopUpButton }
                    sawDisabledLayoutEdits = !fields.isEmpty && fields.allSatisfy { !$0.isEnabled } && choices.allSatisfy { !$0.isEnabled }
                }
                self.cancelSession(in: parent)
            }
        })
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        button(named: "Continue to Print", in: parent)?.performClick(nil)
        XCTAssertTrue(sawCancellableProgress)
        XCTAssertTrue(sawDisabledLayoutEdits)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
        XCTAssertNil(parent.attachedSheet)
    }

    func testRepeatPrintDuringNativeChooserDoesNotReopenLayoutOrStartLoader() async throws {
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>One print request</p>", title: "Repeat print", baseURL: nil, settings: .default)
        let parent = NonActivatingChooserWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 980, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.alphaValue = 0
        parent.orderFront(nil)
        defer { parent.close(); prepared.releaseHold() }
        let editor = WKWebView()
        parent.contentView = editor
        let coordinator = EditorWebView.Coordinator(model: AppModel(), printSettingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()))
        coordinator.webView = editor
        var session: PrintLayoutSession?
        var didCheckChooser = false
        session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), printPanelChooser: { _ in
            XCTAssertNil(parent.attachedSheet, "The layout is hidden while native output UI owns the request.")
            coordinator.printDocument()
            XCTAssertTrue(parent.requestedFront, "Repeated Print fronts the owning window without activating the test process.")
            XCTAssertNil(parent.attachedSheet, "Repeated Print must not reopen the hidden layout sheet.")
            XCTAssertTrue(PrintLayoutSession.activeSession(for: parent) === session)
            didCheckChooser = true
            return false
        }, reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in })
        session?.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        button(named: "Continue to Print", in: parent)?.performClick(nil)
        XCTAssertTrue(didCheckChooser)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
    }

    func testAccessibilityAnnouncementsAreSemanticAcrossCaptureFailureAndRetry() async throws {
        let script = try XCTUnwrap(PrintLayoutScriptLoader.load()) + """
        ;(function(){var apply=window.OuroPrintLayout.apply;window.OuroPrintLayout.apply=function(){if(parseFloat(getComputedStyle(document.body).fontSize)>13){throw new Error('SYNTHETIC-ERROR-NOT-FOR-AX');}return apply();};})();
        """
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let body = (1...60).map { "<h2>Section \($0)</h2><p>Accessibility capture</p>" }.joined()
        let prepared = try await PrintDocumentRenderer(scriptProvider: { script }).prepareDocument(bodyHTML: body, title: "Accessible phases", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        var announcements: [String] = []
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in }, announceAccessibilityPhase: { announcements.append($0) })
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertEqual(announcements.filter { $0 == "Preparing preview pages." }.count, 1, "Sixty page captures must produce one semantic capture announcement.")
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        _ = try await waitUntil { self.button(named: "Retry", in: parent)?.isHidden == false }
        XCTAssertEqual(announcements.filter { $0 == "Print preview preparation failed. Retry or Cancel is available." }.count, 1)
        XCTAssertFalse(announcements.contains { $0.contains("SYNTHETIC-ERROR-NOT-FOR-AX") })
        font.stringValue = "12"
        _ = font.sendAction(font.action, to: font.target)
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertEqual(announcements.filter { $0 == "Preparing preview pages." }.count, 2, "A new successful generation gets its own capture announcement, not one per page.")
        XCTAssertEqual(announcements.filter { $0 == "Print preview ready." }.count, 2)
        cancelSession(in: parent)
        let count = announcements.count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(announcements.count, count, "Retired generations cannot announce.")
    }

    func testShrinkingPageCountKeepsNearestValidLatestSelectedPage() async throws {
        let body = (1...400).map { "<p>SHRINK-PASSAGE-\($0)-TOKEN Readable prose fills multiple pages while retaining all the source text.</p>" }.joined()
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Shrink preview", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let session = makeSession(prepared: prepared, parent: parent, output: URL(fileURLWithPath: "/tmp/shrink-not-exported.pdf"))
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        let preview = try XCTUnwrap(previewView(in: parent))
        let old = try XCTUnwrap(preview.document)
        preview.go(to: try XCTUnwrap(old.page(at: old.pageCount - 1)))
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "8"
        _ = font.sendAction(font.action, to: font.target)
        XCTAssertTrue(preview.document === old)
        let ready = try await waitUntil { self.previewIsReady(in: parent) && preview.document !== old }
        XCTAssertTrue(ready)
        let current = try XCTUnwrap(preview.document)
        XCTAssertLessThan(current.pageCount, old.pageCount)
        XCTAssertEqual(preview.currentPage.map { current.index(for: $0) }, current.pageCount - 1)
        XCTAssertTrue(current.string?.contains("SHRINK-PASSAGE-400-TOKEN") == true)
        cancelSession(in: parent)
    }

    func testABAEditAndQueuedExportOnlySealLatestGeneration() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let body = (1...100).map { "<h2>Section \($0)</h2><p>ABA-PAGE-\($0)-TOKEN</p>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "ABA generations", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "aba-preview")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appendingPathComponent("latest.pdf")
        var result: Result<Bool, Error>?
        var readyEvents = 0
        var loadingEvents = 0
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .export(output, { result = $0 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, onPhase: { phase in
            if phase == .ready { readyEvents += 1 }
            if phase == .loadingHTML { loadingEvents += 1 }
        })
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        _ = try await waitUntil { loadingEvents > 0 }
        font.stringValue = "12"
        _ = font.sendAction(font.action, to: font.target)
        exportButton(in: parent)?.performClick(nil)
        XCTAssertNil(result, "Returning to A must not reuse a seal from an older generation.")
        let finished = try await waitUntil { result != nil }
        XCTAssertTrue(finished)
        guard case .success(true)? = result else { return XCTFail("Latest ABA output was not exported.") }
        XCTAssertEqual(readyEvents, 2, "Only original A and the latest A may seal; superseded B cannot become ready.")
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 100)
        for index in 0..<100 { XCTAssertTrue(pdf.page(at: index)?.string?.contains("ABA-PAGE-\(index + 1)-TOKEN") == true) }
    }

    func testUnrelatedSheetRejectsBothCoordinatorExportAndSessionLoader() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        let editor = WKWebView()
        parent.contentView = editor
        let other = NSPanel()
        other.isReleasedWhenClosed = false
        parent.beginSheet(other, completionHandler: nil)
        defer { parent.endSheet(other); other.close() }
        let coordinator = EditorWebView.Coordinator(model: AppModel())
        coordinator.webView = editor
        var coordinatorResult: Result<Bool, Error>?
        coordinator.exportPDF(to: URL(fileURLWithPath: "/tmp/blocked-coordinator.pdf")) { coordinatorResult = $0 }
        guard case .failure? = coordinatorResult else { return XCTFail("An unrelated sheet must reject interactive export synchronously.") }
        var loaded = false
        var sessionResult: Result<Bool, Error>?
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            loaded = true
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Must not load</p>", title: "Blocked", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .export(URL(fileURLWithPath: "/tmp/blocked-session.pdf"), { sessionResult = $0 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in })
        session.begin()
        guard case .failure? = sessionResult else { return XCTFail("Defensive session admission must reject the unrelated sheet.") }
        XCTAssertFalse(loaded)
        XCTAssertTrue(parent.attachedSheet === other)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
    }

    func testRepeatedPrintDuringExportReportsUnavailableWithoutReplacingSession() async throws {
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Existing export</p>", title: "Export owner", baseURL: nil, settings: .default)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let editor = WKWebView()
        parent.contentView = editor
        let model = AppModel()
        var errors = 0
        model.presentErrorHandler = { _, _ in errors += 1 }
        let coordinator = EditorWebView.Coordinator(model: model)
        coordinator.webView = editor
        let session = makeSession(prepared: prepared, parent: parent, output: URL(fileURLWithPath: "/tmp/export-owner.pdf"))
        session.begin()
        let sheet = parent.attachedSheet
        coordinator.printDocument()
        XCTAssertEqual(errors, 1)
        XCTAssertTrue(PrintLayoutSession.activeSession(for: parent) === session)
        XCTAssertTrue(parent.attachedSheet === sheet)
        cancelSession(in: parent)
    }

    func testCancellingProductHTMLAcquisitionIgnoresLateCallback() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        let editor = DelayedPrintHTMLWebView()
        parent.contentView = editor
        let coordinator = EditorWebView.Coordinator(model: AppModel(), printSettingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()))
        coordinator.webView = editor
        var completions = 0
        var result: Result<Bool, Error>?
        var phases: [PrintPreviewPhase] = []
        coordinator.onPrintPhase = { phases.append($0) }
        coordinator.exportPDF(to: URL(fileURLWithPath: "/tmp/cancelled-html.pdf")) { result = $0; completions += 1 }
        let pending = try await waitUntil { editor.htmlCompletion != nil }
        XCTAssertTrue(pending)
        let holds = PreparedPrintDocument.retainedCountForTesting
        cancelSession(in: parent)
        guard case .success(false)? = result else { return XCTFail("Cancelling HTML acquisition must complete the export once.") }
        editor.htmlCompletion?("<p>Late HTML must not construct a renderer.</p>", nil)
        editor.htmlCompletion = nil
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(PreparedPrintDocument.retainedCountForTesting, holds)
        XCTAssertFalse(phases.contains(.ready))
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
        XCTAssertNil(parent.attachedSheet)
    }

    func testParentCloseDuringInitialLoadCompletesCancellationOnce() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        var completions = 0
        var started = false
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            started = true
            try await Task.sleep(nanoseconds: 500_000_000)
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Closed parent</p>", title: "Close", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .export(URL(fileURLWithPath: "/tmp/closed-parent.pdf"), { _ in completions += 1 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in })
        session.begin()
        _ = try await waitUntil { started }
        parent.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(completions, 1)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
    }

    func testSelectedPaperPreparationCompletesAndSealsWithoutASecondChooser() async throws {
        let initial = NSPrintInfo()
        initial.paperSize = NSSize(width: 612, height: 792)
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Complete selected paper</p>", title: "Selected paper completion", baseURL: nil, settings: .default, printInfo: initial)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        var chooserCount = 0
        var completedPaperSize: NSSize?
        var sawAsyncPreparation = false
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), printPanelChooser: { info in
            chooserCount += 1
            info.paperSize = NSSize(width: 595, height: 842)
            return true
        }, reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, onPhase: { phase in
            guard chooserCount > 0 else { return }
            if phase == .paginating { sawAsyncPreparation = parent.attachedSheet != nil }
            if phase == .ready {
                let preview = self.previewView(in: parent)
                completedPaperSize = preview?.document?.page(at: 0)?.bounds(for: .mediaBox).size
                self.cancelSession(in: parent)
            }
        })
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        button(named: "Continue to Print", in: parent)?.performClick(nil)
        let finished = try await waitUntil { completedPaperSize != nil }
        XCTAssertTrue(finished)
        XCTAssertEqual(try XCTUnwrap(completedPaperSize).width, 595, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(completedPaperSize).height, 842, accuracy: 1)
        XCTAssertTrue(sawAsyncPreparation)
        XCTAssertEqual(chooserCount, 1)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
    }

    func testParentCloseDuringAsyncSelectedPaperPreparationPreventsOutput() async throws {
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Close selected paper</p>", title: "Close output", baseURL: nil, settings: .default)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        var chooserFinished = false
        var closedAsyncPreparation = false
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), printPanelChooser: { info in
            info.paperSize = NSSize(width: 595, height: 842)
            chooserFinished = true
            return true
        }, reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, onPhase: { phase in
            if chooserFinished, phase == .paginating {
                closedAsyncPreparation = true
                parent.close()
            }
        })
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        button(named: "Continue to Print", in: parent)?.performClick(nil)
        let closed = try await waitUntil { closedAsyncPreparation }
        XCTAssertTrue(closed)
        XCTAssertNil(PrintLayoutSession.activeSession(for: parent))
        XCTAssertNil(parent.attachedSheet)
    }

    func testSelectedPaperFailureKeepsOldPreviewAndExposesRetry() async throws {
        let script = try XCTUnwrap(PrintLayoutScriptLoader.load()) + """
        ;(function(){var apply=window.OuroPrintLayout.apply;window.OuroPrintLayout.apply=function(){if(window.__ouroPrintLayoutConfig.pageWidth<600){throw new Error('Synthetic selected paper failure');}return apply();};})();
        """
        let initial = NSPrintInfo()
        initial.paperSize = NSSize(width: 612, height: 792)
        let prepared = try await PrintDocumentRenderer(scriptProvider: { script }).prepareDocument(bodyHTML: "<p>Preserve original complete layout</p>", title: "Selected paper failure", baseURL: nil, settings: .default, printInfo: initial)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        var chooserCount = 0
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), printPanelChooser: { info in
            chooserCount += 1
            info.paperSize = NSSize(width: 595, height: 842)
            return true
        }, reportError: { _, _ in }, telemetry: { _, _ in })
        session.begin()
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        let old = previewView(in: parent)?.document
        button(named: "Continue to Print", in: parent)?.performClick(nil)
        let failed = try await waitUntil { self.button(named: "Retry", in: parent)?.isHidden == false }
        XCTAssertTrue(failed)
        XCTAssertTrue(previewView(in: parent)?.document === old)
        XCTAssertFalse(button(named: "Continue to Print", in: parent)?.isEnabled == true)
        XCTAssertEqual(chooserCount, 1)
        cancelSession(in: parent)
    }

    func testInitialEditsDoNotRegressAnAlreadyLoadingPhaseToExtraction() async throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        var phases: [PrintPreviewPhase] = []
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { settings, info, observer in
            observer?(.loadingHTML)
            try await Task.sleep(nanoseconds: 200_000_000)
            return try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Keep the current phase</p>", title: "Current phase", baseURL: nil, settings: settings, printInfo: info, onPhase: observer)
        }, parentWindow: parent, action: .print, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in }, onPhase: { phases.append($0) })
        session.begin()
        _ = try await waitUntil { phases.last == .loadingHTML }
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        let font = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "14"
        _ = font.sendAction(font.action, to: font.target)
        XCTAssertEqual(phases.last, .loadingHTML)
        XCTAssertEqual(phases.filter { $0 == .extractingHTML }.count, 1)
        _ = try await waitUntil { self.previewIsReady(in: parent) }
        cancelSession(in: parent)
    }

    func testFailedInitialStreamIsLabeledIncompleteAndProgressDoesNotLookComplete() async throws {
        let script = try XCTUnwrap(PrintLayoutScriptLoader.load()) + """
        ;(function(){var show=window.OuroPrintLayout.showPage;window.OuroPrintLayout.showPage=function(index){if(index>0){throw new Error('Synthetic second-page capture failure');}return show(index);};})();
        """
        var settings = PrintLayoutSettings.default
        settings.headingBreakLevel = 2
        let prepared = try await PrintDocumentRenderer(scriptProvider: { script }).prepareDocument(bodyHTML: "<h2>First</h2><p>Partial preview</p><h2>Second</h2><p>Failed capture</p>", title: "Partial failure", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let session = makeSession(prepared: prepared, parent: parent, output: URL(fileURLWithPath: "/tmp/partial-failure.pdf"))
        session.begin()
        let failed = try await waitUntil { self.button(named: "Retry", in: parent)?.isHidden == false }
        XCTAssertTrue(failed)
        let root = try XCTUnwrap(parent.attachedSheet?.contentView)
        XCTAssertTrue(descendants(of: root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("Incomplete preview — preparation failed.") })
        XCTAssertEqual(previewView(in: parent)?.document?.pageCount, 1)
        let progress = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSProgressIndicator }.first)
        XCTAssertEqual(progress.doubleValue, 0)
        XCTAssertFalse(exportButton(in: parent)?.isEnabled == true)
        cancelSession(in: parent)
    }

    func testExplicitSettingsExportResolvesIfCoordinatorRetiresDuringHTMLAcquisition() async throws {
        let editor = DelayedPrintHTMLWebView()
        var coordinator: EditorWebView.Coordinator? = EditorWebView.Coordinator(model: AppModel())
        coordinator?.webView = editor
        weak var retiredCoordinator = coordinator
        var completions = 0
        var result: Result<Bool, Error>?
        coordinator?.exportPDF(to: URL(fileURLWithPath: "/tmp/retired-explicit-export.pdf"), settings: .default) { result = $0; completions += 1 }
        XCTAssertNotNil(editor.htmlCompletion)
        coordinator = nil
        XCTAssertNil(retiredCoordinator)
        editor.htmlCompletion?("<p>Retired explicit request</p>", nil)
        editor.htmlCompletion = nil
        XCTAssertEqual(completions, 1)
        guard case .failure? = result else { return XCTFail("Retired explicit HTML acquisition must fail rather than leave its completion unresolved.") }
    }

    func testExplicitSettingsExportPreservesHeadlessCompleteOutput() async throws {
        let editor = DelayedPrintHTMLWebView()
        let parent = makeParentWindow()
        defer { parent.close() }
        parent.contentView = editor
        let coordinator = EditorWebView.Coordinator(model: AppModel())
        coordinator.webView = editor
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "explicit-preview")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appendingPathComponent("explicit.pdf")
        var result: Result<Bool, Error>?
        var settings = PrintLayoutSettings.default
        settings.fontSize = 15
        settings.citationMode = .originalLinks
        coordinator.exportPDF(to: output, settings: settings) { result = $0 }
        XCTAssertNil(parent.attachedSheet, "Explicit settings must preserve the supported non-interactive export path.")
        editor.htmlCompletion?("<p>EXPLICIT-PDF-TOKEN</p>", nil)
        editor.htmlCompletion = nil
        let finished = try await waitUntil { result != nil }
        XCTAssertTrue(finished)
        guard case .success(true)? = result else { return XCTFail("Explicit-settings export did not finish.") }
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 1)
        let page = try XCTUnwrap(pdf.page(at: 0))
        let text = try XCTUnwrap(page.string)
        let range = try XCTUnwrap(text.range(of: "EXPLICIT-PDF-TOKEN"))
        let selection = try XCTUnwrap(page.selection(for: NSRange(range, in: text)))
        let font = try XCTUnwrap(NSFont(name: "Georgia", size: 15))
        XCTAssertEqual(selection.bounds(for: page).width, ("EXPLICIT-PDF-TOKEN" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1)
        XCTAssertNil(parent.attachedSheet)
    }

    private func cancelSession(in parent: NSWindow) {
        button(named: "Cancel", in: parent)?.performClick(nil)
    }

    func testOpeningPreviewReusesTheAlreadyPreparedLayout() async throws {
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h1>Prepared layout</h1><p>Keep the completed layout.</p>", title: "Prepared preview", baseURL: nil, settings: .default)
        _ = try await prepared.webView.evaluateJavaScript("window.__ouroPreparedLayoutMarker = true")
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "prepared-preview")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let session = makeSession(prepared: prepared, parent: parent, output: scratch.appendingPathComponent("output.pdf"))
        session.begin()
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        let survived = try await prepared.webView.evaluateJavaScript("window.__ouroPreparedLayoutMarker === true") as? Bool
        XCTAssertEqual(survived, true, "Opening the layout sheet must not navigate and rebuild an identical prepared document")
    }

    func testPaperChangeStillInvalidatesThePreparedLayout() async throws {
        let initial = NSPrintInfo()
        initial.paperSize = NSSize(width: 612, height: 792)
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h1>Changed paper</h1><p>Use the selected dimensions.</p>", title: "Changed paper", baseURL: nil, settings: .default, printInfo: initial)
        _ = try await prepared.webView.evaluateJavaScript("window.__ouroPreparedLayoutMarker = true")
        let selected = NSPrintInfo()
        selected.paperSize = NSSize(width: 595, height: 842)
        prepared.setPageSettings(selected)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "paper-preview")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let session = makeSession(prepared: prepared, parent: parent, output: scratch.appendingPathComponent("output.pdf"))
        session.begin()
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        let survived = try await prepared.webView.evaluateJavaScript("window.__ouroPreparedLayoutMarker === true") as? Bool
        XCTAssertEqual(survived, false)
        let preview = try XCTUnwrap(previewView(in: parent))
        let page = try XCTUnwrap(preview.document?.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 595, accuracy: 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 842, accuracy: 1)
    }

    func testFirstPreviewPageAppearsBeforeTheEntireOutputIsReady() async throws {
        let prose = (1...800).map { "<p>Preview passage \($0) preserves the full document while the first page becomes available.</p>" }.joined()
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: prose, title: "Progressive preview", baseURL: nil, settings: settings)
        XCTAssertGreaterThan(prepared.layoutMetrics.pageCount, 20)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "progressive-preview")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let session = makeSession(prepared: prepared, parent: parent, output: scratch.appendingPathComponent("output.pdf"))
        session.begin()
        var sawFirstPageWhilePreparing = false
        let ready = try await waitUntil {
            if let document = self.previewView(in: parent)?.document,
               document.pageCount > 0, !self.previewIsReady(in: parent) {
                sawFirstPageWhilePreparing = true
            }
            return self.previewIsReady(in: parent)
        }
        XCTAssertTrue(ready)
        XCTAssertTrue(sawFirstPageWhilePreparing, "Readers must see the first page instead of a blank preview until every output page is captured")
        XCTAssertEqual(previewView(in: parent)?.document?.pageCount, prepared.layoutMetrics.pageCount)
    }

    func testPageNavigationAndZoomDoNotRebuildTheDocument() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h2>First section</h2><p>FIRST-PASSAGE</p><h2>Second section</h2><p>SECOND-PASSAGE</p>", title: "Navigate preview", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "preview-navigation")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let session = makeSession(prepared: prepared, parent: parent, output: scratch.appendingPathComponent("output.pdf"))
        session.begin()
        let ready = try await waitUntil { self.previewIsReady(in: parent) }
        XCTAssertTrue(ready)
        let preview = try XCTUnwrap(previewView(in: parent))
        let document = try XCTUnwrap(preview.document)
        XCTAssertGreaterThan(preview.bounds.width, 300)
        XCTAssertGreaterThan(preview.bounds.height, 400)
        XCTAssertEqual(preview.displayMode, .singlePage)
        guard let root = parent.attachedSheet?.contentView else { return XCTFail("Missing preview controls") }
        let buttons = descendants(of: root).compactMap { $0 as? NSButton }
        let next = try XCTUnwrap(buttons.first { $0.title == "Next" })
        let previous = try XCTUnwrap(buttons.first { $0.title == "Previous" })
        let zoomIn = try XCTUnwrap(buttons.first { $0.title == "Zoom in" })
        let fit = try XCTUnwrap(buttons.first { $0.title == "Fit page" })
        XCTAssertTrue(next.isEnabled)
        XCTAssertFalse(previous.isEnabled)
        next.performClick(nil)
        XCTAssertEqual(preview.currentPage.map { document.index(for: $0) }, 1)
        XCTAssertTrue(previous.isEnabled)
        XCTAssertFalse(next.isEnabled)
        previous.performClick(nil)
        XCTAssertEqual(preview.currentPage.map { document.index(for: $0) }, 0)
        let scale = preview.scaleFactor
        zoomIn.performClick(nil)
        XCTAssertGreaterThan(preview.scaleFactor, scale)
        fit.performClick(nil)
        XCTAssertTrue(preview.autoScales)
        XCTAssertTrue(preview.document === document)
        XCTAssertTrue(exportButton(in: parent)?.isEnabled == true)
    }

    func testSubmittingDuringPreviewPreparationQueuesCompleteOutputWithLaterFieldEdits() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let body = (1...200).map { "<h2>Section \($0)</h2><p>QUEUED-PAGE-\($0)-TOKEN</p>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Queued print output", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "queued-preview")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appendingPathComponent("complete.pdf")
        var result: Result<Bool, Error>?
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .export(output, { result = $0 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in })
        session.begin()
        let firstPage = try await waitUntil { (self.previewView(in: parent)?.document?.pageCount ?? 0) > 0 }
        XCTAssertTrue(firstPage)
        guard let root = parent.attachedSheet?.contentView else { return XCTFail("Missing preview sheet") }
        let labels = descendants(of: root).compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue.hasPrefix("Preparing page ") })
        let export = try XCTUnwrap(exportButton(in: parent))
        XCTAssertTrue(export.isEnabled, "A reader must be able to request output while remaining preview pages are preparing")
        guard export.isEnabled else { return }
        let font = try XCTUnwrap(labels.first { $0.accessibilityLabel() == "Font size (pt)" })
        font.stringValue = "10"
        export.performClick(nil)
        XCTAssertNil(result, "A queued request must never export only the pages captured so far")
        font.stringValue = "14"
        let completed = try await waitUntil { result != nil }
        XCTAssertTrue(completed)
        guard case .success(true)? = result else { return XCTFail("Queued export did not finish successfully") }
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 200)
        for index in 0..<200 {
            XCTAssertTrue(pdf.page(at: index)?.string?.contains("QUEUED-PAGE-\(index + 1)-TOKEN") == true)
        }
        let finalPage = try XCTUnwrap(pdf.page(at: 199))
        let text = try XCTUnwrap(finalPage.string)
        let token = "QUEUED-PAGE-200-TOKEN"
        let tokenRange = try XCTUnwrap(text.range(of: token))
        let selection = try XCTUnwrap(finalPage.selection(for: NSRange(tokenRange, in: text)))
        let expectedFont = try XCTUnwrap(NSFont(name: "Georgia", size: 14))
        let expectedWidth = (token as NSString).size(withAttributes: [.font: expectedFont]).width
        XCTAssertEqual(selection.bounds(for: finalPage).width, expectedWidth, accuracy: 1, "Queued output must commit the later, still-uncommitted 14 pt value")
    }

    func testQueuedOutputDoesNotProceedAfterALaterInvalidFieldEdit() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let body = (1...200).map { "<h2>Section \($0)</h2><p>Preserve the queued document and its validation.</p>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Invalid queued print", baseURL: nil, settings: settings)
        let parent = makeParentWindow()
        defer { parent.close(); prepared.releaseHold() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "invalid-queued-preview")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appendingPathComponent("must-not-export.pdf")
        var result: Result<Bool, Error>?
        let session = PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .export(output, { result = $0 }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in })
        session.begin()
        let firstPage = try await waitUntil { (self.previewView(in: parent)?.document?.pageCount ?? 0) > 0 }
        XCTAssertTrue(firstPage)
        guard let root = parent.attachedSheet?.contentView else { return XCTFail("Missing preview sheet") }
        let labels = descendants(of: root).compactMap { $0 as? NSTextField }
        let font = try XCTUnwrap(labels.first { $0.accessibilityLabel() == "Font size (pt)" })
        let export = try XCTUnwrap(exportButton(in: parent))
        XCTAssertTrue(export.isEnabled)
        font.stringValue = "10"
        export.performClick(nil)
        font.stringValue = "invalid"
        _ = font.sendAction(font.action, to: font.target)
        let finishedRendering = try await waitUntil { self.previewIsReady(in: parent) || result != nil }
        XCTAssertTrue(finishedRendering)
        XCTAssertNil(result, "An invalid final field must stop a queued output request")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "Last-valid settings must not silently replace the visible invalid input")
        XCTAssertNotNil(parent.attachedSheet)
        XCTAssertFalse(export.isEnabled)
        XCTAssertTrue(labels.contains { $0.accessibilityLabel() == "Print layout validation" && !$0.stringValue.isEmpty })
        if parent.attachedSheet != nil {
            let cancel = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Cancel" })
            cancel.performClick(nil)
        }
    }

    private func makeParentWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 980, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.orderFront(nil)
        return window
    }

    private func makeSession(prepared: PreparedPrintDocument, parent: NSWindow, output: URL) -> PrintLayoutSession {
        PrintLayoutSession(prepared: prepared, parentWindow: parent, action: .export(output, { _ in }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, error in XCTFail(error.localizedDescription) }, telemetry: { _, _ in })
    }

    private func descendants(of root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { descendants(of: $0) }
    }

    private func previewView(in parent: NSWindow) -> PDFView? {
        guard let root = parent.attachedSheet?.contentView else { return nil }
        return descendants(of: root).compactMap { $0 as? PDFView }.first
    }

    private func exportButton(in parent: NSWindow) -> NSButton? {
        guard let root = parent.attachedSheet?.contentView else { return nil }
        return descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == "Export PDF" }
    }

    private func previewIsReady(in parent: NSWindow) -> Bool {
        guard let root = parent.attachedSheet?.contentView else { return false }
        return descendants(of: root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("Preview ready —") }
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
