import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var initialFilePath: String?
    private var controllers: [DocumentWindowController] = []
    private lazy var fallbackModel = AppModel()
    private let defaults = UserDefaults.standard
    let updateCoordinator = OuroMDUpdateCoordinator()
    private var updateCancellables: Set<AnyCancellable> = []
    private var undoRedoShortcutMonitor: UndoRedoShortcutMonitor?

    private var isSelfTest: Bool { ProcessInfo.processInfo.environment["OURO_SELFTEST"] == "1" }

    /// The window the user is acting on (key/main), else the last opened.
    var frontController: DocumentWindowController? {
        let app = NSApplication.shared
        if let key = app.keyWindow, let c = controllers.first(where: { $0.window === key }) { return c }
        if let main = app.mainWindow, let c = controllers.first(where: { $0.window === main }) { return c }
        return controllers.last
    }
    /// Forwarding accessors keep every menu action targeting the active window.
    var model: AppModel { frontController?.model ?? controllers.first?.model ?? fallbackModel }
    var window: NSWindow! { frontController?.window }
    func syncChrome() { frontController?.syncChrome() }

    /// Registers a window controller and ensures it's dropped when its window
    /// closes, so closed windows (and their watchers) don't leak.
    private func track(_ controller: DocumentWindowController) {
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installUndoRedoShortcutMonitor()
        if isSelfTest {
            let controller = DocumentWindowController(filePath: initialFilePath, selfTest: true, useAutosave: true)
            track(controller)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { exit(0) }
            return
        }
        observeUpdatePrompts()
        let launchKind: String
        if let path = initialFilePath {
            openInitial(path)
            launchKind = "file"
        } else if restoreSession() {
            launchKind = "restored_session"
        } else {
            let firstRun = !defaults.bool(forKey: "ouro.hasLaunched")
            defaults.set(true, forKey: "ouro.hasLaunched")
            let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: true)
            track(controller)
            if firstRun { controller.model.loadWelcome() }
            controller.show(cascadeFrom: nil)
            launchKind = firstRun ? "first_run" : "new_document"
        }
        OuroMDTelemetry.shared.capture(
            "ouro_md_app_launched",
            properties: ["launch_kind": .string(launchKind)]
        )
        Task { await updateCoordinator.runAutoUpdateCheckIfDue() }
    }

    private func observeUpdatePrompts() {
        updateCoordinator.$updatePrompt
            .compactMap { $0 }
            .sink { [weak self] prompt in
                self?.presentUpdatePrompt(prompt)
            }
            .store(in: &updateCancellables)
    }

    private func presentUpdatePrompt(_ prompt: OuroMDUpdatePrompt) {
        let alert = NSAlert()
        alert.messageText = "Software Update"
        alert.informativeText = prompt.message
        if prompt.isInstallable {
            alert.addButton(withTitle: "Install & Relaunch")
            alert.addButton(withTitle: "Later")
        } else {
            alert.addButton(withTitle: "OK")
        }
        let response = alert.runModal()
        if prompt.isInstallable, response == .alertFirstButtonReturn {
            updateCoordinator.updatePrompt = nil
            Task { await updateCoordinator.installReleaseUpdate() }
        } else if prompt.isInstallable {
            updateCoordinator.dismissUpdatePrompt(reason: "later")
        } else {
            updateCoordinator.dismissUpdatePrompt(reason: "acknowledged")
        }
    }

    private func openInitial(_ path: String?) {
        let controller = DocumentWindowController(filePath: path, selfTest: false, useAutosave: true)
        track(controller)
        controller.show(cascadeFrom: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        undoRedoShortcutMonitor?.invalidate()
        saveSession()
        if !updateCoordinator.applyPendingManualUpdateAndRelaunchIfNeeded() {
            updateCoordinator.applyStagedUpdateOnQuitIfNeeded()
        }
    }

    // MARK: - Session restoration

    /// Persists the open documents + mounted folder so a relaunch reopens them.
    private func saveSession() {
        let docs = controllers.compactMap { $0.model.currentURL?.path }
        defaults.set(docs, forKey: "ouro.session.docs")
        defaults.set(frontController?.model.mountedFolder?.path, forKey: "ouro.session.folder")
    }

    /// Reopens the previously-open documents (one window each) and folder.
    /// Returns false if there was nothing to restore.
    @discardableResult
    private func restoreSession() -> Bool {
        let fm = FileManager.default
        let docs = (defaults.array(forKey: "ouro.session.docs") as? [String] ?? []).filter { fm.fileExists(atPath: $0) }
        let folderPath = defaults.string(forKey: "ouro.session.folder")
        let folder = folderPath.flatMap { fm.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
        guard !docs.isEmpty || folder != nil else { return false }

        var previous: NSWindow?
        for path in docs {
            let controller = DocumentWindowController(filePath: path, selfTest: false, useAutosave: previous == nil)
            track(controller)
            controller.show(cascadeFrom: previous)
            previous = controller.window
        }
        if let folder {
            if let first = controllers.first {
                first.model.openFolder(folder)
            } else {
                let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: true)
                track(controller)
                controller.model.openFolder(folder)
                controller.show(cascadeFrom: nil)
            }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let c = frontController, c.model.currentURL == nil, !c.model.isDirty {
                c.model.open(url: url)
            } else {
                openInNewWindow(url)
            }
        }
    }

    // MARK: - Multi-window

    @objc func newWindow(_ sender: Any?) {
        let prev = frontController?.window
        let controller = DocumentWindowController(filePath: nil, selfTest: false, useAutosave: false)
        track(controller)
        controller.show(cascadeFrom: prev)
    }

    func openInNewWindow(_ url: URL) {
        if let existing = controllers.first(where: { $0.model.currentURL == url }) {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let prev = frontController?.window
        let controller = DocumentWindowController(filePath: url.path, selfTest: false, useAutosave: false)
        track(controller)
        controller.show(cascadeFrom: prev)
    }

    @objc func printDocument(_ sender: Any?) { frontController?.printDocument() }
    @objc func undoEdit(_ sender: Any?) {
        performUndoRedoCommand(.undo, firstResponder: NSApp.keyWindow?.firstResponder)
    }
    @objc func redoEdit(_ sender: Any?) {
        performUndoRedoCommand(.redo, firstResponder: NSApp.keyWindow?.firstResponder)
    }

    private func installUndoRedoShortcutMonitor() {
        guard undoRedoShortcutMonitor == nil else { return }
        let monitor = UndoRedoShortcutMonitor { [weak self] command, firstResponder in
            self?.performUndoRedoCommand(command, firstResponder: firstResponder) ?? false
        }
        monitor.install()
        undoRedoShortcutMonitor = monitor
    }

    @discardableResult
    private func performUndoRedoCommand(_ command: UndoRedoCommand, firstResponder: NSResponder?) -> Bool {
        UndoRedoCommandRouter.perform(
            command,
            firstResponder: firstResponder,
            editorIsReady: model.isReady,
            editorUndo: { [model] in model.undo() },
            editorRedo: { [model] in model.redo() }
        )
    }

    private var prefsWindow: NSWindow?
    @objc func showPreferences(_ sender: Any?) {
        if prefsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Preferences"
            w.isReleasedWhenClosed = false
            w.center()
            prefsWindow = w
        }
        // Re-bind to the active window's model each time it opens.
        prefsWindow?.contentViewController = NSHostingController(
            rootView: PreferencesView(
                model: model,
                updateCoordinator: updateCoordinator,
                telemetry: OuroMDTelemetry.shared
            )
        )
        prefsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = controllers.filter { $0.model.isDirty }
        guard !dirty.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = dirty.count == 1 ? "You have unsaved changes." : "You have unsaved changes in \(dirty.count) windows."
        alert.informativeText = "Do you want to save them before quitting?"
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let saves = dirty.map { controller in
                { (completion: @escaping (Bool) -> Void) in
                    controller.model.performSave(completion: completion)
                }
            }
            TerminationSaveCoordinator.saveAll(
                saves,
                onCancel: { [weak self] in self?.updateCoordinator.cancelPendingManualInstall() },
                reply: { NSApp.reply(toApplicationShouldTerminate: $0) }
            )
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            updateCoordinator.cancelPendingManualInstall()
            return .terminateCancel
        }
    }

    // MARK: - Menu actions

    @objc func checkForUpdates(_ sender: Any?) {
        Task { await updateCoordinator.checkForUpdatesAndPromptInstall() }
    }

    @objc func installUpdateAndRelaunch(_ sender: Any?) {
        Task { await updateCoordinator.installReleaseUpdate() }
    }

    @objc func newDocument(_ sender: Any?) { model.newDocument() }
    @objc func openDocument(_ sender: Any?) { model.openPanel() }
    @objc func openFolder(_ sender: Any?) { model.openFolderPanel() }
    @objc func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { model.open(url: url) }
    }
    @objc func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }
    @objc func saveDocument(_ sender: Any?) { model.save() }
    @objc func saveDocumentAs(_ sender: Any?) { model.saveAs() }
    @objc func renameDocument(_ sender: Any?) { frontController?.presentRename() }
    @objc func exportHTML(_ sender: Any?) { model.exportHTML() }
    @objc func exportPDF(_ sender: Any?) { model.exportPDF() }

    @objc func selectTheme(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            model.setTheme(id: id)
            syncChrome()
        }
    }
    @objc func selectMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? String {
            model.setMode(mode)
            syncChrome()
        }
    }
    @objc func toggleOutline(_ sender: Any?) { model.toggleOutline(); syncChrome() }
    @objc func toggleFocusMode(_ sender: Any?) { model.toggleFocusMode(); syncChrome() }
    @objc func toggleTypewriter(_ sender: Any?) { model.toggleTypewriter(); syncChrome() }

    @objc func toggleWordCount(_ sender: Any?) { frontController?.toggleWordCount(sender) }

    @objc func toggleSidebar(_ sender: Any?) { frontController?.toggleSidebar() }
    @objc func showOutlineSidebar(_ sender: Any?) { frontController?.revealSidebar(mode: .outline) }
    @objc func showFileTreeSidebar(_ sender: Any?) { frontController?.revealSidebar(mode: .files) }
    @objc func toggleSourceMode(_ sender: Any?) {
        model.setMode(model.mode == "sv" ? "ir" : "sv")
        syncChrome()
    }
    @objc func performFind(_ sender: Any?) { model.showFind() }
    @objc func performReplace(_ sender: Any?) { model.showReplace() }
    @objc func findNextCommand(_ sender: Any?) { model.findNext() }
    @objc func findPrevCommand(_ sender: Any?) { model.findPrev() }

    @objc func applyParagraph(_ sender: NSMenuItem) {
        if let command = sender.representedObject as? String { model.format(command) }
    }
    @objc func zoomIn(_ sender: Any?) { model.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { model.zoomOut() }
    @objc func actualSize(_ sender: Any?) { model.actualSize() }

    @objc func formatBold(_ sender: Any?) { model.format("bold") }
    @objc func formatItalic(_ sender: Any?) { model.format("italic") }
    @objc func formatStrikethrough(_ sender: Any?) { model.format("strike") }
    @objc func formatInlineCode(_ sender: Any?) { model.format("code") }
    @objc func insertLink(_ sender: Any?) { model.format("link") }
    @objc func pasteAsPlainText(_ sender: Any?) { model.pasteAsPlainText() }
    @objc func copyAsMarkdown(_ sender: Any?) { model.copyAsMarkdown() }
    @objc func copyAsHTML(_ sender: Any?) { model.copyAsHTML() }

    @objc func openProjectPage(_ sender: Any?) {
        if let url = URL(string: "https://github.com/ourostack/ouro-md") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func reportIssue(_ sender: Any?) {
        if let url = URL(string: "https://github.com/ourostack/ouro-md/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        let hasEditor = frontController != nil
        let editorReady = hasEditor && model.isReady

        switch action {
        case #selector(newDocument(_:)),
             #selector(newWindow(_:)),
             #selector(openDocument(_:)),
             #selector(openFolder(_:)),
             #selector(showPreferences(_:)),
             #selector(checkForUpdates(_:)),
             #selector(openProjectPage(_:)),
             #selector(reportIssue(_:)):
            return true
        case #selector(openRecent(_:)):
            return menuItem.representedObject is URL
        case #selector(clearRecentDocuments(_:)):
            return !NSDocumentController.shared.recentDocumentURLs.isEmpty
        case #selector(renameDocument(_:)):
            return hasEditor && model.currentURL != nil
        case #selector(installUpdateAndRelaunch(_:)):
            return updateCoordinator.updateBadgeText != nil && !updateCoordinator.isInstalling
        case #selector(undoEdit(_:)),
             #selector(redoEdit(_:)):
            // Vditor owns its undo stack, and native AppKit cannot inspect it.
            // Keep the commands enabled whenever the editor is ready so the
            // keyboard shortcuts always reach the editor-side router.
            return editorReady
        case #selector(saveDocument(_:)),
             #selector(saveDocumentAs(_:)),
             #selector(exportHTML(_:)),
             #selector(exportPDF(_:)),
             #selector(printDocument(_:)),
             #selector(selectTheme(_:)),
             #selector(selectMode(_:)),
             #selector(toggleOutline(_:)),
             #selector(toggleFocusMode(_:)),
             #selector(toggleTypewriter(_:)),
             #selector(toggleWordCount(_:)),
             #selector(toggleSidebar(_:)),
             #selector(showOutlineSidebar(_:)),
             #selector(showFileTreeSidebar(_:)),
             #selector(toggleSourceMode(_:)),
             #selector(performFind(_:)),
             #selector(performReplace(_:)),
             #selector(findNextCommand(_:)),
             #selector(findPrevCommand(_:)),
             #selector(applyParagraph(_:)),
             #selector(zoomIn(_:)),
             #selector(zoomOut(_:)),
             #selector(actualSize(_:)),
             #selector(formatBold(_:)),
             #selector(formatItalic(_:)),
             #selector(formatStrikethrough(_:)),
             #selector(formatInlineCode(_:)),
             #selector(insertLink(_:)),
             #selector(pasteAsPlainText(_:)),
             #selector(copyAsMarkdown(_:)),
             #selector(copyAsHTML(_:)):
            return editorReady
        default:
            return true
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xff) / 255.0,
                  green: CGFloat((value >> 8) & 0xff) / 255.0,
                  blue: CGFloat(value & 0xff) / 255.0,
                  alpha: 1.0)
    }
}
