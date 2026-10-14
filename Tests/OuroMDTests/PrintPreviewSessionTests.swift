import AppKit
import PDFKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintPreviewSessionTests: XCTestCase {
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

    func testSubmittingDuringPreviewPreparationQueuesCompleteOutputWithTheFinalFieldEdit() async throws {
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
        let expectedFont = try XCTUnwrap(NSFont(name: "Georgia", size: 10))
        let expectedWidth = (token as NSString).size(withAttributes: [.font: expectedFont]).width
        XCTAssertEqual(selection.bounds(for: finalPage).width, expectedWidth, accuracy: 1, "The final physical text size must match the newly entered 10 pt value")
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
