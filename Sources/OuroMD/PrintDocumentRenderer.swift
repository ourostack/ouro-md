import AppKit
import Foundation
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
    private static var inFlight: Set<ObjectIdentifier> = []

    private let bodyHTML: String
    private let title: String
    private let baseURL: URL?
    private let script: String
    private(set) var settings: PrintLayoutSettings
    private(set) var printInfo: NSPrintInfo
    let webView: WKWebView
    private let hostWindow: NSWindow
    private var loadContinuation: CheckedContinuation<Void, Error>?

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
        let html = PrintLayoutHTMLDocument.wrap(body: bodyHTML, title: title, settings: settings, script: script)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func reload(with updated: PrintLayoutSettings) {
        settings = updated.normalized
        printInfo = settings.applying(to: printInfo)
        let canvasSize = Self.editorCanvasSize(for: settings, paperSize: printInfo.paperSize)
        webView.frame = NSRect(origin: .zero, size: canvasSize)
        hostWindow.setContentSize(canvasSize)
        let html = PrintLayoutHTMLDocument.wrap(body: bodyHTML, title: title, settings: settings, script: script)
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func writePDF(to url: URL) async throws {
        let data = try await createPDFData()
        try data.write(to: url, options: .atomic)
    }

    func makePrintOperation() -> NSPrintOperation {
        let operation = webView.printOperation(with: printInfo)
        operation.view?.frame = webView.bounds
        return operation
    }

    func releaseHold() {
        hostWindow.orderOut(nil)
        Self.inFlight.remove(ObjectIdentifier(self))
    }

    private func retainHold() {
        Self.inFlight.insert(ObjectIdentifier(self))
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
            "(function(){ if (window.OuroPrintLayout && typeof window.OuroPrintLayout.apply === 'function') { window.OuroPrintLayout.apply(); } var article = document.querySelector('.markdown-body'); return Math.max(document.documentElement.scrollHeight || 0, document.body.scrollHeight || 0, article ? article.scrollHeight : 0); })();"
        ) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.loadContinuation = nil
                continuation.resume(throwing: PrintDocumentRenderer.RenderError.loadFailed(error))
                return
            }
            let measuredHeight = (result as? NSNumber)?.doubleValue ?? Double(self.printInfo.paperSize.height)
            let height = max(self.webView.frame.height, CGFloat(measuredHeight))
            self.webView.frame = NSRect(
                x: 0,
                y: 0,
                width: self.webView.frame.width,
                height: height
            )
            self.hostWindow.setContentSize(self.webView.frame.size)
            self.loadContinuation = nil
            continuation.resume()
        }
    }

    func createPDFData() async throws -> Data {
        let source = try await snapshotSourcePDF()
        return try PrintPDFPaginator.paginate(
            sourcePDF: source,
            paperSize: printInfo.paperSize,
            margins: settings.margins
        )
    }

    private func snapshotSourcePDF() async throws -> Data {
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

    private static func editorCanvasSize(for settings: PrintLayoutSettings, paperSize: NSSize) -> NSSize {
        let margins = settings.normalized.margins
        return NSSize(
            width: max(72, paperSize.width - margins.left - margins.right),
            height: max(72, paperSize.height - margins.top - margins.bottom)
        )
    }
}

enum PrintLayoutScriptLoader {
    static func load() -> String? {
        guard let url = OuroResources.web("print-layout", "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
