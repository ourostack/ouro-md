import AppKit
import SwiftUI

/// Owns one document window: its `AppModel`, the sidebar+editor split, the
/// centered title, chrome sync, the word-count popover, and unsaved-close
/// handling. Multiple instances give independent windows.
@MainActor
final class DocumentWindowController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    let model = AppModel()
    let window: NSWindow
    private var sidebarItem: NSSplitViewItem?
    private var wordCountPopover: NSPopover?
    private var renamePopover: NSPopover?
    private var renameField: NSTextField?
    var openDocumentFromTitleClickHandler: (() -> Void)?
    var renamePresentationHandler: (() -> Void)?

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

        let window = DocumentWindow(contentViewController: split)
        window.setContentSize(NSSize(width: 1080, height: 800))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        self.window = window
        super.init()

        window.delegate = self
        // Click the title (or its proxy icon) to open a document, while the
        // window subclass still distinguishes clicks from title-bar drags.
        window.onTitleClicked = { [weak self] in self?.openDocumentFromTitleClick() }
        window.titleHitView = { [weak self] in self?.nativeTitleField() }
        model.onChromeUpdate = { [weak self] in
            Task { @MainActor in self?.syncChrome() }
        }

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
        // Native document chrome: the system draws the title (and, when the file
        // exists on disk, a draggable proxy icon). Left-aligned in windowed mode
        // and full screen, matching every other macOS document app.
        window.title = model.windowTitle
        // VSCode-style deleted marker: a subtitle beside the filename when the
        // file has been removed/moved out from under us (the buffer is kept).
        window.subtitle = model.deletedOnDisk ? "deleted" : ""
        window.representedURL = model.currentURL
        window.isDocumentEdited = model.isDirty
        window.appearance = NSAppearance(named: model.theme.uiMode == "dark" ? .darkAqua : .aqua)
        if let background = NSColor(hex: model.theme.backgroundHex) { window.backgroundColor = background }
        MenuBuilder.refreshDynamicState(model: model)
    }

    // MARK: - Title click / rename

    func openDocumentFromTitleClick() {
        if let handler = openDocumentFromTitleClickHandler {
            handler()
            return
        }
        model.openPanel()
    }

    /// Presents an inline rename popover anchored on the title. Untitled
    /// documents have no file yet, so we route to Save As — that panel is the
    /// "name this document" affordance for an unsaved buffer.
    func presentRename() {
        if let renamePresentationHandler {
            renamePresentationHandler()
            return
        }
        guard model.currentURL != nil else { model.saveAs(); return }
        if let existing = renamePopover { existing.close(); return }

        let field = NSTextField(string: model.windowTitle)
        field.frame = NSRect(x: 12, y: 11, width: 256, height: 22)
        field.lineBreakMode = .byTruncatingMiddle
        field.usesSingleLineMode = true
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(renameFieldCommitted(_:))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
        container.addSubview(field)
        let vc = NSViewController()
        vc.view = container

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        popover.delegate = self
        renamePopover = popover
        renameField = field

        let anchor = nativeTitleField() ?? window.standardWindowButton(.closeButton)?.superview ?? window.contentView!
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)

        window.makeFirstResponder(field)
        // Pre-select the base name (without the extension), like Finder's rename.
        if let editor = field.currentEditor() {
            let full = field.stringValue as NSString
            let ext = full.pathExtension as NSString
            let baseLength = full.length - (ext.length == 0 ? 0 : ext.length + 1)
            editor.selectedRange = NSRange(location: 0, length: max(0, baseLength))
        }
    }

    @objc private func renameFieldCommitted(_ sender: NSTextField) {
        applyRename(sender.stringValue)
    }

    private func applyRename(_ newName: String) {
        guard renameField != nil else { return }
        cancelRename()
        guard newName != model.windowTitle else { return }
        if let message = model.renameCurrentFile(to: newName) {
            let alert = NSAlert()
            alert.messageText = "Couldn’t rename the file"
            alert.informativeText = message
            alert.beginSheetModal(for: window) { _ in }
        }
    }

    /// Tears down the rename popover without renaming. Used for Escape, clicking
    /// away, or the app deactivating — only Return (renameFieldCommitted) renames,
    /// so an unfinished edit can never silently rename the user's file.
    private func cancelRename() {
        let popover = renamePopover
        renameField = nil
        renamePopover = nil
        popover?.delegate = nil
        popover?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        // Any dismissal that wasn't Return is a cancel.
        if renameField != nil { cancelRename() }
    }

    /// Finds the AppKit-drawn title text field so the popover (and the window's
    /// click hit-test) can anchor exactly on the title.
    private func nativeTitleField() -> NSTextField? {
        guard !window.title.isEmpty,
              let titlebar = window.standardWindowButton(.closeButton)?.superview else { return nil }
        func search(_ view: NSView) -> NSTextField? {
            for sub in view.subviews {
                if let label = sub as? NSTextField, label.stringValue == window.title { return label }
                if let found = search(sub) { return found }
            }
            return nil
        }
        return search(titlebar)
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
        guard model.isDirty || model.deletedOnDisk else { return true }
        let alert = NSAlert()
        if model.deletedOnDisk {
            alert.messageText = "“\(model.windowTitle)” was deleted on disk."
            alert.informativeText = "Save to recreate the file, or close to discard the kept copy."
        } else {
            alert.messageText = "Do you want to save the changes made to \(model.windowTitle)?"
            alert.informativeText = "Your changes will be lost if you don't save them."
        }
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

/// A document window whose title click is app-defined. AppKit only provides
/// richer title actions to `NSDocument`-based windows, so we detect a click on
/// the title text ourselves while preserving the ability to drag the window by
/// its title bar (a drag past a small threshold moves the window instead).
final class DocumentWindow: NSWindow {
    var onTitleClicked: (() -> Void)?
    var titleHitView: (() -> NSView?)?

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1,
              let titleView = titleHitView?() else {
            super.mouseDown(with: event)
            return
        }
        let titleRect = titleView.convert(titleView.bounds, to: nil)
        guard titleRect.contains(event.locationInWindow) else {
            super.mouseDown(with: event)
            return
        }

        // Distinguish a click from a drag. Track the
        // mouse until it is released; treat motion past a few points as a drag.
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin
        var didDrag = false
        trackingLoop: while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
            case .leftMouseUp:
                break trackingLoop
            case .leftMouseDragged:
                let now = NSEvent.mouseLocation
                let dx = now.x - startMouse.x
                let dy = now.y - startMouse.y
                if !didDrag && !TitleClickGesture.isDrag(deltaX: dx, deltaY: dy) { continue }
                didDrag = true
                setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
            default:
                break
            }
        }
        if !didDrag { onTitleClicked?() }
    }
}

enum TitleClickGesture {
    static let dragThresholdSquared: CGFloat = 9

    static func isDrag(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        (deltaX * deltaX + deltaY * deltaY) >= dragThresholdSquared
    }
}
