import AppKit

/// Builds the native menu bar and keeps dynamic items (theme / mode / recent)
/// in sync with the current document state.
enum MenuBuilder {
    private static weak var themeMenu: NSMenu?
    private static weak var sourceModeItem: NSMenuItem?
    private static weak var focusModeItem: NSMenuItem?
    private static weak var typewriterItem: NSMenuItem?
    private static var recentDelegate: RecentMenuDelegate?

    @MainActor
    static func install(into app: NSApplication, target: AppDelegate) {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu(target: target))
        mainMenu.addItem(fileMenu(target: target))
        mainMenu.addItem(editMenu(target: target))
        mainMenu.addItem(paragraphMenu(target: target))
        mainMenu.addItem(formatMenu(target: target))
        mainMenu.addItem(viewMenu(target: target))
        mainMenu.addItem(themesMenu(target: target))
        let windowMenuItem = windowMenu()
        mainMenu.addItem(windowMenuItem)
        let helpMenuItem = helpMenu(target: target)
        mainMenu.addItem(helpMenuItem)

        app.mainMenu = mainMenu
        app.windowsMenu = windowMenuItem.submenu
        app.helpMenu = helpMenuItem.submenu

        refreshDynamicState(model: target.model)
    }

    @MainActor
    static func refreshDynamicState(model: AppModel) {
        themeMenu?.items.forEach {
            $0.state = ($0.representedObject as? String == model.themeID) ? .on : .off
        }
        sourceModeItem?.state = (model.mode == "sv") ? .on : .off
        focusModeItem?.state = model.focusMode ? .on : .off
        typewriterItem?.state = model.typewriter ? .on : .off
    }

    // MARK: - App menu

    private static func appMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()
        item.submenu = menu

        add(menu, "About Ouro MD", #selector(AppDelegate.showAbout(_:)), "", target)
        menu.addItem(.separator())
        let settings = add(menu, "Settings…", #selector(AppDelegate.showPreferences(_:)), ",", target)
        settings.keyEquivalentModifierMask = [.command]
        add(menu, "Check for Updates…", #selector(AppDelegate.checkForUpdates(_:)), "", target)
        add(menu, "Open Latest Release", #selector(AppDelegate.openLatestReleasePage(_:)), "", target)
        menu.addItem(.separator())

        let hide = menu.addItem(withTitle: "Hide Ouro MD",
                                action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = nil
        let hideOthers = menu.addItem(withTitle: "Hide Others",
                                      action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ouro MD",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item
    }

    // MARK: - File menu

    @MainActor
    private static func fileMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        item.submenu = menu

        add(menu, "New", #selector(AppDelegate.newDocument(_:)), "n", target)
        let newWindow = add(menu, "New Window", #selector(AppDelegate.newWindow(_:)), "n", target)
        newWindow.keyEquivalentModifierMask = [.command, .shift]
        add(menu, "Open…", #selector(AppDelegate.openDocument(_:)), "o", target)
        let openFolder = add(menu, "Open Folder…", #selector(AppDelegate.openFolder(_:)), "o", target)
        openFolder.keyEquivalentModifierMask = [.command, .shift]

        let openRecent = menu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        let delegate = RecentMenuDelegate(target: target) { [weak target] in
            target?.recentDocumentURLsProvider() ?? []
        }
        recentDelegate = delegate
        recentMenu.delegate = delegate
        openRecent.submenu = recentMenu

        menu.addItem(.separator())
        add(menu, "Save", #selector(AppDelegate.saveDocument(_:)), "s", target)
        let saveAs = add(menu, "Save As…", #selector(AppDelegate.saveDocumentAs(_:)), "s", target)
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        add(menu, "Rename…", #selector(AppDelegate.renameDocument(_:)), "", target)

        menu.addItem(.separator())
        let export = menu.addItem(withTitle: "Export", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: "Export")
        add(exportMenu, "HTML…", #selector(AppDelegate.exportHTML(_:)), "", target)
        add(exportMenu, "PDF…", #selector(AppDelegate.exportPDF(_:)), "", target)
        export.submenu = exportMenu

        add(menu, "Print…", #selector(AppDelegate.printDocument(_:)), "p", target)

        menu.addItem(.separator())
        let close = menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = nil
        return item
    }

    // MARK: - Edit menu (standard responder-chain actions)

    private static func editMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        item.submenu = menu

        let undo = add(menu, "Undo", #selector(AppDelegate.undoEdit(_:)), "z", target)
        _ = undo
        let redo = add(menu, "Redo", #selector(AppDelegate.redoEdit(_:)), "z", target)
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        standard(menu, "Cut", #selector(NSText.cut(_:)), "x")
        standard(menu, "Copy", #selector(NSText.copy(_:)), "c")
        standard(menu, "Paste", #selector(NSText.paste(_:)), "v")
        let pastePlain = add(menu, "Paste as Plain Text", #selector(AppDelegate.pasteAsPlainText(_:)), "v", target)
        pastePlain.keyEquivalentModifierMask = [.command, .shift]
        standard(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
        menu.addItem(.separator())
        let copyAs = menu.addItem(withTitle: "Copy as", action: nil, keyEquivalent: "")
        let copyAsMenu = NSMenu(title: "Copy as")
        copyAs.submenu = copyAsMenu
        add(copyAsMenu, "Rendered (HTML)", #selector(AppDelegate.copyAsHTML(_:)), "", target)
        add(copyAsMenu, "Plain Text", #selector(AppDelegate.copyAsPlainText(_:)), "", target)
        add(copyAsMenu, "Markdown", #selector(AppDelegate.copyAsMarkdown(_:)), "", target)

        menu.addItem(.separator())
        let palette = add(menu, "Command Palette…", #selector(AppDelegate.showCommandPalette(_:)), "p", target)
        palette.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        let find = menu.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        add(findMenu, "Find…", #selector(AppDelegate.performFind(_:)), "f", target)
        add(findMenu, "Replace…", #selector(AppDelegate.performReplace(_:)), "f", target).keyEquivalentModifierMask = [.command, .option]
        add(findMenu, "Find Next", #selector(AppDelegate.findNextCommand(_:)), "g", target)
        add(findMenu, "Find Previous", #selector(AppDelegate.findPrevCommand(_:)), "g", target).keyEquivalentModifierMask = [.command, .shift]
        find.submenu = findMenu
        return item
    }

    // MARK: - Format menu

    private static func formatMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Format")
        item.submenu = menu

        add(menu, "Bold", #selector(AppDelegate.formatBold(_:)), "b", target)
        add(menu, "Italic", #selector(AppDelegate.formatItalic(_:)), "i", target)
        let strike = add(menu, "Strikethrough", #selector(AppDelegate.formatStrikethrough(_:)), "s", target)
        strike.keyEquivalentModifierMask = [.command, .control]
        add(menu, "Inline Code", #selector(AppDelegate.formatInlineCode(_:)), "e", target)
        menu.addItem(.separator())
        add(menu, "Insert Link", #selector(AppDelegate.insertLink(_:)), "k", target)
        return item
    }

    // MARK: - View menu

    private static func viewMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")
        item.submenu = menu

        sourceModeItem = add(menu, "Source Code Mode", #selector(AppDelegate.toggleSourceMode(_:)), "/", target)

        menu.addItem(.separator())
        focusModeItem = add(menu, "Focus Mode", #selector(AppDelegate.toggleFocusMode(_:)), funcKey(NSF8FunctionKey), target)
        focusModeItem?.keyEquivalentModifierMask = []
        typewriterItem = add(menu, "Typewriter Mode", #selector(AppDelegate.toggleTypewriter(_:)), funcKey(NSF9FunctionKey), target)
        typewriterItem?.keyEquivalentModifierMask = []

        menu.addItem(.separator())
        let sidebarMI = add(menu, "Toggle Sidebar", #selector(AppDelegate.toggleSidebar(_:)), "l", target)
        sidebarMI.keyEquivalentModifierMask = [.command, .shift]
        let outlineMI = add(menu, "Outline", #selector(AppDelegate.showOutlineSidebar(_:)), "1", target)
        outlineMI.keyEquivalentModifierMask = [.command, .control]
        let fileTreeMI = add(menu, "File Tree", #selector(AppDelegate.showFileTreeSidebar(_:)), "3", target)
        fileTreeMI.keyEquivalentModifierMask = [.command, .control]
        let searchMI = add(menu, "Search", #selector(AppDelegate.showSearchSidebar(_:)), "f", target)
        searchMI.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        add(menu, "Toggle Word Count", #selector(AppDelegate.toggleWordCount(_:)), "", target)

        menu.addItem(.separator())
        let actual = add(menu, "Actual Size", #selector(AppDelegate.actualSize(_:)), "0", target)
        actual.keyEquivalentModifierMask = [.command, .shift]
        let zoomIn = add(menu, "Zoom In", #selector(AppDelegate.zoomIn(_:)), "=", target)
        zoomIn.keyEquivalentModifierMask = [.command, .shift]
        let zoomOut = add(menu, "Zoom Out", #selector(AppDelegate.zoomOut(_:)), "-", target)
        zoomOut.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        let fullScreen = menu.addItem(withTitle: "Enter Full Screen",
                                      action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        fullScreen.target = nil
        return item
    }

    // MARK: - Paragraph menu

    private static func paragraphMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Paragraph")
        item.submenu = menu

        for level in 1...6 {
            let heading = para(menu, "Heading \(level)", cmd: "h\(level)", key: "\(level)", target)
            heading.keyEquivalentModifierMask = [.command]
        }
        let body = para(menu, "Paragraph", cmd: "paragraph", key: "0", target)
        body.keyEquivalentModifierMask = [.command]

        menu.addItem(.separator())
        para(menu, "Ordered List", cmd: "ol", key: "", target)
        para(menu, "Unordered List", cmd: "ul", key: "", target)
        para(menu, "Task List", cmd: "task", key: "", target)
        para(menu, "Quote", cmd: "quote", key: "", target)

        menu.addItem(.separator())
        para(menu, "Code Fences", cmd: "codeblock", key: "", target)
        para(menu, "Table", cmd: "table", key: "", target)
        para(menu, "Math Block", cmd: "math", key: "", target)
        para(menu, "Horizontal Rule", cmd: "hr", key: "", target)
        return item
    }

    @discardableResult
    private static func para(_ menu: NSMenu, _ title: String, cmd: String, key: String, _ target: AppDelegate) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: #selector(AppDelegate.applyParagraph(_:)), keyEquivalent: key)
        item.target = target
        item.representedObject = cmd
        return item
    }

    // MARK: - Themes menu

    private static func themesMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Themes")
        item.submenu = menu
        for theme in ThemeStore.shared.themes {
            let entry = menu.addItem(withTitle: theme.displayName,
                                     action: #selector(AppDelegate.selectTheme(_:)), keyEquivalent: "")
            entry.target = target
            entry.representedObject = theme.id
        }
        themeMenu = menu
        return item
    }

    // MARK: - Window menu

    private static func windowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")
        item.submenu = menu
        let minimize = menu.addItem(withTitle: "Minimize",
                                    action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        minimize.target = nil
        let zoom = menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        zoom.target = nil
        return item
    }

    // MARK: - Help menu

    private static func helpMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")
        item.submenu = menu
        let shortcuts = add(menu, "Keyboard Shortcuts…", #selector(AppDelegate.showKeyboardShortcuts(_:)), "/", target)
        shortcuts.keyEquivalentModifierMask = [.command, .shift]
        add(menu, "What's New", #selector(AppDelegate.showWhatsNew(_:)), "", target)
        add(menu, "Check for Updates…", #selector(AppDelegate.checkForUpdates(_:)), "", target)
        add(menu, "Open Latest Release", #selector(AppDelegate.openLatestReleasePage(_:)), "", target)
        menu.addItem(.separator())
        add(menu, "Ouro MD on GitHub", #selector(AppDelegate.openProjectPage(_:)), "", target)
        add(menu, "Report an Issue", #selector(AppDelegate.reportIssue(_:)), "", target)
        return item
    }

    // MARK: - Builders

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                            _ key: String, _ target: AppDelegate) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    @discardableResult
    private static func standard(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = nil
        return item
    }

    private static func funcKey(_ code: Int) -> String {
        String(utf16CodeUnits: [unichar(code)], count: 1)
    }

    private static func addRadio(_ menu: NSMenu, _ title: String, mode: String, _ target: AppDelegate) {
        let item = menu.addItem(withTitle: title, action: #selector(AppDelegate.selectMode(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = mode
    }
}

/// Rebuilds the "Open Recent" submenu each time it opens.
@MainActor
final class RecentMenuDelegate: NSObject, NSMenuDelegate {
    private weak var target: AppDelegate?
    private let recentsProvider: @MainActor () -> [URL]

    init(target: AppDelegate, recentsProvider: @escaping @MainActor () -> [URL]) {
        self.target = target
        self.recentsProvider = recentsProvider
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let recents = recentsProvider()
        if recents.isEmpty {
            let empty = menu.addItem(withTitle: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return
        }
        for url in recents {
            let item = menu.addItem(withTitle: url.lastPathComponent,
                                    action: #selector(AppDelegate.openRecent(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = url
            item.toolTip = url.path
        }
        menu.addItem(.separator())
        let clear = menu.addItem(withTitle: "Clear Menu",
                                 action: #selector(AppDelegate.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = target
    }
}
