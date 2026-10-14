import AppKit
import Foundation
import PDFKit
import WebKit

@MainActor
final class PrintDocumentRenderer {
    enum RenderError: LocalizedError {
        case missingScript
        case loadFailed(Error)
        case pdfFailed
        case superseded
        case unavailablePrintOperation
        case footnoteLayoutFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingScript:
                return "The print layout script is missing from the app bundle."
            case .loadFailed(let error):
                return error.localizedDescription
            case .pdfFailed:
                return "The print preview could not be rendered as PDF."
            case .superseded:
                return "The print preview request was superseded by a newer update."
            case .unavailablePrintOperation:
                return "The system could not create a print operation for the prepared PDF."
            case .footnoteLayoutFailed(let message):
                return message
            }
        }
    }

    private let scriptProvider: () -> String
    private let profileLayout: Bool

    init(scriptProvider: @escaping () -> String = { PrintLayoutScriptLoader.load() ?? "" }, profileLayout: Bool = false) {
        self.scriptProvider = scriptProvider
        self.profileLayout = profileLayout
    }

    func prepareDocument(
        bodyHTML: String,
        title: String,
        baseURL: URL?,
        settings: PrintLayoutSettings,
        printInfo: NSPrintInfo = .shared,
        onPhase: (@MainActor (PrintPreviewPhase) -> Void)? = nil
    ) async throws -> PreparedPrintDocument {
        let script = scriptProvider()
        guard !script.isEmpty else { throw RenderError.missingScript }
        let normalized = settings.normalized
        try normalized.validate(for: printInfo.paperSize)
        let sizedPrintInfo = normalized.applying(to: printInfo)
        let document = PreparedPrintDocument(
            bodyHTML: bodyHTML,
            title: title,
            baseURL: baseURL,
            settings: normalized,
            script: (profileLayout ? "window.__ouroPrintProfiling = true;\n" : "") + script,
            printInfo: sizedPrintInfo
        )
        do {
            try await document.load(onPhase: onPhase)
            return document
        } catch {
            document.releaseHold()
            throw error
        }
    }

}

@MainActor
final class PreparedPrintDocument: NSObject, WKNavigationDelegate {
    private struct LayoutSignature: Equatable {
        let settings: PrintLayoutSettings
        let paperSize: NSSize
    }

    private static var inFlight: [ObjectIdentifier: PreparedPrintDocument] = [:]

    private let bodyHTML: String
    private let title: String
    private let baseURL: URL?
    private let script: String
    private(set) var settings: PrintLayoutSettings
    private(set) var printInfo: NSPrintInfo
    let webView: WKWebView
    private let hostWindow: NSWindow
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var currentNavigation: WKNavigation?
    private var loadGeneration = 0
    private var loadingSignature: LayoutSignature?
    private var loadedSignature: LayoutSignature?
    private var loadPhaseObserver: (@MainActor (PrintPreviewPhase) -> Void)?
    private(set) var layoutMetrics = PrintLayoutMetrics(
        contentWidth: 0,
        contentHeight: 0,
        pageGap: 0,
        pageStride: 0,
        totalWidth: 0,
        pageCount: 1,
        fragmentedProofIDs: [],
        links: []
    )

    init(
        bodyHTML: String,
        title: String,
        baseURL: URL?,
        settings: PrintLayoutSettings,
        script: String,
        printInfo: NSPrintInfo
    ) {
        self.bodyHTML = bodyHTML
        self.title = title
        self.baseURL = baseURL
        self.script = script
        self.settings = settings.normalized
        self.printInfo = printInfo
        let pageSize = Self.editorCanvasSize(for: self.settings, paperSize: printInfo.paperSize)
        self.webView = WKWebView(
            frame: NSRect(origin: .zero, size: pageSize),
            configuration: WKWebViewConfiguration()
        )
        self.hostWindow = HeadlessHostWindow(
            contentRect: NSRect(origin: .zero, size: pageSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        hostWindow.contentView = webView
        hostWindow.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        hostWindow.orderFront(nil)
    }

    func load(onPhase: (@MainActor (PrintPreviewPhase) -> Void)? = nil) async throws {
        retainHold()
        try await loadHTML(using: settings, onPhase: onPhase)
    }

    func reload(with updated: PrintLayoutSettings, onPhase: (@MainActor (PrintPreviewPhase) -> Void)? = nil) async throws {
        settings = updated.normalized
        try settings.validate(for: printInfo.paperSize)
        printInfo = settings.applying(to: printInfo)
        let canvasSize = Self.editorCanvasSize(for: settings, paperSize: printInfo.paperSize)
        webView.frame = NSRect(origin: .zero, size: canvasSize)
        hostWindow.setContentSize(canvasSize)
        try await loadHTML(using: settings, onPhase: onPhase)
    }

    func setPageSettings(_ selected: NSPrintInfo) {
        printInfo = settings.applying(to: selected)
    }

    func hasCurrentLayout(for requested: PrintLayoutSettings) -> Bool {
        loadContinuation == nil && currentNavigation == nil &&
            loadedSignature == LayoutSignature(settings: requested.normalized, paperSize: printInfo.paperSize)
    }

    func writePDF(to url: URL) async throws {
        let data = try await createPDFData()
        try data.write(to: url, options: .atomic)
    }

    func releaseHold() {
        hostWindow.orderOut(nil)
        Self.inFlight.removeValue(forKey: ObjectIdentifier(self))
    }

    private func retainHold() {
        Self.inFlight[ObjectIdentifier(self)] = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        let generation = loadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.finishLoadAfterLayout(navigation: navigation, generation: generation)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failLoad(navigation: navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failLoad(navigation: navigation, error: error)
    }

    private func failLoad(navigation: WKNavigation?, error: Error) {
        guard navigation == nil || navigation === currentNavigation else { return }
        if let continuation = loadContinuation {
            loadContinuation = nil
            currentNavigation = nil
            loadPhaseObserver = nil
            continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
        }
    }

    private func finishLoadAfterLayout(navigation: WKNavigation?, generation: Int) {
        guard let continuation = loadContinuation else { return }
        guard generation == loadGeneration, navigation === currentNavigation else { return }
        loadPhaseObserver?(.paginating)
        webView.evaluateJavaScript(
            "(function(){ if (!window.OuroPrintLayout || typeof window.OuroPrintLayout.apply !== 'function') { return null; } return window.OuroPrintLayout.apply(); })();"
        ) { [weak self] result, error in
            guard let self else { return }
            guard generation == self.loadGeneration, navigation === self.currentNavigation else { return }
            if let error {
                self.loadContinuation = nil
                self.currentNavigation = nil
                self.loadPhaseObserver = nil
                if let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String,
                   message.contains("Page footnote") {
                    continuation.resume(throwing: PrintDocumentRenderer.RenderError.footnoteLayoutFailed(message))
                } else {
                    continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
                }
                return
            }
            guard let metrics = Self.decodeMetrics(result) else {
                self.loadContinuation = nil
                self.currentNavigation = nil
                self.loadPhaseObserver = nil
                continuation.resume(throwing: PrintDocumentRenderer.RenderError.pdfFailed)
                return
            }
            self.layoutMetrics = metrics
            self.webView.frame = NSRect(
                x: 0,
                y: 0,
                width: printInfo.paperSize.width,
                height: printInfo.paperSize.height
            )
            self.hostWindow.setContentSize(self.webView.frame.size)
            self.loadedSignature = self.loadingSignature
            self.loadContinuation = nil
            self.currentNavigation = nil
            self.loadPhaseObserver = nil
            continuation.resume()
        }
    }

    func createPDFData(
        onPhase: (@MainActor (PrintPreviewPhase) -> Void)? = nil,
        onPage: (@MainActor (Int, Int, Data) throws -> Void)? = nil
    ) async throws -> Data {
        let generation = loadGeneration
        var pagePDFs: [Data] = []
        var pageLinks: [[PrintLayoutMetrics.Link]] = []
        onPhase?(.capturingPages(completed: 0, total: layoutMetrics.pageCount))
        for index in 0..<layoutMetrics.pageCount {
            try Task.checkCancellation()
            guard generation == loadGeneration else { throw PrintDocumentRenderer.RenderError.superseded }
            let metrics = try await activatePage(index)
            guard generation == loadGeneration else { throw PrintDocumentRenderer.RenderError.superseded }
            let snapshot = try await snapshotVisiblePagePDF()
            try Task.checkCancellation()
            guard generation == loadGeneration else { throw PrintDocumentRenderer.RenderError.superseded }
            pagePDFs.append(snapshot)
            pageLinks.append(metrics.links)
            onPhase?(.capturingPages(completed: index + 1, total: layoutMetrics.pageCount))
            try onPage?(index + 1, layoutMetrics.pageCount, snapshot)
        }
        onPhase?(.assemblingPDF)
        return try PrintPDFPaginator.paginate(
            sourcePages: pagePDFs,
            paperSize: printInfo.paperSize,
            margins: settings.margins,
            pageLinks: pageLinks
        )
    }

    func makePrintOperation(with pdf: PDFDocument) throws -> NSPrintOperation {
        guard let operation = pdf.printOperation(for: printInfo, scalingMode: .pageScaleNone, autoRotate: false) else {
            throw PrintDocumentRenderer.RenderError.unavailablePrintOperation
        }
        operation.printPanel.options.subtract([.showsPaperSize, .showsOrientation, .showsPageSetupAccessory])
        return operation
    }

    static var retainedCountForTesting: Int { inFlight.count }

    private func activatePage(_ index: Int) async throws -> PrintLayoutMetrics {
        let metrics = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PrintLayoutMetrics, Error>) in
            webView.evaluateJavaScript(
                "(function(){ return window.OuroPrintLayout && typeof window.OuroPrintLayout.showPage === 'function' ? window.OuroPrintLayout.showPage(\(index)) : null; })();"
            ) { result, error in
                if let error {
                    continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
                } else if let metrics = Self.decodeMetrics(result) {
                    continuation.resume(returning: metrics)
                } else {
                    continuation.resume(throwing: PrintDocumentRenderer.RenderError.pdfFailed)
                }
            }
        }
        return metrics
    }

    private func snapshotVisiblePagePDF() async throws -> Data {
        let configuration = WKPDFConfiguration()
        configuration.rect = webView.bounds
        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
                @unknown default:
                    continuation.resume(throwing: PrintDocumentRenderer.RenderError.pdfFailed)
                }
            }
        }
    }

    private func loadHTML(using settings: PrintLayoutSettings, onPhase: (@MainActor (PrintPreviewPhase) -> Void)?) async throws {
        let signature = LayoutSignature(settings: settings, paperSize: printInfo.paperSize)
        let html = PrintLayoutHTMLDocument.wrap(body: bodyHTML, title: title, settings: settings, script: script, paperSize: signature.paperSize)
        loadGeneration += 1
        loadingSignature = signature
        loadedSignature = nil
        let generation = loadGeneration
        if let continuation = loadContinuation {
            loadContinuation = nil
            currentNavigation = nil
            continuation.resume(throwing: PrintDocumentRenderer.RenderError.superseded)
        }
        loadPhaseObserver = onPhase
        onPhase?(.loadingHTML)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            currentNavigation = webView.loadHTMLString(html, baseURL: baseURL)
            guard generation == loadGeneration else {
                let leaked = continuation
                loadContinuation = nil
                currentNavigation = nil
                leaked.resume(throwing: PrintDocumentRenderer.RenderError.superseded)
                return
            }
        }
    }

    private static func editorCanvasSize(for settings: PrintLayoutSettings, paperSize: NSSize) -> NSSize {
        paperSize
    }

    private static func decodeMetrics(_ result: Any?) -> PrintLayoutMetrics? {
        guard let dictionary = result as? [String: Any],
              let contentWidth = dictionary["contentWidth"] as? NSNumber,
              let contentHeight = dictionary["contentHeight"] as? NSNumber,
              let pageGap = dictionary["pageGap"] as? NSNumber,
              let pageStride = dictionary["pageStride"] as? NSNumber,
              let totalWidth = dictionary["totalWidth"] as? NSNumber,
              let pageCount = dictionary["pageCount"] as? NSNumber else { return nil }
        let links = (dictionary["links"] as? [[String: Any]] ?? []).compactMap { link -> PrintLayoutMetrics.Link? in
            guard let x = link["x"] as? NSNumber,
                  let y = link["y"] as? NSNumber,
                  let width = link["width"] as? NSNumber,
                  let height = link["height"] as? NSNumber else { return nil }
            let destinationPageIndex = (link["destinationPageIndex"] as? NSNumber)?.intValue
            let destinationX = (link["destinationX"] as? NSNumber)?.doubleValue
            let destinationY = (link["destinationY"] as? NSNumber)?.doubleValue
            return PrintLayoutMetrics.Link(
                x: x.doubleValue,
                y: y.doubleValue,
                width: width.doubleValue,
                height: height.doubleValue,
                url: link["url"] as? String,
                destinationPageIndex: destinationPageIndex,
                destinationX: destinationX,
                destinationY: destinationY
            )
        }
        return PrintLayoutMetrics(
            contentWidth: contentWidth.doubleValue,
            contentHeight: contentHeight.doubleValue,
            pageGap: pageGap.doubleValue,
            pageStride: pageStride.doubleValue,
            totalWidth: totalWidth.doubleValue,
            pageCount: pageCount.intValue,
            fragmentedProofIDs: dictionary["fragmentedProofIDs"] as? [String] ?? [],
            links: links
        )
    }
}

enum PrintLayoutScriptLoader {
    static func load() -> String? {
        guard let url = OuroResources.web("print-layout", "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
