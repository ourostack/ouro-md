import AppKit

/// Builds the native menu bar and keeps dynamic items (theme / mode / recent)
/// in sync with the current document state.
enum MenuBuilder {
    private static weak var themeMenu: NSMenu?
    private static weak var modeMenu: NSMenu?
    private static var recentDelegate: RecentMenuDelegate?

    static func install(into app: NSApplication, target: AppDelegate) {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu())
        mainMenu.addItem(fileMenu(target: target))
        mainMenu.addItem(editMenu())
        mainMenu.addItem(formatMenu(target: target))
        mainMenu.addItem(viewMenu(target: target))
        let windowMenuItem = windowMenu()
        mainMenu.addItem(windowMenuItem)
        let helpMenuItem = helpMenu(target: target)
        mainMenu.addItem(helpMenuItem)

        app.mainMenu = mainMenu
        app.windowsMenu = windowMenuItem.submenu
        app.helpMenu = helpMenuItem.submenu

        refreshDynamicState(model: target.model)
    }

    static func refreshDynamicState(model: AppModel) {
        themeMenu?.items.forEach {
            $0.state = ($0.representedObject as? String == model.themeID) ? .on : .off
        }
        modeMenu?.items.forEach {
            $0.state = ($0.representedObject as? String == model.mode) ? .on : .off
        }
    }

    // MARK: - App menu

    private static func appMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()
        item.submenu = menu

        menu.addItem(withTitle: "About ouro-md",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let hide = menu.addItem(withTitle: "Hide ouro-md",
                                action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = nil
        let hideOthers = menu.addItem(withTitle: "Hide Others",
                                      action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ouro-md",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item
    }

    // MARK: - File menu

    private static func fileMenu(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        item.submenu = menu

        add(menu, "New", #selector(AppDelegate.newDocument(_:)), "n", target)
        add(menu, "Open…", #selector(AppDelegate.openDocument(_:)), "o", target)

        let openRecent = menu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        let delegate = RecentMenuDelegate(target: target)
        recentDelegate = delegate
        recentMenu.delegate = delegate
        openRecent.submenu = recentMenu

        menu.addItem(.separator())
        add(menu, "Save", #selector(AppDelegate.saveDocument(_:)), "s", target)
        let saveAs = add(menu, "Save As…", #selector(AppDelegate.saveDocumentAs(_:)), "s", target)
        saveAs.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        let export = menu.addItem(withTitle: "Export", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: "Export")
        add(exportMenu, "HTML…", #selector(AppDelegate.exportHTML(_:)), "", target)
        add(exportMenu, "PDF…", #selector(AppDelegate.exportPDF(_:)), "", target)
        export.submenu = exportMenu

        menu.addItem(.separator())
        let close = menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = nil
        return item
    }

    // MARK: - Edit menu (standard responder-chain actions)

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        item.submenu = menu

        standard(menu, "Undo", Selector(("undo:")), "z")
        let redo = standard(menu, "Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        standard(menu, "Cut", #selector(NSText.cut(_:)), "x")
        standard(menu, "Copy", #selector(NSText.copy(_:)), "c")
        standard(menu, "Paste", #selector(NSText.paste(_:)), "v")
        standard(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
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

        let modeItem = menu.addItem(withTitle: "Editing Mode", action: nil, keyEquivalent: "")
        let modeSub = NSMenu(title: "Editing Mode")
        addRadio(modeSub, "Instant (Live Preview)", mode: "ir", target)
        addRadio(modeSub, "WYSIWYG", mode: "wysiwyg", target)
        addRadio(modeSub, "Split (Source + Preview)", mode: "sv", target)
        modeItem.submenu = modeSub
        modeMenu = modeSub

        menu.addItem(.separator())
        let themeItem = menu.addItem(withTitle: "Theme", action: nil, keyEquivalent: "")
        let themeSub = NSMenu(title: "Theme")
        for theme in ThemeStore.shared.themes {
            let entry = themeSub.addItem(withTitle: theme.displayName,
                                         action: #selector(AppDelegate.selectTheme(_:)), keyEquivalent: "")
            entry.target = target
            entry.representedObject = theme.id
        }
        themeItem.submenu = themeSub
        themeMenu = themeSub

        menu.addItem(.separator())
        let outline = add(menu, "Toggle Outline", #selector(AppDelegate.toggleOutline(_:)), "o", target)
        outline.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(.separator())
        add(menu, "Actual Size", #selector(AppDelegate.actualSize(_:)), "0", target)
        add(menu, "Zoom In", #selector(AppDelegate.zoomIn(_:)), "+", target)
        add(menu, "Zoom Out", #selector(AppDelegate.zoomOut(_:)), "-", target)

        menu.addItem(.separator())
        let fullScreen = menu.addItem(withTitle: "Enter Full Screen",
                                      action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        fullScreen.target = nil
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
        add(menu, "ouro-md on GitHub", #selector(AppDelegate.openProjectPage(_:)), "", target)
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

    private static func addRadio(_ menu: NSMenu, _ title: String, mode: String, _ target: AppDelegate) {
        let item = menu.addItem(withTitle: title, action: #selector(AppDelegate.selectMode(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = mode
    }
}

/// Rebuilds the "Open Recent" submenu each time it opens.
final class RecentMenuDelegate: NSObject, NSMenuDelegate {
    private weak var target: AppDelegate?

    init(target: AppDelegate) { self.target = target }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let recents = NSDocumentController.shared.recentDocumentURLs
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
