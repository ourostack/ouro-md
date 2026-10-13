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

        var errorDescription: String? {
            switch self {
            case .missingScript:
                return "The print layout script is missing from the app bundle."
            case .loadFailed(let error):
                return error.localizedDescription
            case .pdfFailed:
                return "The print preview could not be rendered as PDF."
            }
        }
    }

    private let scriptProvider: () -> String

    init(scriptProvider: @escaping () -> String = { PrintLayoutScriptLoader.load() ?? "" }) {
        self.scriptProvider = scriptProvider
    }

    func prepareDocument(
        bodyHTML: String,
        title: String,
        baseURL: URL?,
        settings: PrintLayoutSettings,
        printInfo: NSPrintInfo = .shared
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
            script: script,
            printInfo: sizedPrintInfo
        )
        try await document.load()
        return document
    }

}

@MainActor
final class PreparedPrintDocument: NSObject, WKNavigationDelegate {
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
    private(set) var layoutMetrics = PrintLayoutMetrics(
        contentWidth: 0,
        contentHeight: 0,
        pageGap: 0,
        pageStride: 0,
        totalWidth: 0,
        pageCount: 1,
        fragmentedProofIDs: [],
        endnoteLinks: []
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

    func load() async throws {
        retainHold()
        try await loadHTML(using: settings)
    }

    func reload(with updated: PrintLayoutSettings) async throws {
        settings = updated.normalized
        try settings.validate(for: printInfo.paperSize)
        printInfo = settings.applying(to: printInfo)
        let canvasSize = Self.editorCanvasSize(for: settings, paperSize: printInfo.paperSize)
        webView.frame = NSRect(origin: .zero, size: canvasSize)
        hostWindow.setContentSize(canvasSize)
        try await loadHTML(using: settings)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.finishLoadAfterLayout()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failLoad(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failLoad(error)
    }

    private func failLoad(_ error: Error) {
        if let continuation = loadContinuation {
            loadContinuation = nil
            continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
        }
    }

    private func finishLoadAfterLayout() {
        guard let continuation = loadContinuation else { return }
        webView.evaluateJavaScript(
            "(function(){ if (!window.OuroPrintLayout || typeof window.OuroPrintLayout.apply !== 'function') { return null; } return window.OuroPrintLayout.apply(); })();"
        ) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.loadContinuation = nil
                continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
                return
            }
            guard let metrics = Self.decodeMetrics(result) else {
                self.loadContinuation = nil
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
            self.loadContinuation = nil
            continuation.resume()
        }
    }

    func createPDFData() async throws -> Data {
        var pagePDFs: [Data] = []
        for index in 0..<layoutMetrics.pageCount {
            try await activatePage(index)
            pagePDFs.append(try await snapshotVisiblePagePDF())
        }
        return try PrintPDFPaginator.paginate(
            sourcePages: pagePDFs,
            paperSize: printInfo.paperSize,
            margins: settings.margins,
            metrics: layoutMetrics
        )
    }

    func makePrintOperation(with pdf: PDFDocument) -> NSPrintOperation {
        pdf.printOperation(for: printInfo, scalingMode: .pageScaleNone, autoRotate: false)
            ?? NSPrintOperation(view: NSView(), printInfo: printInfo)
    }

    static var retainedCountForTesting: Int { inFlight.count }

    private func activatePage(_ index: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(
                "(function(){ return window.OuroPrintLayout && typeof window.OuroPrintLayout.showPage === 'function' ? window.OuroPrintLayout.showPage(\(index)) : null; })();"
            ) { _, error in
                if let error {
                    continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
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

    private func loadHTML(using settings: PrintLayoutSettings) async throws {
        let html = PrintLayoutHTMLDocument.wrap(body: bodyHTML, title: title, settings: settings, script: script)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
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
        let links = (dictionary["endnoteLinks"] as? [[String: Any]] ?? []).compactMap { link -> PrintLayoutMetrics.EndnoteLink? in
            guard let url = link["url"] as? String,
                  let pageIndex = link["pageIndex"] as? NSNumber,
                  let x = link["x"] as? NSNumber,
                  let y = link["y"] as? NSNumber,
                  let width = link["width"] as? NSNumber,
                  let height = link["height"] as? NSNumber else { return nil }
            return PrintLayoutMetrics.EndnoteLink(
                url: url,
                pageIndex: pageIndex.intValue,
                x: x.doubleValue,
                y: y.doubleValue,
                width: width.doubleValue,
                height: height.doubleValue
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
            endnoteLinks: links
        )
    }
}

enum PrintLayoutScriptLoader {
    static func load() -> String? {
        guard let url = OuroResources.web("print-layout", "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
