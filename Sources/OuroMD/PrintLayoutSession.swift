import AppKit
import Foundation
import PDFKit
import WebKit

@MainActor
final class PrintLayoutSession: NSObject, NSWindowDelegate {
    enum SessionError: LocalizedError {
        case cancelled
        case unavailable(String)
        case missingPreview

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "The print layout was cancelled."
            case .unavailable(let message):
                return message
            case .missingPreview:
                return "The print preview is not ready yet."
            }
        }
    }

    enum Action {
        case print
        case export(URL, (Result<Bool, Error>) -> Void)
    }

    private static var active: [ObjectIdentifier: PrintLayoutSession] = [:]

    let prepared: PreparedPrintDocument
    private let parentWindow: NSWindow
    private let action: Action
    private let reportError: (String, Error) -> Void
    private let telemetry: (String, [String: OuroMDTelemetryValue]) -> Void
    private let pageSetupChooser: @MainActor (NSPrintInfo) -> Bool
    private let printPanelChooser: @MainActor (NSPrintInfo) -> Bool
    private let controls: PrintLayoutAccessoryController
    private let panel: NSPanel
    private let previewView = PDFView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let previousPageButton = NSButton(title: "Previous", target: nil, action: nil)
    private let nextPageButton = NSButton(title: "Next", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    private let zoomOutButton = NSButton(title: "Zoom out", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "Zoom in", target: nil, action: nil)
    private let fitPageButton = NSButton(title: "Fit page", target: nil, action: nil)
    private var pageChangeObserver: NSObjectProtocol?
    private var previewTask: Task<Void, Never>?
    private var currentPreviewData: Data?
    private var currentPreviewSettings: PrintLayoutSettings?
    private var submitWhenPreviewReady = false
    private var completionDelivered = false
    private var sessionFinished = false
    private var printOperationRunning = false
    private var outputTask: Task<Void, Never>?
    private var parentCloseObserver: NSObjectProtocol?

    init(
        prepared: PreparedPrintDocument,
        parentWindow: NSWindow,
        action: Action,
        settingsStore: PrintLayoutSettingsStore,
        pageSetupChooser: @escaping @MainActor (NSPrintInfo) -> Bool = { NSPageLayout().runModal(with: $0) == NSApplication.ModalResponse.OK.rawValue },
        printPanelChooser: @escaping @MainActor (NSPrintInfo) -> Bool = { NSPrintPanel().runModal(with: $0) == NSApplication.ModalResponse.OK.rawValue },
        reportError: @escaping (String, Error) -> Void,
        telemetry: @escaping (String, [String: OuroMDTelemetryValue]) -> Void
    ) {
        self.prepared = prepared
        self.parentWindow = parentWindow
        self.action = action
        self.pageSetupChooser = pageSetupChooser
        self.printPanelChooser = printPanelChooser
        self.reportError = reportError
        self.telemetry = telemetry
        self.controls = PrintLayoutAccessoryController(settings: prepared.settings, settingsStore: settingsStore)
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        controls.onSettingsChanged = { [weak self] updated in
            self?.schedulePreviewRefresh(using: updated)
        }
        controls.onValidationChanged = { [weak self] _ in
            guard let self else { return }
            self.updatePrimaryEnabled(self.previewView.document != nil && !self.submitWhenPreviewReady)
        }
        controls.onPageSetupRequested = { [weak self] in
            guard let self, !self.sessionFinished else { return }
            self.submitWhenPreviewReady = false
            self.previewTask?.cancel()
            guard let selected = self.prepared.printInfo.copy() as? NSPrintInfo else {
                self.reportError("Could not open page setup", SessionError.unavailable("The current paper settings could not be copied."))
                return
            }
            if self.pageSetupChooser(selected) {
                self.prepared.setPageSettings(selected)
            }
            self.schedulePreviewRefresh(using: self.controls.currentSettings, debounce: false)
        }
        buildPanel()
    }

    func begin() {
        retainSession()
        parentCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parentWindow, queue: .main) { [weak self] _ in
            self?.completeCancellationIfNeeded()
        }
        panel.delegate = self
        parentWindow.beginSheet(panel)
        schedulePreviewRefresh(using: prepared.settings, debounce: false)
    }

    static var activeCountForTesting: Int { active.count }

    func windowWillClose(_ notification: Notification) {
        completeCancellationIfNeeded()
    }

    private func retainSession() {
        Self.active[ObjectIdentifier(self)] = self
    }

    private func finishSession() {
        guard !sessionFinished else { return }
        sessionFinished = true
        previewTask?.cancel()
        previewTask = nil
        outputTask?.cancel()
        outputTask = nil
        if let observer = parentCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            parentCloseObserver = nil
        }
        if let observer = pageChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            pageChangeObserver = nil
        }
        prepared.releaseHold()
        Self.active.removeValue(forKey: ObjectIdentifier(self))
    }

    private func buildPanel() {
        panel.title = {
            switch action {
            case .print: return "Print Layout"
            case .export: return "Export PDF Layout"
            }
        }()
        previewView.autoScales = true
        previewView.displayMode = .singlePage
        previewView.displaysPageBreaks = true
        previewView.backgroundColor = .windowBackgroundColor
        previewView.setAccessibilityLabel("Print preview")
        previewView.minScaleFactor = 0.2
        previewView.maxScaleFactor = 4

        previousPageButton.target = self
        previousPageButton.action = #selector(previousPagePressed(_:))
        nextPageButton.target = self
        nextPageButton.action = #selector(nextPagePressed(_:))
        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOutPressed(_:))
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomInPressed(_:))
        fitPageButton.target = self
        fitPageButton.action = #selector(fitPagePressed(_:))
        pageLabel.setAccessibilityLabel("Preview page")
        pageChangeObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: previewView, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePreviewNavigation() }
        }

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0

        primaryButton.title = {
            switch action {
            case .print: return "Continue to Print"
            case .export: return "Export PDF"
            }
        }()
        primaryButton.target = self
        primaryButton.action = #selector(primaryPressed(_:))
        primaryButton.bezelStyle = .rounded
        primaryButton.setButtonType(.momentaryPushIn)

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed(_:))
        cancelButton.bezelStyle = .rounded

        let split = NSSplitView()
        split.dividerStyle = .thin
        split.isVertical = true
        split.translatesAutoresizingMaskIntoConstraints = false

        let controlsContainer = NSView()
        controls.view.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(controls.view)
        NSLayoutConstraint.activate([
            controls.view.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            controls.view.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            controls.view.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            controls.view.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),
            controlsContainer.widthAnchor.constraint(equalToConstant: 300)
        ])
        split.addSubview(controlsContainer)
        let navigation = NSStackView(views: [previousPageButton, pageLabel, nextPageButton, NSView(), zoomOutButton, zoomInButton, fitPageButton])
        navigation.orientation = .horizontal
        navigation.spacing = 8
        navigation.alignment = .centerY
        navigation.setContentHuggingPriority(.required, for: .vertical)
        previewView.setContentHuggingPriority(.defaultLow, for: .vertical)
        let previewStack = NSStackView(views: [previewView, navigation])
        previewStack.orientation = .vertical
        previewStack.spacing = 8
        previewStack.alignment = .width
        split.addSubview(previewStack)

        let buttons = NSStackView(views: [cancelButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let footer = NSStackView(views: [statusLabel, NSView(), buttons])
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY

        let root = NSStackView(views: [split, footer])
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            split.heightAnchor.constraint(equalToConstant: 620)
        ])
        panel.contentView = container
        updateStatus("Preparing preview…")
        updatePrimaryEnabled(false)
        updatePreviewNavigation()
    }

    private func updateStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func updatePrimaryEnabled(_ enabled: Bool) {
        primaryButton.isEnabled = enabled && controls.validationMessage == nil
    }

    private func schedulePreviewRefresh(using settings: PrintLayoutSettings, debounce: Bool = true) {
        previewTask?.cancel()
        currentPreviewData = nil
        currentPreviewSettings = nil
        previewView.document = nil
        updateStatus("Rendering preview…")
        updatePrimaryEnabled(false)
        updatePreviewNavigation()
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                if debounce { try await Task.sleep(nanoseconds: 120_000_000) }
                try Task.checkCancellation()
                if !self.prepared.hasCurrentLayout(for: settings) {
                    try await self.prepared.reload(with: settings)
                }
                let streamingPreview = PDFDocument()
                let pdfData = try await self.prepared.createPDFData { count, total, data in
                    guard let page = PDFDocument(data: data)?.page(at: 0) else {
                        throw SessionError.unavailable("A rendered preview page could not be read.")
                    }
                    streamingPreview.insert(page, at: streamingPreview.pageCount)
                    if count == 1 {
                        self.previewView.document = streamingPreview
                        self.updatePrimaryEnabled(!self.submitWhenPreviewReady)
                    }
                    self.updateStatus("Preparing page \(count) of \(total)… Links activate when ready.")
                    self.updatePreviewNavigation()
                }
                guard !Task.isCancelled else { return }
                guard let completePreview = PDFDocument(data: pdfData) else { throw SessionError.missingPreview }
                let selectedPage = self.previewView.currentPage.map { streamingPreview.index(for: $0) } ?? 0
                self.currentPreviewData = pdfData
                self.currentPreviewSettings = settings
                self.previewView.document = completePreview
                if let page = completePreview.page(at: min(max(0, selectedPage), completePreview.pageCount - 1)) {
                    self.previewView.go(to: page)
                }
                let count = self.prepared.layoutMetrics.pageCount
                self.updateStatus("Preview ready — \(count) \(count == 1 ? "page" : "pages")")
                self.updatePrimaryEnabled(true)
                self.updatePreviewNavigation()
                if self.submitWhenPreviewReady {
                    self.primaryPressed(nil)
                }
            } catch {
                if Task.isCancelled { return }
                if case PrintDocumentRenderer.RenderError.superseded = error { return }
                if error is CancellationError { return }
                self.currentPreviewData = nil
                self.submitWhenPreviewReady = false
                self.previewView.document = nil
                self.updateStatus(error.localizedDescription)
                self.updatePrimaryEnabled(false)
                self.updatePreviewNavigation()
                self.telemetry("ouro_md_print_preview_failed", ["code": .string("preview_failed")])
            }
        }
    }

    private func updatePreviewNavigation() {
        let document = previewView.document
        let page = previewView.currentPage.flatMap { document?.index(for: $0) }
        let total = prepared.layoutMetrics.pageCount
        pageLabel.stringValue = page.map { "Page \($0 + 1) of \(total)" } ?? "No preview"
        previousPageButton.isEnabled = previewView.canGoToPreviousPage
        nextPageButton.isEnabled = previewView.canGoToNextPage
        let hasPage = (document?.pageCount ?? 0) > 0
        zoomOutButton.isEnabled = hasPage
        zoomInButton.isEnabled = hasPage
        fitPageButton.isEnabled = hasPage
    }

    @objc private func previousPagePressed(_ sender: Any?) {
        previewView.goToPreviousPage(sender)
        updatePreviewNavigation()
    }

    @objc private func nextPagePressed(_ sender: Any?) {
        previewView.goToNextPage(sender)
        updatePreviewNavigation()
    }

    @objc private func zoomOutPressed(_ sender: Any?) {
        previewView.autoScales = false
        previewView.scaleFactor = max(previewView.minScaleFactor, previewView.scaleFactor / 1.25)
    }

    @objc private func zoomInPressed(_ sender: Any?) {
        previewView.autoScales = false
        previewView.scaleFactor = min(previewView.maxScaleFactor, previewView.scaleFactor * 1.25)
    }

    @objc private func fitPagePressed(_ sender: Any?) {
        previewView.autoScales = true
    }

    @objc private func cancelPressed(_ sender: Any?) {
        endSheet()
        completeCancellationIfNeeded()
    }

    @objc private func primaryPressed(_ sender: Any?) {
        submitWhenPreviewReady = true
        panel.makeFirstResponder(nil)
        guard controls.applyCurrentValues() else {
            submitWhenPreviewReady = false
            NSSound.beep()
            return
        }
        guard let pdfData = currentPreviewData, currentPreviewSettings == controls.currentSettings else {
            updatePrimaryEnabled(false)
            return
        }
        submitWhenPreviewReady = false
        performOutput(using: pdfData)
    }

    private func performOutput(using pdfData: Data) {
        guard !sessionFinished else { return }
        endSheet()
        switch action {
        case .print:
            guard let selected = prepared.printInfo.copy() as? NSPrintInfo else {
                reportError("Could not open print settings", SessionError.unavailable("The current print settings could not be copied."))
                finishSession()
                return
            }
            guard printPanelChooser(selected) else { completeCancellationIfNeeded(); return }
            guard !sessionFinished else { return }
            do {
                try controls.currentSettings.validatePrintableArea(paperSize: selected.paperSize, imageableBounds: selected.imageablePageBounds)
            } catch {
                reportError("Could not prepare print document", error)
                parentWindow.beginSheet(panel)
                return
            }
            let repaginate = selected.paperSize != prepared.printInfo.paperSize
            prepared.setPageSettings(selected)
            outputTask = Task { @MainActor in
                do {
                    let finalData: Data
                    if repaginate {
                        try await self.prepared.reload(with: self.controls.currentSettings)
                        finalData = try await self.prepared.createPDFData()
                    } else {
                        finalData = pdfData
                    }
                    try Task.checkCancellation()
                    guard !self.sessionFinished else { return }
                    guard let pdfDocument = PDFDocument(data: finalData) else { throw SessionError.missingPreview }
                    let operation = try self.prepared.makePrintOperation(with: pdfDocument)
                    operation.showsPrintPanel = false
                    self.printOperationRunning = true
                    operation.runModal(for: self.parentWindow, delegate: self, didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.reportError("Could not prepare print document", error)
                    self.finishSession()
                }
            }
        case .export(let url, _):
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try pdfData.write(to: url, options: .atomic)
                    self.deliverExportCompletion(.success(true))
                } catch {
                    self.deliverExportCompletion(.failure(error))
                }
                self.finishSession()
            }
        }
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printOperationRunning = false
        if success {
            telemetry("ouro_md_print_completed", ["code": .string("printed")])
        } else {
            telemetry("ouro_md_print_cancelled", ["code": .string("cancelled")])
        }
        finishSession()
    }

    private func endSheet() {
        if panel.sheetParent != nil {
            parentWindow.endSheet(panel)
        }
        panel.orderOut(nil)
    }

    private func completeCancellationIfNeeded() {
        guard !sessionFinished else { return }
        if printOperationRunning {
            return
        }
        telemetry("ouro_md_print_cancelled", ["code": .string("cancelled")])
        deliverExportCompletion(.success(false))
        finishSession()
    }

    private func deliverExportCompletion(_ result: Result<Bool, Error>) {
        guard !completionDelivered else { return }
        guard case let .export(_, completion) = action else {
            completionDelivered = true
            return
        }
        completionDelivered = true
        completion(result)
    }
}
