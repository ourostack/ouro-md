import AppKit
import SwiftUI

/// Owns one document window: its `AppModel`, the sidebar+editor split, the
/// centered title, chrome sync, the word-count popover, and unsaved-close
/// handling. Multiple instances give independent windows.
final class DocumentWindowController: NSObject, NSWindowDelegate {
    let model = AppModel()
    let window: NSWindow
    private var titleLabel: NSTextField?
    private var sidebarItem: NSSplitViewItem?
    private var wordCountPopover: NSPopover?

    /// `onBecomeKey` lets the app re-point menu state at the active window.
    var onBecomeKey: ((DocumentWindowController) -> Void)?
    /// `onClose` lets the app drop this controller so it isn't leaked.
    var onClose: ((DocumentWindowController) -> Void)?

    init(filePath: String?, selfTest: Bool, useAutosave: Bool) {
        let sidebarVC = NSHostingController(rootView: SidebarView(model: model))
        let editorVC = NSHostingController(rootView: EditorPane(model: model))

        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebar.minimumThickness = 190
        sidebar.maximumThickness = 380
        sidebar.canCollapse = true
        sidebar.isCollapsed = !model.sidebarVisible
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: editorVC))
        self.sidebarItem = sidebar

        let window = NSWindow(contentViewController: split)
        window.setContentSize(NSSize(width: 1080, height: 800))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = ""
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        self.window = window
        super.init()

        window.delegate = self
        installCenteredTitle()
        model.onChromeUpdate = { [weak self] in self?.syncChrome() }

        if useAutosave {
            window.setFrameAutosaveName("OuroMainWindow")
        } else {
            window.center()
        }

        if selfTest {
            window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
            window.orderFront(nil)
        }
        if let filePath { model.loadInitialFile(filePath) }
        syncChrome()
    }

    func show(cascadeFrom previous: NSWindow?) {
        if let previous {
            let topLeft = NSPoint(x: previous.frame.minX, y: previous.frame.maxY)
            window.cascadeTopLeft(from: topLeft)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func syncChrome() {
        // The centered label owns the filename; keep the system title empty so it
        // doesn't render a second (left-aligned) copy next to the traffic lights.
        window.title = ""
        window.isDocumentEdited = model.isDirty
        window.appearance = NSAppearance(named: model.theme.uiMode == "dark" ? .darkAqua : .aqua)
        if let background = NSColor(hex: model.theme.backgroundHex) { window.backgroundColor = background }
        titleLabel?.stringValue = model.windowTitle + (model.isDirty ? " — Edited" : "")
        MenuBuilder.refreshDynamicState(model: model)
    }

    private func installCenteredTitle() {
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        let label = PassthroughTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        titlebar.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: titlebar.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: titlebar.widthAnchor, multiplier: 0.6)
        ])
        titleLabel = label
    }

    func toggleSidebar() {
        guard let sidebarItem else { return }
        let willShow = sidebarItem.isCollapsed
        sidebarItem.animator().isCollapsed = !willShow
        model.setSidebarVisible(willShow)
    }

    func revealSidebar(mode: SidebarMode) {
        model.setSidebarMode(mode)
        if let sidebarItem, sidebarItem.isCollapsed {
            sidebarItem.animator().isCollapsed = false
            model.setSidebarVisible(true)
        }
    }

    func toggleWordCount(_ sender: Any?) {
        if let popover = wordCountPopover, popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let contentView = window.contentView else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: WordCountView(model: model))
        let anchor = NSRect(x: contentView.bounds.maxX - 80, y: 0, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: contentView, preferredEdge: .maxY)
        wordCountPopover = popover
    }

    func printDocument() {
        model.printDocument()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        MenuBuilder.refreshDynamicState(model: model)
        onBecomeKey?(self)
    }

    func windowWillClose(_ notification: Notification) {
        model.teardown()
        onClose?(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \(model.windowTitle)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.performSave { ok in if ok { sender.close() } }
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}
