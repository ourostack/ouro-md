import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var initialFilePath: String?
    private var controllers: [DocumentWindowController] = []
    private lazy var fallbackModel = AppModel()

    private var isSelfTest: Bool { ProcessInfo.processInfo.environment["OURO_SELFTEST"] == "1" }

    /// The window the user is acting on (key/main), else the last opened.
    var frontController: DocumentWindowController? {
        if let key = NSApp.keyWindow, let c = controllers.first(where: { $0.window === key }) { return c }
        if let main = NSApp.mainWindow, let c = controllers.first(where: { $0.window === main }) { return c }
        return controllers.last
    }
    /// Forwarding accessors keep every menu action targeting the active window.
    var model: AppModel { frontController?.model ?? controllers.first?.model ?? fallbackModel }
    var window: NSWindow! { frontController?.window }
    func syncChrome() { frontController?.syncChrome() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DocumentWindowController(filePath: initialFilePath, selfTest: isSelfTest, useAutosave: true)
        controllers.append(controller)
        if isSelfTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { exit(0) }
            return
        }
        controller.show(cascadeFrom: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
        controllers.append(controller)
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
        controllers.append(controller)
        controller.show(cascadeFrom: prev)
    }

    @objc func printDocument(_ sender: Any?) { frontController?.printDocument() }

    private var prefsWindow: NSWindow?
    @objc func showPreferences(_ sender: Any?) {
        if prefsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Preferences"
            w.isReleasedWhenClosed = false
            w.center()
            prefsWindow = w
        }
        // Re-bind to the active window's model each time it opens.
        prefsWindow?.contentViewController = NSHostingController(rootView: PreferencesView(model: model))
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
            let group = DispatchGroup()
            for c in dirty { group.enter(); c.model.performSave { _ in group.leave() } }
            group.notify(queue: .main) { NSApp.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    // MARK: - Menu actions

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
}

/// A title label that never intercepts mouse events, so the titlebar it sits in
/// stays draggable (the click falls through to the window background).
final class PassthroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }
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
