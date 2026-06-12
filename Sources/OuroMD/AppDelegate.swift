import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var initialFilePath: String?
    let model = AppModel()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: ContentView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 960, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.delegate = self
        window.setFrameAutosaveName("OuroMainWindow")
        window.center()
        self.window = window

        model.onChromeUpdate = { [weak self] in self?.syncChrome() }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let path = initialFilePath { model.loadInitialFile(path) }
        syncChrome()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.open(url: url) }
    }

    private func syncChrome() {
        guard let window else { return }
        window.title = model.windowTitle
        window.isDocumentEdited = model.isDirty
        window.representedURL = model.currentURL
        MenuBuilder.refreshDynamicState(model: model)
    }

    // MARK: - Unsaved-changes handling

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        switch unsavedAlert() {
        case .save:
            model.performSave { ok in if ok { sender.close() } }
            return false
        case .dontSave:
            return true
        case .cancel:
            return false
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isDirty else { return .terminateNow }
        switch unsavedAlert() {
        case .save:
            model.performSave { ok in NSApp.reply(toApplicationShouldTerminate: ok) }
            return .terminateLater
        case .dontSave:
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }

    private enum SaveChoice { case save, dontSave, cancel }

    private func unsavedAlert() -> SaveChoice {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \(model.windowTitle)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .dontSave
        default: return .cancel
        }
    }

    // MARK: - Menu actions

    @objc func newDocument(_ sender: Any?) { model.newDocument() }
    @objc func openDocument(_ sender: Any?) { model.openPanel() }
    @objc func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { model.open(url: url) }
    }
    @objc func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }
    @objc func saveDocument(_ sender: Any?) { model.save() }
    @objc func saveDocumentAs(_ sender: Any?) { model.saveAs() }
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
    @objc func zoomIn(_ sender: Any?) { model.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { model.zoomOut() }
    @objc func actualSize(_ sender: Any?) { model.actualSize() }

    @objc func formatBold(_ sender: Any?) { model.format("bold") }
    @objc func formatItalic(_ sender: Any?) { model.format("italic") }
    @objc func formatStrikethrough(_ sender: Any?) { model.format("strike") }
    @objc func formatInlineCode(_ sender: Any?) { model.format("code") }
    @objc func insertLink(_ sender: Any?) { model.format("link") }

    @objc func openProjectPage(_ sender: Any?) {
        if let url = URL(string: "https://github.com/ourostack/ouro-md") {
            NSWorkspace.shared.open(url)
        }
    }
}
