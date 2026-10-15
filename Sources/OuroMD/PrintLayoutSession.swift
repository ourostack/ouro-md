import AppKit
import Foundation
import PDFKit
import WebKit

private final class NonPresentingPrintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

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

    enum Presentation: Equatable {
        case sheet
        case headless
    }

    typealias DocumentLoader = @MainActor (PrintLayoutSettings, NSPrintInfo, (@MainActor (PrintPreviewPhase) -> Void)?) async throws -> PreparedPrintDocument

    private struct PreviewIdentity: Equatable {
        let generation: Int
        let settings: PrintLayoutSettings
        let paperSize: NSSize
        let orientation: NSPrintInfo.PaperOrientation
    }

    private struct CompletePreview {
        let identity: PreviewIdentity
        let data: Data
    }

    private enum DisplayState: Equatable {
        case current
        case previousComplete
        case incompleteStale
    }

    private static var active: [ObjectIdentifier: PrintLayoutSession] = [:]

    private(set) var prepared: PreparedPrintDocument?
    private let documentLoader: DocumentLoader
    private var currentPrintInfo: NSPrintInfo
    private let parentWindow: NSWindow
    private let presentation: Presentation
    private let action: Action
    private let reportError: (String, Error) -> Void
    private let telemetry: (String, [String: OuroMDTelemetryValue]) -> Void
    private let onPhase: (@MainActor (PrintPreviewPhase) -> Void)?
    private let announceAccessibilityPhase: (@MainActor (String) -> Void)?
    private let pageSetupChooser: @MainActor (NSPrintInfo) -> Bool
    private let printPanelChooser: @MainActor (NSPrintInfo) -> Bool
    private let controls: PrintLayoutAccessoryController
    private let panel: NSPanel
    private let previewView = PDFView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let previousPageButton = NSButton(title: "Previous", target: nil, action: nil)
    private let nextPageButton = NSButton(title: "Next", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    private let zoomOutButton = NSButton(title: "Zoom out", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "Zoom in", target: nil, action: nil)
    private let fitPageButton = NSButton(title: "Fit page", target: nil, action: nil)
    private var pageChangeObserver: NSObjectProtocol?
    private var previewTask: Task<Void, Never>?
    private var completePreview: CompletePreview?
    private var lastCompleteDocument: PDFDocument?
    private var displayState = DisplayState.current
    private var generation = 0
    private var initialPreparationTask: Task<Void, Never>?
    private var initialAttempt = 0
    private var preparationFailed = false
    private var outputPreparationRunning = false
    private var announcedPhases = Set<String>()
    private var currentPhase: PrintPreviewPhase?
    private var submitWhenPreviewReady = false
    private var completionDelivered = false
    private var sessionFinished = false
    private var printOperationRunning = false
    private var outputTask: Task<Void, Never>?
    private var parentCloseObserver: NSObjectProtocol?

    convenience init(
        prepared: PreparedPrintDocument,
        parentWindow: NSWindow,
        action: Action,
        settingsStore: PrintLayoutSettingsStore,
        pageSetupChooser: @escaping @MainActor (NSPrintInfo) -> Bool = { NSPageLayout().runModal(with: $0) == NSApplication.ModalResponse.OK.rawValue },
        printPanelChooser: @escaping @MainActor (NSPrintInfo) -> Bool = { NSPrintPanel().runModal(with: $0) == NSApplication.ModalResponse.OK.rawValue },
        reportError: @escaping (String, Error) -> Void,
        telemetry: @escaping (String, [String: OuroMDTelemetryValue]) -> Void,
        onPhase: (@MainActor (PrintPreviewPhase) -> Void)? = nil,
        announceAccessibilityPhase: (@MainActor (String) -> Void)? = nil,
        presentation: Presentation = .sheet
    ) {
        self.init(settings: prepared.settings, printInfo: prepared.printInfo, documentLoader: { _, _, _ in prepared }, parentWindow: parentWindow, action: action, settingsStore: settingsStore, pageSetupChooser: pageSetupChooser, printPanelChooser: printPanelChooser, reportError: reportError, telemetry: telemetry, onPhase: onPhase, announceAccessibilityPhase: announceAccessibilityPhase, presentation: presentation)
        self.prepared = prepared
    }

    init(
        settings: PrintLayoutSettings,
        printInfo: NSPrintInfo,
        documentLoader: @escaping DocumentLoader,
        parentWindow: NSWindow,
        action: Action,
        settingsStore: PrintLayoutSettingsStore,
        pageSetupChooser: @escaping @MainActor (NSPrintInfo) -> Bool = { NSPageLayout().runModal(with: $0) == NSApplication.ModalResponse.OK.rawValue },
        printPanelChooser: @escaping @MainActor (NSPrintInfo) -> Bool = { NSPrintPanel().runModal(with: $0) == NSApplication.ModalResponse.OK.rawValue },
        reportError: @escaping (String, Error) -> Void,
        telemetry: @escaping (String, [String: OuroMDTelemetryValue]) -> Void,
        onPhase: (@MainActor (PrintPreviewPhase) -> Void)? = nil,
        announceAccessibilityPhase: (@MainActor (String) -> Void)? = nil,
        presentation: Presentation = .sheet
    ) {
        self.documentLoader = documentLoader
        self.currentPrintInfo = settings.applying(to: printInfo)
        self.parentWindow = parentWindow
        self.presentation = presentation
        self.action = action
        self.pageSetupChooser = pageSetupChooser
        self.printPanelChooser = printPanelChooser
        self.reportError = reportError
        self.telemetry = telemetry
        self.onPhase = onPhase
        self.announceAccessibilityPhase = announceAccessibilityPhase
        self.controls = PrintLayoutAccessoryController(settings: settings, settingsStore: settingsStore)
        let panelType: NSPanel.Type = presentation == .headless ? NonPresentingPrintPanel.self : NSPanel.self
        self.panel = panelType.init(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        if presentation == .headless {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        }
        controls.onSettingsChanged = { [weak self] updated in
            self?.schedulePreviewRefresh(using: updated)
        }
        controls.onValidationChanged = { [weak self] _ in
            guard let self else { return }
            self.updatePrimaryEnabled(self.previewView.document != nil && !self.submitWhenPreviewReady && !self.preparationFailed)
            self.retryButton.isEnabled = self.controls.validationMessage == nil
        }
        controls.onPageSetupRequested = { [weak self] in
            guard let self, !self.sessionFinished, !self.outputPreparationRunning else { return }
            self.submitWhenPreviewReady = false
            self.previewTask?.cancel()
            guard let selected = self.currentPrintInfo.copy() as? NSPrintInfo else {
                self.reportError("Could not open page setup", SessionError.unavailable("The current paper settings could not be copied."))
                return
            }
            if self.pageSetupChooser(selected) {
                self.currentPrintInfo = selected
            }
            self.schedulePreviewRefresh(using: self.controls.currentSettings, debounce: false)
        }
        buildPanel()
    }

    func begin() {
        guard !sessionFinished else { return }
        if presentation == .headless, isPrintRequest {
            reportError("Could not open print layout", SessionError.unavailable("Headless acceptance supports PDF export only, without native printer dialogs."))
            finishSession()
            return
        }
        if Self.activeSession(for: parentWindow) === self {
            bringToFront()
            return
        }
        guard Self.activeSession(for: parentWindow) == nil, parentWindow.attachedSheet == nil else {
            let error = SessionError.unavailable("Another sheet or print layout is already open for this document.")
            reportError("Could not open print layout", error)
            deliverExportCompletion(.failure(error))
            finishSession()
            return
        }
        retainSession()
        parentCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parentWindow, queue: .main) { [weak self] _ in
            self?.completeCancellationIfNeeded()
        }
        panel.delegate = self
        if presentation == .sheet {
            parentWindow.beginSheet(panel)
        } else {
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        schedulePreviewRefresh(using: controls.currentSettings, debounce: false)
    }

    static var activeCountForTesting: Int { active.count }
    var panelForTesting: NSPanel { panel }

    static func activeSession(for parentWindow: NSWindow) -> PrintLayoutSession? {
        active[ObjectIdentifier(parentWindow)]
    }

    var isPrintRequest: Bool {
        if case .print = action { return true }
        return false
    }

    func bringToFront() {
        guard !sessionFinished, presentation == .sheet else { return }
        (parentWindow.attachedSheet ?? parentWindow).makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        completeCancellationIfNeeded()
    }

    private func retainSession() {
        Self.active[ObjectIdentifier(parentWindow)] = self
    }

    private func finishSession() {
        guard !sessionFinished else { return }
        sessionFinished = true
        generation += 1
        initialAttempt += 1
        initialPreparationTask?.cancel()
        initialPreparationTask = nil
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
        prepared?.releaseHold()
        prepared = nil
        if Self.active[ObjectIdentifier(parentWindow)] === self {
            Self.active.removeValue(forKey: ObjectIdentifier(parentWindow))
        }
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
        retryButton.target = self
        retryButton.action = #selector(retryPressed(_:))
        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.setAccessibilityLabel("Print preview progress")
        progressIndicator.widthAnchor.constraint(equalToConstant: 140).isActive = true

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
            controlsContainer.widthAnchor.constraint(equalToConstant: 360)
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

        let buttons = NSStackView(views: [retryButton, cancelButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let footer = NSStackView(views: [progressIndicator, statusLabel, NSView(), buttons])
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
        primaryButton.isEnabled = enabled && controls.validationMessage == nil && !outputPreparationRunning
    }

    private func schedulePreviewRefresh(using settings: PrintLayoutSettings, debounce: Bool = true) {
        guard !sessionFinished, !outputPreparationRunning else { return }
        previewTask?.cancel()
        generation += 1
        let requestedGeneration = generation
        completePreview = nil
        displayState = staleDisplayState
        preparationFailed = false
        retryButton.isHidden = true
        announcedPhases.removeAll()
        if let prepared, prepared.isLoading {
            prepared.cancelLoading()
        }
        if prepared == nil {
            updatePhase(initialPreparationTask == nil ? .extractingHTML : (currentPhase ?? .extractingHTML), generation: requestedGeneration)
        } else {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
            updateStatus(updatingPreviewPrefix + "Rendering preview…")
        }
        updatePrimaryEnabled(previewView.document != nil && !submitWhenPreviewReady)
        updatePreviewNavigation()
        guard let prepared else {
            startInitialPreparation()
            return
        }
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                if debounce { try await Task.sleep(nanoseconds: 120_000_000) }
                try Task.checkCancellation()
                guard self.isCurrent(requestedGeneration) else { return }
                prepared.setPageSettings(self.currentPrintInfo)
                let phaseObserver: @MainActor (PrintPreviewPhase) -> Void = { [weak self] phase in self?.updatePhase(phase, generation: requestedGeneration) }
                if !prepared.hasCurrentLayout(for: settings) {
                    try await prepared.reload(with: settings, onPhase: phaseObserver)
                }
                guard self.isCurrent(requestedGeneration) else { return }
                let streamingPreview = PDFDocument()
                var displayingReplacement = self.previewView.document == nil
                let pdfData = try await prepared.createPDFData(onPhase: phaseObserver) { count, total, data in
                    guard self.isCurrent(requestedGeneration), !Task.isCancelled else { throw CancellationError() }
                    guard let page = PDFDocument(data: data)?.page(at: 0) else {
                        throw SessionError.unavailable("A rendered preview page could not be read.")
                    }
                    streamingPreview.insert(page, at: streamingPreview.pageCount)
                    let selectedPage = self.selectedPreviewPageIndex
                    if displayingReplacement || count > min(selectedPage, total - 1) {
                        if !displayingReplacement || count == 1 {
                            self.display(streamingPreview, selectedPage: min(selectedPage, total - 1))
                            self.displayState = .current
                            displayingReplacement = true
                            self.updateStatus(self.captureStatus(completed: count, total: total))
                        }
                        self.updatePrimaryEnabled(!self.submitWhenPreviewReady)
                    }
                    self.updatePreviewNavigation()
                }
                guard !Task.isCancelled, self.isCurrent(requestedGeneration) else { return }
                guard let completePreview = PDFDocument(data: pdfData) else { throw SessionError.missingPreview }
                self.completePreview = CompletePreview(identity: self.identity(settings: settings), data: pdfData)
                self.lastCompleteDocument = completePreview
                self.displayState = .current
                self.display(completePreview, selectedPage: self.selectedPreviewPageIndex)
                self.updatePhase(.ready, generation: requestedGeneration)
                guard self.isCurrent(requestedGeneration) else { return }
                self.updatePrimaryEnabled(true)
                self.updatePreviewNavigation()
                if self.submitWhenPreviewReady {
                    self.primaryPressed(nil)
                }
            } catch {
                if Task.isCancelled || !self.isCurrent(requestedGeneration) { return }
                self.failPreparation(error, generation: requestedGeneration)
            }
        }
    }

    private func updatePreviewNavigation() {
        let document = previewView.document
        let page = previewView.currentPage.flatMap { document?.index(for: $0) }
        let total = displayState != .current || preparationFailed ? (document?.pageCount ?? 0) : max(document?.pageCount ?? 0, prepared?.layoutMetrics.pageCount ?? 0)
        pageLabel.stringValue = page.map { displayState == .incompleteStale ? "Page \($0 + 1) — incomplete preview" : "Page \($0 + 1) of \(total)" } ?? "No preview"
        previousPageButton.isEnabled = previewView.canGoToPreviousPage
        nextPageButton.isEnabled = previewView.canGoToNextPage
        let hasPage = (document?.pageCount ?? 0) > 0
        zoomOutButton.isEnabled = hasPage
        zoomInButton.isEnabled = hasPage
        fitPageButton.isEnabled = hasPage
    }

    private func isCurrent(_ requestedGeneration: Int) -> Bool {
        !sessionFinished && requestedGeneration == generation
    }

    private func identity(settings: PrintLayoutSettings) -> PreviewIdentity {
        PreviewIdentity(generation: generation, settings: settings.normalized, paperSize: currentPrintInfo.paperSize, orientation: currentPrintInfo.orientation)
    }

    private var staleDisplayState: DisplayState {
        guard let document = previewView.document else { return .current }
        return document === lastCompleteDocument ? .previousComplete : .incompleteStale
    }

    private var updatingPreviewPrefix: String {
        switch displayState {
        case .current: return ""
        case .previousComplete: return "Previous layout — updating. "
        case .incompleteStale: return "Incomplete preview — updating. "
        }
    }

    private func captureStatus(completed: Int, total: Int) -> String {
        updatingPreviewPrefix + "Preparing page \(completed) of \(total)… Links activate when ready."
    }

    private var selectedPreviewPageIndex: Int {
        guard let document = previewView.document, let page = previewView.currentPage else { return 0 }
        return max(0, document.index(for: page))
    }

    private func display(_ document: PDFDocument, selectedPage: Int) {
        let fit = previewView.autoScales
        let scale = previewView.scaleFactor
        previewView.document = document
        if let page = document.page(at: min(max(0, selectedPage), document.pageCount - 1)) {
            previewView.go(to: page)
        }
        previewView.autoScales = fit
        if !fit { previewView.scaleFactor = scale }
    }

    private func startInitialPreparation() {
        guard initialPreparationTask == nil, !sessionFinished else { return }
        initialAttempt += 1
        let attempt = initialAttempt
        let settings = controls.currentSettings
        let info = settings.applying(to: currentPrintInfo)
        initialPreparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let document = try await self.documentLoader(settings, info) { [weak self] phase in
                    guard let self, !self.sessionFinished, self.initialAttempt == attempt else { return }
                    self.updatePhase(phase, generation: self.generation)
                }
                guard !Task.isCancelled, !self.sessionFinished, self.initialAttempt == attempt else {
                    document.releaseHold()
                    return
                }
                self.initialPreparationTask = nil
                self.prepared = document
                self.schedulePreviewRefresh(using: self.controls.currentSettings, debounce: false)
            } catch {
                guard !Task.isCancelled, !self.sessionFinished, self.initialAttempt == attempt else { return }
                self.initialPreparationTask = nil
                self.failPreparation(error, generation: self.generation)
            }
        }
    }

    private func updatePhase(_ phase: PrintPreviewPhase, generation: Int) {
        guard isCurrent(generation) else { return }
        currentPhase = phase
        onPhase?(phase)
        guard isCurrent(generation) else { return }
        let prefix = updatingPreviewPrefix
        let announcement: String
        switch phase {
        case .extractingHTML:
            announcement = "Preparing document for print."
            updateStatus(prefix + "Preparing document…")
        case .loadingHTML:
            announcement = "Loading print layout."
            updateStatus(prefix + "Loading print layout…")
        case .paginating:
            announcement = "Paginating print layout."
            updateStatus(prefix + "Paginating print layout…")
        case .capturingPages(let completed, let total):
            announcement = "Preparing preview pages."
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = Double(max(1, total))
            progressIndicator.doubleValue = Double(completed)
            updateStatus(captureStatus(completed: completed, total: total))
        case .assemblingPDF:
            announcement = "Finishing complete PDF."
            updateStatus(prefix + "Finishing complete PDF…")
        case .ready:
            let count = previewView.document?.pageCount ?? 0
            announcement = "Print preview ready."
            updateStatus("Preview ready — \(count) \(count == 1 ? "page" : "pages")")
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.doubleValue = progressIndicator.maxValue
        case .failed:
            announcement = "Print preview preparation failed. Retry or Cancel is available."
        }
        switch phase {
        case .extractingHTML, .loadingHTML, .paginating, .assemblingPDF:
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
        case .failed:
            progressIndicator.isIndeterminate = false
            progressIndicator.stopAnimation(nil)
            progressIndicator.doubleValue = 0
        case .capturingPages, .ready:
            break
        }
        if announcedPhases.insert(phase.code).inserted {
            if let announceAccessibilityPhase {
                announceAccessibilityPhase(announcement)
            } else {
                NSAccessibility.post(element: progressIndicator, notification: .announcementRequested, userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
    }

    private func failPreparation(_ error: Error, generation: Int) {
        guard isCurrent(generation) else { return }
        completePreview = nil
        preparationFailed = true
        if let lastCompleteDocument {
            display(lastCompleteDocument, selectedPage: selectedPreviewPageIndex)
        }
        displayState = staleDisplayState
        submitWhenPreviewReady = false
        updatePhase(.failed, generation: generation)
        guard isCurrent(generation) else { return }
        let failurePrefix = previewView.document == nil ? "" : (displayState == .previousComplete ? "Previous layout — update failed. " : "Incomplete preview — preparation failed. ")
        updateStatus(failurePrefix + error.localizedDescription)
        retryButton.isHidden = false
        retryButton.isEnabled = controls.validationMessage == nil
        updatePrimaryEnabled(false)
        updatePreviewNavigation()
        telemetry("ouro_md_print_preview_failed", ["code": .string("preview_failed")])
    }

    @objc private func retryPressed(_ sender: Any?) {
        guard !sessionFinished, preparationFailed, !outputPreparationRunning else { return }
        submitWhenPreviewReady = false
        panel.makeFirstResponder(nil)
        guard controls.applyCurrentValues() else { return }
        if preparationFailed {
            schedulePreviewRefresh(using: controls.currentSettings, debounce: false)
        }
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
        guard !sessionFinished, !preparationFailed, !outputPreparationRunning else { return }
        submitWhenPreviewReady = true
        panel.makeFirstResponder(nil)
        guard controls.applyCurrentValues() else {
            submitWhenPreviewReady = false
            NSSound.beep()
            return
        }
        guard let completePreview, completePreview.identity == identity(settings: controls.currentSettings), !preparationFailed else {
            updatePrimaryEnabled(false)
            return
        }
        submitWhenPreviewReady = false
        performOutput(using: completePreview)
    }

    private func performOutput(using preview: CompletePreview) {
        guard !sessionFinished, preview.identity == identity(settings: controls.currentSettings), let prepared else { return }
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
            let repaginate = selected.paperSize != preview.identity.paperSize || selected.orientation != preview.identity.orientation
            currentPrintInfo = selected
            prepared.setPageSettings(selected)
            outputPreparationRunning = true
            primaryButton.isEnabled = false
            controls.view.subviews.forEach { self.setLayoutEditing($0, enabled: false) }
            if repaginate {
                generation += 1
                completePreview = nil
                displayState = staleDisplayState
                announcedPhases.removeAll()
                parentWindow.beginSheet(panel)
                updatePhase(.loadingHTML, generation: generation)
            }
            guard !sessionFinished else { return }
            let outputIdentity = identity(settings: controls.currentSettings)
            outputTask = Task { @MainActor in
                do {
                    let finalData: Data
                    if repaginate {
                        let phaseObserver: @MainActor (PrintPreviewPhase) -> Void = { [weak self] phase in self?.updatePhase(phase, generation: outputIdentity.generation) }
                        try await prepared.reload(with: outputIdentity.settings, onPhase: phaseObserver)
                        finalData = try await prepared.createPDFData(onPhase: phaseObserver)
                    } else {
                        finalData = preview.data
                    }
                    try Task.checkCancellation()
                    guard !self.sessionFinished, outputIdentity == self.identity(settings: self.controls.currentSettings) else { return }
                    guard let pdfDocument = PDFDocument(data: finalData) else { throw SessionError.missingPreview }
                    self.completePreview = CompletePreview(identity: outputIdentity, data: finalData)
                    self.lastCompleteDocument = pdfDocument
                    self.display(pdfDocument, selectedPage: self.selectedPreviewPageIndex)
                    self.updatePhase(.ready, generation: outputIdentity.generation)
                    guard self.isCurrent(outputIdentity.generation), !Task.isCancelled else { return }
                    self.endSheet()
                    let operation = try prepared.makePrintOperation(with: pdfDocument)
                    operation.showsPrintPanel = false
                    self.printOperationRunning = true
                    operation.runModal(for: self.parentWindow, delegate: self, didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.outputPreparationRunning = false
                    self.controls.view.subviews.forEach { self.setLayoutEditing($0, enabled: true) }
                    if self.panel.sheetParent == nil { self.parentWindow.beginSheet(self.panel, completionHandler: nil) }
                    self.failPreparation(error, generation: outputIdentity.generation)
                }
            }
        case .export(let url, _):
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    guard !self.sessionFinished else { return }
                    guard preview.identity == self.identity(settings: self.controls.currentSettings) else {
                        self.deliverExportCompletion(.failure(SessionError.unavailable("The PDF export was superseded by a newer layout.")))
                        self.finishSession()
                        return
                    }
                    try preview.data.write(to: url, options: .atomic)
                    self.deliverExportCompletion(.success(true))
                } catch {
                    self.deliverExportCompletion(.failure(error))
                }
                self.finishSession()
            }
        }
    }

    private func setLayoutEditing(_ view: NSView, enabled: Bool) {
        (view as? NSControl)?.isEnabled = enabled
        view.subviews.forEach { setLayoutEditing($0, enabled: enabled) }
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
        endSheet()
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
