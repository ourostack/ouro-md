import XCTest
@testable import OuroMDAppSupport

final class CommandPaletteCatalogTests: XCTestCase {
    func testCatalogFiltersByMultipleTermsShortcutAliasesAndLimits() {
        let items = CommandPaletteCatalog.items(themes: [
            CommandPaletteTheme(id: "paper", displayName: "Paper Trail"),
            CommandPaletteTheme(id: "night", displayName: "Night Desk")
        ])

        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "").count, 10)
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "", emptyLimit: 3).map(\.id), [
            "file.new",
            "file.open",
            "file.open-folder"
        ])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "export pdf").map(\.id), ["file.export-pdf"])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "theme night").map(\.id), ["theme.night"])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "cmd shift palette").map(\.id), ["edit.command-palette"])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "cmd shift slash").map(\.id), ["help.keyboard-shortcuts"])
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "cmd option f").map(\.id), ["edit.replace"])
        XCTAssertTrue(Set(CommandPaletteCatalog.filter(items, query: "latest release").map(\.id)).isSuperset(of: [
            "help.whats-new",
            "help.open-latest-release"
        ]))
        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "version build").map(\.id), ["help.about"])
        XCTAssertTrue(CommandPaletteCatalog.filter(items, query: "not-a-command").isEmpty)
    }

    func testCatalogHonorsResultLimit() {
        let items = [
            CommandPaletteItem(id: "a.one", title: "Alpha One", keywords: "shared"),
            CommandPaletteItem(id: "a.two", title: "Alpha Two", keywords: "shared"),
            CommandPaletteItem(id: "a.three", title: "Alpha Three", keywords: "shared")
        ]

        XCTAssertEqual(CommandPaletteCatalog.filter(items, query: "shared", resultLimit: 2).map(\.id), [
            "a.one",
            "a.two"
        ])
    }

    func testCatalogCarriesShortcutMetadataForPowerUserDiscovery() {
        let items = Dictionary(uniqueKeysWithValues: CommandPaletteCatalog.items(themes: []).map { ($0.id, $0) })

        XCTAssertEqual(items["edit.command-palette"]?.shortcut, "⇧⌘P")
        XCTAssertEqual(items["help.keyboard-shortcuts"]?.shortcut, "⌘?")
        XCTAssertEqual(items["file.open-folder"]?.shortcut, "⇧⌘O")
        XCTAssertEqual(items["edit.find"]?.shortcut, "⌘F")
        XCTAssertEqual(items["edit.replace"]?.shortcut, "⌥⌘F")
        XCTAssertEqual(items["view.search-sidebar"]?.shortcut, "⇧⌘F")
        XCTAssertEqual(items["paragraph.h6"]?.shortcut, "⌘6")
    }

    func testCatalogIncludesDocumentTruthCommands() {
        let items = Dictionary(uniqueKeysWithValues: CommandPaletteCatalog.items(themes: []).map { ($0.id, $0) })

        XCTAssertEqual(items["file.reveal-in-finder"]?.title, "Reveal in Finder")
        XCTAssertEqual(items["file.copy-path"]?.title, "Copy File Path")
        XCTAssertEqual(items["file.copy-relative-path"]?.title, "Copy Relative Path")
        XCTAssertEqual(items["file.copy-git-diff-command"]?.title, "Copy Git Diff Command")
        XCTAssertEqual(CommandPaletteCatalog.filter(Array(items.values), query: "git diff").map(\.id), ["file.copy-git-diff-command"])
        XCTAssertEqual(CommandPaletteCatalog.filter(Array(items.values), query: "finder reveal").map(\.id), ["file.reveal-in-finder"])
    }

    func testCatalogIncludesThemeCommandsFromDescriptors() {
        let themeItems = CommandPaletteCatalog.items(themes: [
            CommandPaletteTheme(id: "graphite", displayName: "Graphite"),
            CommandPaletteTheme(id: "custom-night", displayName: "Custom Night")
        ]).filter { $0.id.hasPrefix("theme.") }

        XCTAssertEqual(themeItems, [
            CommandPaletteItem(id: "theme.graphite", title: "Theme: Graphite", keywords: "appearance color graphite"),
            CommandPaletteItem(id: "theme.custom-night", title: "Theme: Custom Night", keywords: "appearance color custom-night")
        ])
    }
}
