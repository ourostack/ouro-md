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
        XCTAssertTrue(CommandPaletteCatalog.filter(items, query: "not-a-command").isEmpty)
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
        model.performCommandPaletteItem(CommandPaletteItem(id: "theme.graphite", title: "Theme: Graphite", keywords: "appearance color graphite"))

        XCTAssertEqual(bridge.commands, ["bold"])
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
