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
    private let controls: PrintLayoutAccessoryController
    private let panel: NSPanel
    private let previewView = PDFView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var previewTask: Task<Void, Never>?
    private var currentPreviewData: Data?
    private var completionDelivered = false
    private var sessionFinished = false
    private var printOperationRunning = false

    init(
        prepared: PreparedPrintDocument,
        parentWindow: NSWindow,
        action: Action,
        settingsStore: PrintLayoutSettingsStore,
        reportError: @escaping (String, Error) -> Void,
        telemetry: @escaping (String, [String: OuroMDTelemetryValue]) -> Void
    ) {
        self.prepared = prepared
        self.parentWindow = parentWindow
        self.action = action
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
            self?.updatePrimaryEnabled(self?.currentPreviewData != nil)
        }
        buildPanel()
    }

    func begin() {
        retainSession()
        panel.delegate = self
        parentWindow.beginSheet(panel)
        schedulePreviewRefresh(using: prepared.settings)
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
        previewView.displayMode = .singlePageContinuous
        previewView.displaysPageBreaks = true
        previewView.backgroundColor = .windowBackgroundColor
        previewView.setAccessibilityLabel("Print preview")

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
        split.addSubview(previewView)

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
    }

    private func updateStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func updatePrimaryEnabled(_ enabled: Bool) {
        primaryButton.isEnabled = enabled && controls.validationMessage == nil
    }

    private func schedulePreviewRefresh(using settings: PrintLayoutSettings) {
        previewTask?.cancel()
        updateStatus("Rendering preview…")
        updatePrimaryEnabled(false)
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.prepared.reload(with: settings)
                let pdfData = try await self.prepared.createPDFData()
                guard !Task.isCancelled else { return }
                self.currentPreviewData = pdfData
                self.previewView.document = PDFDocument(data: pdfData)
                self.updateStatus("Preview ready")
                self.updatePrimaryEnabled(true)
            } catch {
                if Task.isCancelled { return }
                if case PrintDocumentRenderer.RenderError.superseded = error { return }
                if error is CancellationError { return }
                self.currentPreviewData = nil
                self.previewView.document = nil
                self.updateStatus(error.localizedDescription)
                self.updatePrimaryEnabled(false)
                self.telemetry("ouro_md_print_preview_failed", ["code": .string("preview_failed")])
            }
        }
    }

    @objc private func cancelPressed(_ sender: Any?) {
        endSheet()
        completeCancellationIfNeeded()
    }

    @objc private func primaryPressed(_ sender: Any?) {
        panel.makeFirstResponder(nil)
        guard controls.applyCurrentValues() else {
            NSSound.beep()
            return
        }
        guard let pdfData = currentPreviewData else {
            reportError("Could not prepare print preview", SessionError.missingPreview)
            return
        }
        endSheet()
        switch action {
        case .print:
            guard let pdfDocument = PDFDocument(data: pdfData) else {
                reportError("Could not prepare print document", SessionError.missingPreview)
                finishSession()
                return
            }
            do {
                let operation = try prepared.makePrintOperation(with: pdfDocument)
                printOperationRunning = true
                operation.runModal(
                    for: parentWindow,
                    delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                    contextInfo: nil
                )
            } catch {
                reportError("Could not prepare print document", error)
                finishSession()
            }
        case .export(let url, _):
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try pdfData.write(to: url, options: .atomic)
                    self.deliverExportCompletion(.success(true))
                    self.telemetry("ouro_md_export_completed", ["format": .string("pdf")])
                } catch {
                    self.deliverExportCompletion(.failure(error))
                    self.telemetry("ouro_md_export_failed", ["format": .string("pdf")])
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
            telemetry("ouro_md_print_cancelled", ["code": .string("cancelled")])
            printOperationRunning = false
        } else {
            telemetry("ouro_md_print_cancelled", ["code": .string("cancelled")])
        }
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
