import AppKit
import WebKit
import XCTest
@testable import OuroMD

@MainActor
final class UndoRedoRoutingTests: XCTestCase {
    func testUndoAndRedoMenuItemsTargetNativeAppDelegateSelectors() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        MenuBuilder.install(into: app, target: delegate)

        let editMenu = app.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Edit" }
        let undo = editMenu?.item(withTitle: "Undo")
        let redo = editMenu?.item(withTitle: "Redo")
        XCTAssertEqual(undo?.action, #selector(AppDelegate.undoEdit(_:)))
        XCTAssertTrue(undo?.target === delegate)
        XCTAssertEqual(redo?.action, #selector(AppDelegate.redoEdit(_:)))
        XCTAssertTrue(redo?.target === delegate)
        XCTAssertEqual(redo?.keyEquivalent, "z")
        XCTAssertTrue(redo?.keyEquivalentModifierMask.contains(.command) == true)
        XCTAssertTrue(redo?.keyEquivalentModifierMask.contains(.shift) == true)
    }

    func testViewSearchMenuTargetsSidebarSearch() {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        defer { app.mainMenu = previousMenu }
        let delegate = AppDelegate()

        MenuBuilder.install(into: app, target: delegate)

        let viewMenu = app.mainMenu?.items.compactMap(\.submenu).first { $0.title == "View" }
        let search = viewMenu?.item(withTitle: "Search")
        XCTAssertEqual(search?.action, #selector(AppDelegate.showSearchSidebar(_:)))
        XCTAssertTrue(search?.target === delegate)
        XCTAssertEqual(search?.keyEquivalent, "f")
        XCTAssertTrue(search?.keyEquivalentModifierMask.contains(.command) == true)
        XCTAssertTrue(search?.keyEquivalentModifierMask.contains(.shift) == true)
    }

    func testCommandPaletteMenuUsesStandardSearchableActionShortcut() {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        defer { app.mainMenu = previousMenu }
        let delegate = AppDelegate()

        MenuBuilder.install(into: app, target: delegate)

        let editMenu = app.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Edit" }
        let palette = editMenu?.item(withTitle: "Command Palette…")
        XCTAssertEqual(palette?.action, #selector(AppDelegate.showCommandPalette(_:)))
        XCTAssertTrue(palette?.target === delegate)
        XCTAssertEqual(palette?.keyEquivalent, "p")
        XCTAssertTrue(palette?.keyEquivalentModifierMask.contains(.command) == true)
        XCTAssertTrue(palette?.keyEquivalentModifierMask.contains(.shift) == true)
    }

    func testHelpMenuSurfacesKeyboardShortcutsReference() {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        defer { app.mainMenu = previousMenu }
        let delegate = AppDelegate()

        MenuBuilder.install(into: app, target: delegate)

        let helpMenu = app.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Help" }
        let shortcuts = helpMenu?.item(withTitle: "Keyboard Shortcuts…")
        XCTAssertEqual(shortcuts?.action, #selector(AppDelegate.showKeyboardShortcuts(_:)))
        XCTAssertTrue(shortcuts?.target === delegate)
        XCTAssertEqual(shortcuts?.keyEquivalent, "/")
        XCTAssertTrue(shortcuts?.keyEquivalentModifierMask.contains(.command) == true)
        XCTAssertTrue(shortcuts?.keyEquivalentModifierMask.contains(.shift) == true)
    }

    func testHelpMenuSurfacesVersionAndUpdateCommands() {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        defer { app.mainMenu = previousMenu }
        let delegate = AppDelegate()

        MenuBuilder.install(into: app, target: delegate)

        let helpMenu = app.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Help" }
        XCTAssertEqual(helpMenu?.item(withTitle: "What's New")?.action, #selector(AppDelegate.showWhatsNew(_:)))
        XCTAssertEqual(helpMenu?.item(withTitle: "Check for Updates…")?.action, #selector(AppDelegate.checkForUpdates(_:)))
        XCTAssertEqual(helpMenu?.item(withTitle: "Open Latest Release")?.action, #selector(AppDelegate.openLatestReleasePage(_:)))
    }

    func testShortcutParserRecognizesMacUndoRedoKeystrokes() {
        XCTAssertEqual(
            UndoRedoCommandRouter.command(for: keyEvent("z", modifiers: [.command])),
            .undo
        )
        XCTAssertEqual(
            UndoRedoCommandRouter.command(for: keyEvent("Z", modifiers: [.command, .shift])),
            .redo
        )
        XCTAssertEqual(
            UndoRedoCommandRouter.command(for: keyEvent("y", modifiers: [.command])),
            .redo
        )
    }

    func testCommandYRedoUsesEditorFallbackWhenFocusIsInWebEditor() {
        let event = keyEvent("y", modifiers: [.command])
        let command = UndoRedoCommandRouter.command(for: event)
        var undoFallbackCalls = 0
        var redoFallbackCalls = 0

        let handled = UndoRedoCommandRouter.perform(
            command!,
            firstResponder: nil,
            editorIsReady: true,
            editorUndo: { undoFallbackCalls += 1 },
            editorRedo: { redoFallbackCalls += 1 }
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(undoFallbackCalls, 0)
        XCTAssertEqual(redoFallbackCalls, 1)
    }

    func testShortcutParserRejectsModifiedNonUndoRedoKeystrokes() {
        XCTAssertNil(UndoRedoCommandRouter.command(for: keyEvent("z", modifiers: [.command, .option])))
        XCTAssertNil(UndoRedoCommandRouter.command(for: keyEvent("z", modifiers: [.command, .control])))
        XCTAssertNil(UndoRedoCommandRouter.command(for: keyEvent("x", modifiers: [.command])))
    }

    func testShortcutMonitorHandlesNSApplicationSendEventBeforeMenuDispatch() {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        let responder = FirstResponderView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        content.addSubview(responder)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(responder))

        let menu = NSMenu()
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let redo = editMenu.addItem(withTitle: "Redo",
                                    action: #selector(FirstResponderView.unwantedRedo(_:)),
                                    keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = responder
        edit.submenu = editMenu
        menu.addItem(edit)
        app.mainMenu = menu

        var handledCommand: UndoRedoCommand?
        let monitor = UndoRedoShortcutMonitor { command, firstResponder in
            handledCommand = command
            return true
        }
        monitor.install()
        defer {
            monitor.invalidate()
            app.mainMenu = previousMenu
            window.orderOut(nil)
        }

        app.sendEvent(keyEvent("Z", modifiers: [.command, .shift], windowNumber: window.windowNumber))

        XCTAssertEqual(handledCommand, .redo)
        XCTAssertEqual(responder.unwantedRedoCount, 0)
    }

    func testMenuValidationDisablesEditorOnlyCommandsWithoutAWindow() {
        let delegate = AppDelegate()

        let save = NSMenuItem(title: "Save", action: #selector(AppDelegate.saveDocument(_:)), keyEquivalent: "")
        let rename = NSMenuItem(title: "Rename", action: #selector(AppDelegate.renameDocument(_:)), keyEquivalent: "")
        let undo = NSMenuItem(title: "Undo", action: #selector(AppDelegate.undoEdit(_:)), keyEquivalent: "")
        let search = NSMenuItem(title: "Search", action: #selector(AppDelegate.showSearchSidebar(_:)), keyEquivalent: "")
        let palette = NSMenuItem(title: "Command Palette", action: #selector(AppDelegate.showCommandPalette(_:)), keyEquivalent: "")

        XCTAssertFalse(delegate.validateMenuItem(save))
        XCTAssertFalse(delegate.validateMenuItem(rename))
        XCTAssertFalse(delegate.validateMenuItem(undo))
        XCTAssertFalse(delegate.validateMenuItem(search))
        XCTAssertFalse(delegate.validateMenuItem(palette))
    }

    func testMenuValidationKeepsGlobalCommandsEnabledWithoutAWindow() {
        let delegate = AppDelegate()

        let new = NSMenuItem(title: "New", action: #selector(AppDelegate.newDocument(_:)), keyEquivalent: "")
        let open = NSMenuItem(title: "Open", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "")
        let updates = NSMenuItem(title: "Check for Updates", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        let shortcuts = NSMenuItem(title: "Keyboard Shortcuts", action: #selector(AppDelegate.showKeyboardShortcuts(_:)), keyEquivalent: "")
        let whatsNew = NSMenuItem(title: "What's New", action: #selector(AppDelegate.showWhatsNew(_:)), keyEquivalent: "")
        let release = NSMenuItem(title: "Open Latest Release", action: #selector(AppDelegate.openLatestReleasePage(_:)), keyEquivalent: "")
        let about = NSMenuItem(title: "About", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")

        XCTAssertTrue(delegate.validateMenuItem(new))
        XCTAssertTrue(delegate.validateMenuItem(open))
        XCTAssertTrue(delegate.validateMenuItem(updates))
        XCTAssertTrue(delegate.validateMenuItem(shortcuts))
        XCTAssertTrue(delegate.validateMenuItem(whatsNew))
        XCTAssertTrue(delegate.validateMenuItem(release))
        XCTAssertTrue(delegate.validateMenuItem(about))
    }

    func testMenuValidationChecksRecentItemsAndDefaults() {
        let delegate = AppDelegate()

        let recent = NSMenuItem(title: "Recent", action: #selector(AppDelegate.openRecent(_:)), keyEquivalent: "")
        XCTAssertFalse(delegate.validateMenuItem(recent))
        recent.representedObject = URL(fileURLWithPath: "/tmp/example.md")
        XCTAssertTrue(delegate.validateMenuItem(recent))

        let clearRecent = NSMenuItem(title: "Clear Recent", action: #selector(AppDelegate.clearRecentDocuments(_:)), keyEquivalent: "")
        delegate.recentDocumentURLsProvider = { [] }
        XCTAssertFalse(delegate.validateMenuItem(clearRecent))
        delegate.recentDocumentURLsProvider = { [URL(fileURLWithPath: "/tmp/example.md")] }
        XCTAssertTrue(delegate.validateMenuItem(clearRecent))

        let unknown = NSMenuItem(title: "Unknown", action: Selector(("unknownCommand:")), keyEquivalent: "")
        XCTAssertTrue(delegate.validateMenuItem(unknown))
    }

    func testRecentMenuDelegateUsesInjectedRecentProvider() {
        let delegate = AppDelegate()
        let recentURL = URL(fileURLWithPath: "/tmp/injected-recent.md")
        let menu = NSMenu(title: "Open Recent")
        let recentDelegate = RecentMenuDelegate(target: delegate) { [recentURL] in [recentURL] }

        recentDelegate.menuNeedsUpdate(menu)

        XCTAssertEqual(menu.items.first?.title, "injected-recent.md")
        XCTAssertEqual(menu.items.first?.representedObject as? URL, recentURL)
        XCTAssertTrue(menu.items.first?.target === delegate)
        XCTAssertEqual(menu.items.last?.title, "Clear Menu")
    }

    func testRecentMenuDelegateShowsEmptyStateFromInjectedProvider() {
        let delegate = AppDelegate()
        let menu = NSMenu(title: "Open Recent")
        let recentDelegate = RecentMenuDelegate(target: delegate) { [] }

        recentDelegate.menuNeedsUpdate(menu)

        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items.first?.title, "No Recent Documents")
        XCTAssertFalse(menu.items.first?.isEnabled ?? true)
    }

    func testClearRecentDocumentsUsesInjectedHandler() {
        let delegate = AppDelegate()
        var cleared = false
        delegate.clearRecentDocumentsHandler = { _ in cleared = true }

        delegate.clearRecentDocuments(nil)

        XCTAssertTrue(cleared)
    }

    func testUndoDoesNotFallThroughWhenNativeTextViewHasEmptyStack() {
        let manager = RecordingUndoManager()
        let textView = NativeTextView(undoManager: manager)
        var fallbackCount = 0

        let handledNative = UndoRedoCommandRouter.performUndo(firstResponder: textView) {
            fallbackCount += 1
        }

        XCTAssertTrue(handledNative)
        XCTAssertEqual(manager.undoCalls, 0)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testRedoDoesNotFallThroughWhenNativeTextViewHasEmptyStack() {
        let manager = RecordingUndoManager()
        let textView = NativeTextView(undoManager: manager)
        var fallbackCount = 0

        let handledNative = UndoRedoCommandRouter.performRedo(firstResponder: textView) {
            fallbackCount += 1
        }

        XCTAssertTrue(handledNative)
        XCTAssertEqual(manager.redoCalls, 0)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testUndoAndRedoUseNativeTextViewManagerWhenAvailable() {
        let manager = RecordingUndoManager(canUndo: true, canRedo: true)
        let textView = NativeTextView(undoManager: manager)
        var fallbackCount = 0

        XCTAssertTrue(UndoRedoCommandRouter.performUndo(firstResponder: textView) { fallbackCount += 1 })
        XCTAssertTrue(UndoRedoCommandRouter.performRedo(firstResponder: textView) { fallbackCount += 1 })

        XCTAssertEqual(manager.undoCalls, 1)
        XCTAssertEqual(manager.redoCalls, 1)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testUndoAndRedoFallBackForTextViewsInsideWebView() {
        let manager = RecordingUndoManager(canUndo: true, canRedo: true)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        let textView = NativeTextView(undoManager: manager)
        webView.addSubview(textView)
        var undoFallbackCount = 0
        var redoFallbackCount = 0

        XCTAssertFalse(UndoRedoCommandRouter.performUndo(firstResponder: textView) { undoFallbackCount += 1 })
        XCTAssertFalse(UndoRedoCommandRouter.performRedo(firstResponder: textView) { redoFallbackCount += 1 })

        XCTAssertEqual(manager.undoCalls, 0)
        XCTAssertEqual(manager.redoCalls, 0)
        XCTAssertEqual(undoFallbackCount, 1)
        XCTAssertEqual(redoFallbackCount, 1)
    }

    func testUndoAndRedoFallBackWhenResponderIsNotNativeTextView() {
        let responder = NSResponder()
        var undoFallbackCount = 0
        var redoFallbackCount = 0

        XCTAssertFalse(UndoRedoCommandRouter.performUndo(firstResponder: responder) { undoFallbackCount += 1 })
        XCTAssertFalse(UndoRedoCommandRouter.performRedo(firstResponder: responder) { redoFallbackCount += 1 })

        XCTAssertEqual(undoFallbackCount, 1)
        XCTAssertEqual(redoFallbackCount, 1)
    }
}

private func keyEvent(_ key: String, modifiers: NSEvent.ModifierFlags, windowNumber: Int = 0) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown,
                     location: .zero,
                     modifierFlags: modifiers,
                     timestamp: 0,
                     windowNumber: windowNumber,
                     context: nil,
                     characters: key,
                     charactersIgnoringModifiers: key.lowercased(),
                     isARepeat: false,
                     keyCode: key.lowercased() == "y" ? 16 : 6)!
}

private final class FirstResponderView: NSView {
    private(set) var unwantedRedoCount = 0

    override var acceptsFirstResponder: Bool { true }

    @objc func unwantedRedo(_ sender: Any?) {
        unwantedRedoCount += 1
    }
}

private final class NativeTextView: NSTextView {
    private var testUndoManager: UndoManager

    init(undoManager: UndoManager) {
        self.testUndoManager = undoManager
        super.init(frame: .zero, textContainer: nil)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        self.testUndoManager = UndoManager()
        super.init(frame: frameRect, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable in tests")
    }

    override var undoManager: UndoManager? { testUndoManager }
}

private final class RecordingUndoManager: UndoManager {
    private let canUndoValue: Bool
    private let canRedoValue: Bool
    private(set) var undoCalls = 0
    private(set) var redoCalls = 0

    init(canUndo: Bool = false, canRedo: Bool = false) {
        self.canUndoValue = canUndo
        self.canRedoValue = canRedo
        super.init()
    }

    override var canUndo: Bool { canUndoValue }
    override var canRedo: Bool { canRedoValue }

    override func undo() {
        undoCalls += 1
    }

    override func redo() {
        redoCalls += 1
    }
}
