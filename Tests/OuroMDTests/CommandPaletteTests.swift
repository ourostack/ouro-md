import XCTest
@testable import OuroMD

final class CommandPaletteTests: XCTestCase {
    func testCatalogFiltersByMultipleTermsAndLimitsDefaultSuggestions() {
        let items = CommandPaletteCatalog.items(themes: [
            Theme(id: "paper", displayName: "Paper Trail", uiMode: "classic", backgroundHex: "#ffffff", css: "", editorCSS: ""),
            Theme(id: "night", displayName: "Night Desk", uiMode: "dark", backgroundHex: "#000000", css: "", editorCSS: ""),
        ])

        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "").count, 10)
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "export pdf").map(\.id), ["file.export-pdf"])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "theme night").map(\.id), ["theme.night"])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "cmd shift palette").map(\.id), ["edit.command-palette"])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "cmd shift slash").map(\.id), ["help.keyboard-shortcuts"])
        XCTAssertTrue(CommandPaletteCatalog.filter(items, query: "not-a-command").isEmpty)
    }

    func testCatalogCarriesShortcutMetadataForPowerUserDiscovery() {
        let items = Dictionary(uniqueKeysWithValues: CommandPaletteCatalog.items().map { ($0.id, $0) })

        XCTAssertEqual(items["edit.command-palette"]?.shortcut, "⇧⌘P")
        XCTAssertEqual(items["help.keyboard-shortcuts"]?.shortcut, "⌘?")
        XCTAssertEqual(items["file.open-folder"]?.shortcut, "⇧⌘O")
        XCTAssertEqual(items["edit.find"]?.shortcut, "⌘F")
        XCTAssertEqual(items["edit.replace"]?.shortcut, "⌥⌘F")
        XCTAssertEqual(items["view.search-sidebar"]?.shortcut, "⇧⌘F")
        XCTAssertEqual(items["paragraph.h6"]?.shortcut, "⌘6")
    }

    func testCatalogIncludesEditorMenuCommandsWithoutShortcuts() {
        let ids = Set(CommandPaletteCatalog.items().map(\.id))

        XCTAssertTrue(ids.contains("edit.paste-plain"))
        XCTAssertTrue(ids.contains("edit.find-next"))
        XCTAssertTrue(ids.contains("edit.find-previous"))
        XCTAssertTrue(ids.contains("paragraph.quote"))
        XCTAssertTrue(ids.contains("paragraph.codeblock"))
        XCTAssertTrue(ids.contains("paragraph.math"))
        XCTAssertTrue(ids.contains("paragraph.hr"))
    }

    func testPaletteVisibilityAndFindCommandsResetQuery() {
        let model = AppModel()
        model.showCommandPalette()
        model.commandPaletteQuery = "replace"

        model.performCommandPaletteItem(CommandPaletteItem(id: "edit.replace", title: "Replace", keywords: "find substitute"))

        XCTAssertFalse(model.commandPaletteVisible)
        XCTAssertEqual(model.commandPaletteQuery, "")
        XCTAssertTrue(model.findVisible)
        XCTAssertTrue(model.replaceVisible)
    }

    func testPaletteDispatchesFormatModeSidebarAndThemeActions() {
        let model = AppModel()
        let bridge = PaletteBridge()
        model.bridge = bridge

        model.performCommandPaletteItem(CommandPaletteItem(id: "format.bold", title: "Bold", keywords: "strong"))
        model.performCommandPaletteItem(CommandPaletteItem(id: "view.source", title: "Toggle Source Mode", keywords: "markdown code"))
        model.performCommandPaletteItem(CommandPaletteItem(id: "view.search-sidebar", title: "Show Folder Search", keywords: "sidebar"))
        model.performCommandPaletteItem(CommandPaletteItem(id: "paragraph.quote", title: "Quote", keywords: ""))
        model.performCommandPaletteItem(CommandPaletteItem(id: "paragraph.codeblock", title: "Code Fences", keywords: ""))
        model.performCommandPaletteItem(CommandPaletteItem(id: "paragraph.math", title: "Math Block", keywords: ""))
        model.performCommandPaletteItem(CommandPaletteItem(id: "paragraph.hr", title: "Horizontal Rule", keywords: ""))
        model.performCommandPaletteItem(CommandPaletteItem(id: "theme.graphite", title: "Theme: Graphite", keywords: "appearance color graphite"))

        XCTAssertEqual(bridge.commands, ["bold", "quote", "codeblock", "math", "hr"])
        XCTAssertEqual(model.mode, "sv")
        XCTAssertTrue(model.sidebarVisible)
        XCTAssertEqual(model.sidebarMode, .search)
        XCTAssertEqual(model.themeID, "graphite")
    }
}

private final class PaletteBridge: EditorBridge {
    var commands: [String] = []

    func setMarkdown(_ markdown: String) {}
    func reloadMarkdown(_ markdown: String) {}
    func getMarkdown(_ completion: @escaping (String?) -> Void) { completion("") }
    func getHTML(_ completion: @escaping (String?) -> Void) { completion("") }
    func applyTheme(uiMode: String, css: String, codeTheme: String, background: String) {}
    func setMode(_ mode: String) {}
    func setOutline(_ on: Bool) {}
    func setFocusMode(_ on: Bool) {}
    func setTypewriter(_ on: Bool) {}
    func setAutoPair(_ on: Bool) {}
    func scrollToHeading(_ index: Int) {}
    func find(_ query: String, backward: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {}
    func revealSearchMatch(lineNumber: Int, sourceColumn: Int, sourceLength: Int, matchOrdinal: Int, matchedText: String, query: String, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) {}
    func replace(_ query: String, with replacement: String, all: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool, completion: @escaping (Int) -> Void) { completion(0) }
    func clearFind() {}
    func execCommand(_ command: String) { commands.append(command) }
    func insertText(_ text: String) {}
    func setDocBase(_ directory: String?) {}
    func markSaved() {}
    func undo() {}
    func redo() {}
    func focusEditor() {}
    func printDocument() {}
    func setZoom(_ factor: Double) {}
}
