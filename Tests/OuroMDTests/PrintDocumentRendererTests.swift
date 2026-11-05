import AppKit
import PDFKit
import WebKit
import XCTest
@testable import OuroMD

@MainActor
private final class DelayedPrintImageHandler: NSObject, WKURLSchemeHandler {
    private var stopped = Set<ObjectIdentifier>()
    private(set) var finished = false
    let delay: UInt64

    init(delay: UInt64) { self.delay = delay }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        Task { @MainActor in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !stopped.contains(id), let url = urlSchemeTask.request.url else { return }
            let data = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\"><rect width=\"64\" height=\"64\" fill=\"#0000ff\"/></svg>".utf8)
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "image/svg+xml", expectedContentLength: data.count, textEncodingName: "utf-8"))
            urlSchemeTask.didReceive(data)
            finished = true
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(urlSchemeTask))
    }
}

@MainActor
final class PrintDocumentRendererTests: XCTestCase {
    func testPreparationProfileIsOptInAndContainsOnlyFixedTimingCodes() async throws {
        for profiling in [false, true] {
            let prepared = try await PrintDocumentRenderer(profileLayout: profiling).prepareDocument(bodyHTML: "<p>PRIVATE-PROFILE-CONTENT</p>", title: "PRIVATE-PROFILE-TITLE", baseURL: nil, settings: .default)
            defer { prepared.releaseHold() }
            let expected: Set<String> = profiling ? ["surface_construction", "html_wrap", "html_submit"] : []
            XCTAssertEqual(Set(prepared.preparationProfile.keys), expected)
            XCTAssertTrue(prepared.preparationProfile.values.allSatisfy { $0.isFinite && $0 >= 0 })
        }
    }

    func testPreparationWaitsForActualImageResourceAndPreservesItsPaint() async throws {
        try await verifyImageResource(delay: 400_000_000, rejectingDecode: false)
    }

    func testRejectingDecodeDoesNotPreventAnAlreadyLoadedImageFromPrinting() async throws {
        try await verifyImageResource(delay: 0, rejectingDecode: true)
    }

    private func verifyImageResource(delay: UInt64, rejectingDecode: Bool) async throws {
        let handler = DelayedPrintImageHandler(delay: delay)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "print-fixture")
        let script = try XCTUnwrap(PrintLayoutScriptLoader.load()) + (rejectingDecode ? ";HTMLImageElement.prototype.decode=function(){return Promise.reject(new Error('Synthetic decode rejection'));};" : "")
        let prepared = try await PrintDocumentRenderer(scriptProvider: { script }, webViewConfiguration: configuration).prepareDocument(bodyHTML: "<img width=\"64\" height=\"64\" src=\"print-fixture://image/blue.svg\" alt=\"Blue print fixture\">", title: "Image readiness", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        XCTAssertTrue(handler.finished, "WebKit navigation must finish loading image resources before pagination.")
        let geometry = try await prepared.webView.evaluateJavaScript("Array.from(document.images).map(image=>[image.complete,image.naturalWidth,image.naturalHeight,image.getBoundingClientRect().width,image.getBoundingClientRect().height])")
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let image = try XCTUnwrap(pdf.page(at: 0)?.thumbnail(of: NSSize(width: 150, height: 200), for: .mediaBox))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
        var bluePixels = 0
        var peakBlueDominance = 0.0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    peakBlueDominance = max(peakBlueDominance, color.blueComponent - max(color.redComponent, color.greenComponent))
                    if color.blueComponent - max(color.redComponent, color.greenComponent) > 0.5 { bluePixels += 1 }
                }
            }
        }
        XCTAssertGreaterThan(bluePixels, 100, "A ready PDF must contain the loaded image's blue ink, not only an empty image box. Geometry: \(String(describing: geometry)); peak blue dominance: \(peakBlueDominance); bitmap \(bitmap.pixelsWide)x\(bitmap.pixelsHigh).")
    }

    func testWebContentTerminationResolvesPendingLoadAndAllowsRetry() async throws {
        let prepared = PreparedPrintDocument(bodyHTML: "<p>Retry terminated load</p>", title: "Termination", baseURL: nil, settings: .default, script: try XCTUnwrap(PrintLayoutScriptLoader.load()), printInfo: NSPrintInfo())
        defer { prepared.releaseHold() }
        let loading = Task { try await prepared.load() }
        await Task.yield()
        prepared.webViewWebContentProcessDidTerminate(prepared.webView)
        do {
            try await loading.value
            XCTFail("Termination must resolve the pending load with an explicit error.")
        } catch {
            guard case PrintDocumentRenderer.RenderError.webContentTerminated = error else { return XCTFail("Unexpected termination error: \(error)") }
        }
        try await prepared.reload(with: .default)
        XCTAssertTrue(prepared.hasCurrentLayout(for: .default))
    }

    func testWebContentTerminationResolvesPendingCapture() async throws {
        var settings = PrintLayoutSettings.default
        settings.headingBreakLevel = 2
        let body = (1...100).map { "<h2>Section \($0)</h2><p>Terminate capture</p>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Capture termination", baseURL: nil, settings: settings)
        defer { prepared.releaseHold() }
        let capturing = Task { try await prepared.createPDFData() }
        for _ in 0..<1000 {
            if prepared.pendingWebOperationCountForTesting > 0 { break }
            await Task.yield()
        }
        XCTAssertGreaterThan(prepared.pendingWebOperationCountForTesting, 0)
        prepared.webViewWebContentProcessDidTerminate(prepared.webView)
        do {
            _ = try await capturing.value
            XCTFail("Termination must resolve a pending capture, not leave its task suspended.")
        } catch {
            guard case PrintDocumentRenderer.RenderError.webContentTerminated = error else { return XCTFail("Unexpected capture termination error: \(error)") }
        }
        XCTAssertEqual(prepared.pendingWebOperationCountForTesting, 0)
    }

    func testPreparationWaitsForActualFontReadinessInsteadOfAFixedSettlingDelay() async throws {
        let script = try XCTUnwrap(PrintLayoutScriptLoader.load()) + """
        ;Object.defineProperty(document.fonts,'ready',{get:function(){return new Promise(function(resolve){setTimeout(function(){window.__ouroFontsReadyForTest=true;resolve();},600);});}});
        """
        let prepared = try await PrintDocumentRenderer(scriptProvider: { script }).prepareDocument(bodyHTML: "<p>Wait for font readiness</p>", title: "Font readiness", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let ready = try await prepared.webView.evaluateJavaScript("window.__ouroFontsReadyForTest === true") as? Bool
        XCTAssertEqual(ready, true, "Pagination must await real font readiness, not an arbitrary settling sleep.")
    }

    func testOrientationAloneInvalidatesTheCachedLayout() async throws {
        let info = NSPrintInfo()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Orientation identity</p>", title: "Orientation", baseURL: nil, settings: .default, printInfo: info)
        defer { prepared.releaseHold() }
        XCTAssertTrue(prepared.hasCurrentLayout(for: .default))
        let selected = try XCTUnwrap(info.copy() as? NSPrintInfo)
        selected.orientation = info.orientation == .portrait ? .landscape : .portrait
        selected.paperSize = info.paperSize
        prepared.setPageSettings(selected)
        XCTAssertFalse(prepared.hasCurrentLayout(for: .default))
        try await prepared.reload(with: .default)
        XCTAssertTrue(prepared.hasCurrentLayout(for: .default))
    }

    func testCancellationDuringWebKitLoadResolvesAndRetiresExactlyOnce() async throws {
        let originalHolds = PreparedPrintDocument.retainedCountForTesting
        let prepared = PreparedPrintDocument(bodyHTML: "<p>Cancelled load</p>", title: "Cancel load", baseURL: nil, settings: .default, script: try XCTUnwrap(PrintLayoutScriptLoader.load()), printInfo: NSPrintInfo())
        let task = Task { try await prepared.load() }
        await Task.yield()
        prepared.cancelLoading()
        do {
            try await task.value
            XCTFail("A cancelled loading continuation must not return a prepared layout.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        prepared.releaseHold()
        prepared.releaseHold()
        XCTAssertEqual(PreparedPrintDocument.retainedCountForTesting, originalHolds)
        XCTAssertNil(prepared.webView.window)
    }

    func testPreparationReportsLoadThenPagination() async throws {
        var phases: [PrintPreviewPhase] = []
        let prepared = try await PrintDocumentRenderer().prepareDocument(
            bodyHTML: "<p>Observe real preparation.</p>",
            title: "Preparation phases",
            baseURL: nil,
            settings: .default,
            onPhase: { phases.append($0) }
        )
        defer { prepared.releaseHold() }
        XCTAssertEqual(phases, [.loadingHTML, .paginating])
        XCTAssertGreaterThan(prepared.layoutMetrics.contentWidth, 0)
        XCTAssertGreaterThan(prepared.layoutMetrics.pageCount, 0)
    }

    func testCaptureReportsAssemblyBeforeReturningCompletePDF() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let prepared = try await PrintDocumentRenderer().prepareDocument(
            bodyHTML: "<h2>First</h2><p>FIRST-PHASE-TOKEN</p><h2>Second</h2><p>SECOND-PHASE-TOKEN</p>",
            title: "Capture phases",
            baseURL: nil,
            settings: settings
        )
        defer { prepared.releaseHold() }
        var phases: [PrintPreviewPhase] = []
        let data = try await prepared.createPDFData(onPhase: { phases.append($0) })
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(phases, [
            .capturingPages(completed: 0, total: 2),
            .capturingPages(completed: 1, total: 2),
            .capturingPages(completed: 2, total: 2),
            .assemblingPDF
        ])
        XCTAssertFalse(phases.contains(.ready), "Only the session can seal the current preview and declare it ready.")
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("FIRST-PHASE-TOKEN") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("SECOND-PHASE-TOKEN") == true)
    }

    func testOptionalPhaseObservationDoesNotChangeCompleteOutput() async throws {
        let body = "<h2>Complete output</h2><p>OBSERVED-PHASE-TOKEN <a href=\"https://example.com/phase-source\">source</a></p>"
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Optional observer", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let plainData = try await prepared.createPDFData()
        let plain = try XCTUnwrap(PDFDocument(data: plainData))
        var phases: [PrintPreviewPhase] = []
        let observedData = try await prepared.createPDFData(onPhase: { phases.append($0) })
        let observed = try XCTUnwrap(PDFDocument(data: observedData))
        XCTAssertEqual(plain.pageCount, observed.pageCount)
        XCTAssertEqual(plain.string, observed.string)
        XCTAssertTrue(observed.string?.contains("OBSERVED-PHASE-TOKEN") == true)
        for index in 0..<plain.pageCount {
            XCTAssertEqual(plain.page(at: index)?.bounds(for: .mediaBox), observed.page(at: index)?.bounds(for: .mediaBox))
            XCTAssertEqual(plain.page(at: index)?.annotations.compactMap(\.url), observed.page(at: index)?.annotations.compactMap(\.url))
        }
        XCTAssertEqual(phases.last, .assemblingPDF)
    }

    func testEndnotesIncludeLocalAndRelativeCitationTargets() async throws {
        let body = "<p>Sources: <a href=\"https://example.com/source\">Web source</a>, <a href=\"file:///tmp/local-source.md\">Local source</a>, <a href=\"relative-source.md\">Relative source</a>.</p>"
        var settings = PrintLayoutSettings.default
        settings.includeExternalLinkReferences = true
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Source references", baseURL: URL(fileURLWithPath: "/tmp/citation-fixture/", isDirectory: true), settings: settings)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(text.contains("https://example.com/source"))
        XCTAssertTrue(text.contains("file:///tmp/local-source.md"))
        XCTAssertTrue(text.contains("file:///tmp/citation-fixture/relative-source.md"))
    }

    func testA4PaperFlowsThroughLayoutAndPDFGeometry() async throws {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h1>A4 proof</h1><p>Paper-aware layout</p>", title: "A4", baseURL: nil, settings: .default, printInfo: info)
        defer { prepared.releaseHold() }
        XCTAssertEqual(prepared.layoutMetrics.contentWidth, 487, accuracy: 1)
        XCTAssertEqual(prepared.layoutMetrics.contentHeight, 734, accuracy: 1)
        let data = try await prepared.createPDFData()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 595, accuracy: 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 842, accuracy: 1)
    }

    func testPageSetupRepaginatesBeforeFixedNativePrintOperation() async throws {
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h1>Page setup proof</h1><p>Selected paper controls output.</p>", title: "Page setup", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let selected = NSPrintInfo()
        selected.paperSize = NSSize(width: 595, height: 842)
        selected.orientation = .landscape
        prepared.setPageSettings(selected)
        try await prepared.reload(with: .default)
        let data = try await prepared.createPDFData()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, selected.paperSize.width, accuracy: 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, selected.paperSize.height, accuracy: 1)
        let operation = try prepared.makePrintOperation(with: document)
        XCTAssertFalse(operation.printPanel.options.contains(.showsPaperSize))
        XCTAssertFalse(operation.printPanel.options.contains(.showsOrientation))
        XCTAssertFalse(operation.printPanel.options.contains(.showsPageSetupAccessory))
    }

    func testRenderedPDFUsesPagedLayoutPreservesWholeRowsAndClickableEndnotes() async throws {
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "print-renderer")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let renderer = PrintDocumentRenderer(scriptProvider: { PrintLayoutScriptLoader.load() ?? "" })
        let prepared = try await renderer.prepareDocument(
            bodyHTML: Self.syntheticBodyHTML,
            title: "print-proof.pdf",
            baseURL: scratch,
            settings: PrintLayoutSettings(
                margins: PrintLayoutSettings.default.margins,
                fontSize: PrintLayoutSettings.default.fontSize,
                lineSpacing: PrintLayoutSettings.default.lineSpacing,
                includeExternalLinkReferences: true
            )
        )
        defer { prepared.releaseHold() }

        let pdf = try await prepared.createPDFData()
        guard let document = PDFDocument(data: pdf) else {
            return XCTFail("Expected a readable PDF document")
        }

        XCTAssertGreaterThan(document.pageCount, 2)
        let pageStrings = (0..<document.pageCount).compactMap { document.page(at: $0)?.string ?? "" }
        XCTAssertEqual(pageStrings.count, document.pageCount)
        XCTAssertTrue(pageStrings.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertEqual(try XCTUnwrap(Self.fontSize(of: "Overview with", in: document.page(at: 0))), 12, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(Self.fontSize(of: "Printable proof", in: document.page(at: 0))), 24, accuracy: 0.75)
        XCTAssertEqual(try XCTUnwrap(Self.bounds(of: "Printable proof", in: document.page(at: 0))).minX, 54, accuracy: 0.75)
        XCTAssertEqual(prepared.layoutMetrics.fragmentedProofIDs, [])

        let annotationURLs = Set((0..<document.pageCount).flatMap { index in
            document.page(at: index)?.annotations.compactMap { $0.url?.absoluteString } ?? []
        })
        XCTAssertTrue(annotationURLs.contains("https://example.com/repeated?query=1&value=2"))
        XCTAssertTrue(annotationURLs.contains("https://example.com/code-link"))
        XCTAssertTrue(annotationURLs.contains("https://example.com/image-only"))
        let fullText = pageStrings.joined(separator: "\n")
        XCTAssertTrue(fullText.contains("https://example.com/image-only"))
        XCTAssertTrue(fullText.contains("x"))
        XCTAssertTrue(fullText.contains("y + z"))
        XCTAssertTrue(fullText.contains("Rendered diagram"))

        try Self.writeEvidenceIfRequested(
            pdf: pdf,
            document: document,
            controlsSettings: prepared.settings,
            reportLines: [
                "pageCount=\(document.pageCount)",
                "annotationURLs=\(annotationURLs.sorted().joined(separator: ","))",
                "fragmentedProofIDs=\(prepared.layoutMetrics.fragmentedProofIDs.joined(separator: ","))"
            ]
        )
    }

    func testRenderedPDFAppliesExplicitSettingsToLayoutGeometry() async throws {
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "print-geometry")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let renderer = PrintDocumentRenderer(scriptProvider: { PrintLayoutScriptLoader.load() ?? "" })

        let compact = try await renderer.prepareDocument(
            bodyHTML: Self.syntheticBodyHTML,
            title: "compact.pdf",
            baseURL: scratch,
            settings: PrintLayoutSettings.default
        )
        let spacious = try await renderer.prepareDocument(
            bodyHTML: Self.syntheticBodyHTML,
            title: "spacious.pdf",
            baseURL: scratch,
            settings: PrintLayoutSettings(
                margins: PrintPageMargins(top: 72, right: 72, bottom: 72, left: 96),
                fontSize: 16,
                lineSpacing: 2,
                includeExternalLinkReferences: true
            )
        )
        defer {
            compact.releaseHold()
            spacious.releaseHold()
        }

        let compactData = try await compact.createPDFData()
        let spaciousData = try await spacious.createPDFData()
        let compactDocument = try XCTUnwrap(PDFDocument(data: compactData))
        let spaciousDocument = try XCTUnwrap(PDFDocument(data: spaciousData))
        let compactTitleBounds = try XCTUnwrap(Self.bounds(of: "Printable proof", in: compactDocument.page(at: 0)))
        let spaciousTitleBounds = try XCTUnwrap(Self.bounds(of: "Printable proof", in: spaciousDocument.page(at: 0)))
        let spaciousBodyFont = try XCTUnwrap(Self.fontSize(of: "Overview with", in: spaciousDocument.page(at: 0)))
        let spaciousHeadingFont = try XCTUnwrap(Self.fontSize(of: "Printable proof", in: spaciousDocument.page(at: 0)))

        XCTAssertGreaterThan(spaciousTitleBounds.minX, compactTitleBounds.minX)
        XCTAssertEqual(spaciousTitleBounds.minX, 96, accuracy: 1.0)
        XCTAssertEqual(spaciousBodyFont, 16, accuracy: 0.75)
        XCTAssertEqual(spaciousHeadingFont, 32, accuracy: 0.75)
        XCTAssertGreaterThan(spaciousDocument.pageCount, compactDocument.pageCount)
    }

    func testPreparedDocumentRetainsItselfUntilReleased() async throws {
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "print-retain")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let renderer = PrintDocumentRenderer(scriptProvider: { PrintLayoutScriptLoader.load() ?? "" })
        weak var weakPrepared: PreparedPrintDocument?

        do {
            let prepared = try await renderer.prepareDocument(
                bodyHTML: Self.syntheticBodyHTML,
                title: "retain.pdf",
                baseURL: scratch,
                settings: .default
            )
            weakPrepared = prepared
            XCTAssertEqual(PreparedPrintDocument.retainedCountForTesting, 1)
        }

        XCTAssertNotNil(weakPrepared)
        weakPrepared?.releaseHold()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(weakPrepared)
        XCTAssertEqual(PreparedPrintDocument.retainedCountForTesting, 0)
    }

    func testRenderedPDFPreservesAuthoredLinksWhenReferencesAreOff() async throws {
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "print-links-off")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let renderer = PrintDocumentRenderer(scriptProvider: { PrintLayoutScriptLoader.load() ?? "" })
        let prepared = try await renderer.prepareDocument(
            bodyHTML: Self.syntheticBodyHTML,
            title: "links-off.pdf",
            baseURL: scratch,
            settings: PrintLayoutSettings(
                margins: .init(top: 54, right: 54, bottom: 54, left: 54),
                fontSize: 12,
                lineSpacing: 1.45,
                includeExternalLinkReferences: false
            )
        )
        defer { prepared.releaseHold() }
        let pdf = try await prepared.createPDFData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let annotationURLs = Set((0..<document.pageCount).flatMap { index in
            document.page(at: index)?.annotations.compactMap { $0.url?.absoluteString } ?? []
        })
        XCTAssertTrue(annotationURLs.contains("https://example.com/repeated?query=1&value=2"))
        XCTAssertTrue(annotationURLs.contains("https://example.com/code-link"))
        XCTAssertTrue(annotationURLs.contains("https://example.com/image-only"))
        XCTAssertTrue(Self.containsInternalLink(in: document))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string ?? "" }.joined(separator: "\n")
        XCTAssertFalse(text.contains("Link sources (endnotes)"))
    }

    func testRenderedPDFPreservesAuthoredAndGeneratedLinksWhenReferencesAreOn() async throws {
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "print-links-on")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let renderer = PrintDocumentRenderer(scriptProvider: { PrintLayoutScriptLoader.load() ?? "" })
        let prepared = try await renderer.prepareDocument(
            bodyHTML: Self.syntheticBodyHTML,
            title: "links-on.pdf",
            baseURL: scratch,
            settings: PrintLayoutSettings(
                margins: .init(top: 54, right: 54, bottom: 54, left: 54),
                fontSize: 12,
                lineSpacing: 1.45,
                includeExternalLinkReferences: true
            )
        )
        defer { prepared.releaseHold() }
        let pdf = try await prepared.createPDFData()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let annotationURLs = Set((0..<document.pageCount).flatMap { index in
            document.page(at: index)?.annotations.compactMap { $0.url?.absoluteString } ?? []
        })
        XCTAssertTrue(annotationURLs.contains("https://example.com/repeated?query=1&value=2"))
        XCTAssertTrue(annotationURLs.contains("https://example.com/code-link"))
        XCTAssertTrue(annotationURLs.contains("https://example.com/image-only"))
        XCTAssertTrue(Self.containsInternalLink(in: document))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string ?? "" }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Link sources (endnotes)"))
    }

    private static func bounds(of needle: String, in page: PDFPage?) -> CGRect? {
        guard let page, let text = page.string, let range = text.range(of: needle) else { return nil }
        let nsRange = NSRange(range, in: text)
        return page.selection(for: nsRange)?.bounds(for: page)
    }

    private static func fontSize(of needle: String, in page: PDFPage?) -> Double? {
        guard let page,
              let attributed = page.attributedString,
              let text = page.string,
              let range = text.range(of: needle) else { return nil }
        let nsRange = NSRange(range, in: text)
        let attributes = attributed.attributes(at: nsRange.location, effectiveRange: nil)
        return (attributes[.font] as? NSFont).map { Double($0.pointSize) }
    }

    private static func containsInternalLink(in document: PDFDocument) -> Bool {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if let destinationPage = annotation.destination?.page,
                   document.index(for: destinationPage) != NSNotFound {
                    return true
                }
            }
        }
        return false
    }

    private static func writeEvidenceIfRequested(
        pdf: Data,
        document: PDFDocument,
        controlsSettings: PrintLayoutSettings,
        reportLines: [String]
    ) throws {
        let env = ProcessInfo.processInfo.environment
        guard let requestedDirectory = env["OURO_PRINT_EVIDENCE_DIR"], !requestedDirectory.isEmpty else { return }
        let evidenceDirectory = URL(fileURLWithPath: requestedDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try atomicWrite(pdf, to: evidenceDirectory.appendingPathComponent("print-layout-proof.pdf"))
        try writePageImage(pageAt: 0, name: "print-layout-proof-page-1.png", from: document, into: evidenceDirectory)
        try writePageImage(pageAt: max(0, document.pageCount / 2), name: "print-layout-proof-page-middle.png", from: document, into: evidenceDirectory)
        try writePageImage(pageAt: max(0, document.pageCount - 1), name: "print-layout-proof-page-last.png", from: document, into: evidenceDirectory)
        try writeControlsSnapshot(settings: controlsSettings, to: evidenceDirectory.appendingPathComponent("print-layout-controls.png"))
        try atomicWrite(
            Data(reportLines.joined(separator: "\n").utf8),
            to: evidenceDirectory.appendingPathComponent("print-layout-report.txt")
        )
    }

    private static func writePageImage(pageAt index: Int, name: String, from document: PDFDocument, into directory: URL) throws {
        guard let page = document.page(at: index) else { return }
        let image = page.thumbnail(of: NSSize(width: 900, height: 1165), for: .mediaBox)
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try atomicWrite(png, to: directory.appendingPathComponent(name))
        }
    }

    private static func writeControlsSnapshot(settings: PrintLayoutSettings, to url: URL) throws {
        let controller = PrintLayoutAccessoryController(
            settings: settings,
            settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore())
        )
        controller.loadViewIfNeeded()
        let view = controller.view
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 260)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try atomicWrite(png, to: url)
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let temporary = url.deletingPathExtension().appendingPathExtension(url.pathExtension + ".next")
        try data.write(to: temporary, options: .atomic)
        _ = try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    private static let syntheticBodyHTML = {
        let validImage = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0ioAAAAASUVORK5CYII="
        let lead = "<p id=\"overview\">Overview with <a href=\"https://example.com/repeated?query=1&amp;value=2\">an external reference</a>, <a href=\"#overview\">an internal anchor</a>, <a href=\"https://example.com/code-link\"><code>file.swift</code></a>, and <a href=\"https://example.com/image-only\"><img alt=\"Diagram\" src=\"data:image/png;base64,\(validImage)\"></a>.</p>"
        let rich = "<p>Inline math <span class=\"katex\"><span class=\"katex-html\" aria-hidden=\"true\"><span class=\"base\"><span class=\"mord\">x</span><span class=\"mspace\"> </span><span class=\"mrel\">=</span><span class=\"mspace\"> </span><span class=\"mord\">y + z</span></span></span></span>, <span>Rendered diagram</span> <svg width=\"120\" height=\"36\" viewBox=\"0 0 120 36\" xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"2\" y=\"2\" width=\"116\" height=\"32\" rx=\"6\" fill=\"#e8f0fe\" stroke=\"#1a73e8\" stroke-width=\"2\"/><text x=\"60\" y=\"23\" text-anchor=\"middle\" font-size=\"14\" fill=\"#0b57d0\">diagram</text></svg>, and an inline local image <img alt=\"Synthetic local image\" width=\"18\" height=\"18\" src=\"data:image/png;base64,\(validImage)\"></p>"
        let prose = "<p>This paragraph keeps page flow honest by carrying enough text to cross multiple lines without forcing unreadable overflow or clipping in the printed layout.</p>"
        let tables = (1...24).map { row in
            "<div data-proof-id=\"row-\(row)\"><table><thead><tr><th>Column</th><th>Notes</th></tr></thead><tbody><tr><td>ROW-\(row)-BEGIN</td><td>This table must stay together on one page with enough content to wrap naturally across several lines in the cell while preserving ROW-\(row)-END as part of the same table block. <a href=\"https://example.com/repeated?query=1&amp;value=2\">Repeated destination</a>.</td></tr></tbody></table></div>"
        }.joined(separator: prose)
        let footnote = "<section class=\"footnotes\"><hr><ol><li id=\"fn-note\">Author footnote text stays in place. <a href=\"#fnref-note\" class=\"footnote-backref\">↩</a></li></ol></section>"
        return ["<h1>Printable proof</h1>", lead, rich, prose, tables, footnote].joined(separator: "\n")
    }()
}
