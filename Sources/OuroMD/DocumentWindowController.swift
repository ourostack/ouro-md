import AppKit
import Combine
import OuroMDAppSupport
import SwiftUI

/// Owns one document window: its `AppModel`, the sidebar+editor split, the
/// centered title, chrome sync, the status bar, and unsaved-close
/// handling. Multiple instances give independent windows.
@MainActor
final class DocumentWindowController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    let model = AppModel()
    let window: NSWindow
    private var sidebarItem: NSSplitViewItem?
    private var truthAccessory: NSTitlebarAccessoryViewController?
    private var truthButton: DocumentTruthTitleButton?
    private var renamePopover: NSPopover?
    private var renameField: NSTextField?
    var renamePresentationHandler: (() -> Void)?
    /// Test seam: overrides what a title click does (defaults to the Open panel).
    var openDocumentFromTitleClickHandler: (() -> Void)?

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
        // Click the filename to open a document (same as File ▸ Open), while the
        // window subclass still distinguishes a click from a title-bar drag.
        window.onTitleClicked = { [weak self] in self?.openDocumentFromTitleClick() }
        window.titleHitView = { [weak self] in self?.nativeTitleField() }
        // Native fixed-size title-bar document-status glyph. A SwiftUI `Menu`
        // here previously let hidden accessibility text affect title-bar layout,
        // producing the malformed white chip/artifacts seen in 0.9.82.
        let truthAccessory = NSTitlebarAccessoryViewController()
        let truthButton = DocumentTruthTitleButton(model: model)
        truthAccessory.view = truthButton
        truthAccessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(truthAccessory)
        self.truthAccessory = truthAccessory
        self.truthButton = truthButton
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
        truthButton?.refresh()
        truthAccessory?.isHidden = model.focusMode
        MenuBuilder.refreshDynamicState(model: model)
    }

    // MARK: - Title click / open

    /// A plain click on the filename opens the standard Open panel (same as
    /// File ▸ Open), reusing the existing unsaved-changes guard. Rename stays a
    /// menu command so a title click can never risk an accidental rename.
    func openDocumentFromTitleClick() {
        if let openDocumentFromTitleClickHandler {
            openDocumentFromTitleClickHandler()
            return
        }
        model.openPanel()
    }

    // MARK: - Rename

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

    /// Finds the AppKit-drawn title text field so the popover can anchor on the title.
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

    func toggleStatusBar() {
        model.statusBarVisible.toggle()
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

/// Fixed-size native title-bar button for document truth. Keeping this surface
/// entirely in AppKit guarantees that accessibility metadata never participates
/// in visual layout.
@MainActor
final class DocumentTruthTitleButton: NSButton {
    static let controlSize = NSSize(width: 24, height: 24)

    private weak var model: AppModel?
    private var truthCancellable: AnyCancellable?

    override var intrinsicContentSize: NSSize { Self.controlSize }

    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: Self.controlSize))
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .inline
        focusRingType = .none
        target = self
        action = #selector(showDocumentTruthMenu(_:))
        setAccessibilityLabel("File status")
        truthCancellable = model.$documentTruth.sink { [weak self] snapshot in
            self?.refresh(snapshot: snapshot)
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        guard let model else { return }
        refresh(snapshot: model.documentTruth)
    }

    func makeMenu() -> NSMenu {
        guard let model else { return NSMenu() }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem(
            "Reveal in Finder",
            systemImage: "folder",
            action: #selector(revealInFinder(_:)),
            enabled: model.documentTruth.canCopyPath
        ))
        menu.addItem(menuItem(
            "Copy File Path",
            systemImage: "doc.on.clipboard",
            action: #selector(copyFilePath(_:)),
            enabled: model.documentTruth.canCopyPath
        ))
        menu.addItem(menuItem(
            "Copy Relative Path",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            action: #selector(copyRelativePath(_:)),
            enabled: model.documentTruth.canCopyRelativePath
        ))
        menu.addItem(menuItem(
            "Copy Git Diff Command",
            systemImage: "terminal",
            action: #selector(copyGitDiffCommand(_:)),
            enabled: model.documentTruth.canCopyGitDiffCommand
        ))
        return menu
    }

    private func refresh(snapshot: DocumentTruthSnapshot) {
        guard let model else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image = NSImage(
            systemSymbolName: Self.iconName(for: snapshot.state),
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        contentTintColor = .secondaryLabelColor
        let displayLabel: String
        if model.deletedOnDisk {
            displayLabel = "Deleted on disk"
        } else if model.isDirty {
            displayLabel = model.currentURL == nil
                ? "Unsaved changes"
                : "\(snapshot.label) · unsaved"
        } else {
            displayLabel = snapshot.label
        }
        toolTip = "File status · \(displayLabel)"
        setAccessibilityValue(displayLabel)
        setAccessibilityHelp(toolTip)
    }

    private func menuItem(
        _ title: String,
        systemImage: String,
        action: Selector,
        enabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        item.isEnabled = enabled
        return item
    }

    @objc private func showDocumentTruthMenu(_ sender: NSButton) {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.minY), in: self)
    }

    @objc private func revealInFinder(_ sender: Any?) {
        model?.revealCurrentFileInFinder()
    }

    @objc private func copyFilePath(_ sender: Any?) {
        model?.copyCurrentFilePath()
    }

    @objc private func copyRelativePath(_ sender: Any?) {
        model?.copyCurrentFileRelativePath()
    }

    @objc private func copyGitDiffCommand(_ sender: Any?) {
        model?.copyCurrentGitDiffCommand()
    }

    private static func iconName(for state: DocumentTruthState) -> String {
        switch state {
        case .untitled:
            return "doc"
        case .unavailable:
            return "exclamationmark.triangle"
        case .gitUnavailable:
            return "questionmark.folder"
        case .notInGit:
            return "doc.text"
        case .untracked:
            return "plus.circle"
        case .trackedClean:
            return "checkmark.circle"
        case .trackedModified:
            return "pencil.circle"
        case .trackedStaged:
            return "tray.and.arrow.up"
        case .trackedMixed:
            return "arrow.triangle.2.circlepath"
        }
    }
}

/// A document window that observes native title-field clicks without consuming
/// AppKit's events. `mouseDown(with:)` is not reached when the click belongs to
/// the system title text field; `sendEvent(_:)` sees every event before AppKit
/// dispatches it to that subview.
final class DocumentWindow: NSWindow {
    var onTitleClicked: (() -> Void)?
    var titleHitView: (() -> NSView?)?
    private var titleClickStart: NSPoint?

    override func sendEvent(_ event: NSEvent) {
        var openAfterDispatch = false
        switch event.type {
        case .leftMouseDown:
            titleClickStart = isPlainTitleClick(event) ? event.locationInWindow : nil
        case .leftMouseDragged:
            if let start = titleClickStart,
               TitleClickGesture.isDrag(
                   deltaX: event.locationInWindow.x - start.x,
                   deltaY: event.locationInWindow.y - start.y
               ) {
                titleClickStart = nil
            }
        case .leftMouseUp:
            openAfterDispatch = titleClickStart != nil && titleContains(event.locationInWindow)
            titleClickStart = nil
        default:
            break
        }
        // Preserve native title-bar dragging, double-click behavior, proxy-icon
        // behavior, and traffic-light handling. We only observe the event stream.
        super.sendEvent(event)
        if openAfterDispatch { onTitleClicked?() }
    }

    private func isPlainTitleClick(_ event: NSEvent) -> Bool {
        guard event.clickCount == 1 else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return modifiers.isEmpty && titleContains(event.locationInWindow)
    }

    private func titleContains(_ point: NSPoint) -> Bool {
        guard let titleView = titleHitView?() else { return false }
        return titleView.convert(titleView.bounds, to: nil).contains(point)
    }
}

enum TitleClickGesture {
    static let dragThresholdSquared: CGFloat = 9

    static func isDrag(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        (deltaX * deltaX + deltaY * deltaY) >= dragThresholdSquared
    }
}
