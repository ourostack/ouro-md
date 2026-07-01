import OuroMDAppSupport

extension Theme {
    var commandPaletteTheme: CommandPaletteTheme {
        CommandPaletteTheme(id: id, displayName: displayName)
    }
}

extension CommandPaletteCatalog {
    static func items(themes: [Theme] = ThemeStore.shared.themes) -> [CommandPaletteItem] {
        items(themes: themes.map(\.commandPaletteTheme))
    }
}
