import Foundation

public struct CommandPaletteTheme: Equatable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct CommandPaletteItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let keywords: String
    public let shortcut: String?

    public init(id: String, title: String, keywords: String, shortcut: String? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.shortcut = shortcut
    }

    public var searchableText: String {
        "\(title) \(keywords) \(shortcut ?? "") \(shortcutSearchText)".lowercased()
    }

    private var shortcutSearchText: String {
        guard let shortcut else { return "" }
        return shortcut
            .replacingOccurrences(of: "⌘", with: " command cmd ")
            .replacingOccurrences(of: "⇧", with: " shift ")
            .replacingOccurrences(of: "⌥", with: " option alt ")
            .replacingOccurrences(of: "⌃", with: " control ctrl ")
            .replacingOccurrences(of: "?", with: " question slash shift ")
            .replacingOccurrences(of: "/", with: " slash ")
    }
}

public enum CommandPaletteCatalog {
    public static func items(themes: [CommandPaletteTheme]) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = [
            CommandPaletteItem(id: "file.new", title: "New Document", keywords: "file blank", shortcut: "⌘N"),
            CommandPaletteItem(id: "file.open", title: "Open Document", keywords: "file picker", shortcut: "⌘O"),
            CommandPaletteItem(id: "file.open-folder", title: "Open Folder", keywords: "workspace files", shortcut: "⇧⌘O"),
            CommandPaletteItem(id: "file.save", title: "Save", keywords: "write disk", shortcut: "⌘S"),
            CommandPaletteItem(id: "file.save-as", title: "Save As", keywords: "duplicate copy", shortcut: "⇧⌘S"),
            CommandPaletteItem(id: "file.export-html", title: "Export HTML", keywords: "share web"),
            CommandPaletteItem(id: "file.export-pdf", title: "Export PDF", keywords: "print share"),
            CommandPaletteItem(id: "file.print", title: "Print", keywords: "paper pdf", shortcut: "⌘P"),
            CommandPaletteItem(id: "edit.command-palette", title: "Command Palette", keywords: "commands actions power user", shortcut: "⇧⌘P"),
            CommandPaletteItem(id: "edit.find", title: "Find", keywords: "search document", shortcut: "⌘F"),
            CommandPaletteItem(id: "edit.replace", title: "Replace", keywords: "find substitute", shortcut: "⌥⌘F"),
            CommandPaletteItem(id: "edit.find-next", title: "Find Next", keywords: "search next match", shortcut: "⌘G"),
            CommandPaletteItem(id: "edit.find-previous", title: "Find Previous", keywords: "search previous match", shortcut: "⇧⌘G"),
            CommandPaletteItem(id: "edit.paste-plain", title: "Paste as Plain Text", keywords: "clipboard paste text", shortcut: "⇧⌘V"),
            CommandPaletteItem(id: "edit.copy-markdown", title: "Copy as Markdown", keywords: "clipboard source"),
            CommandPaletteItem(id: "edit.copy-html", title: "Copy as HTML", keywords: "clipboard rich"),
            CommandPaletteItem(id: "format.bold", title: "Bold", keywords: "strong", shortcut: "⌘B"),
            CommandPaletteItem(id: "format.italic", title: "Italic", keywords: "emphasis", shortcut: "⌘I"),
            CommandPaletteItem(id: "format.strike", title: "Strikethrough", keywords: "delete line", shortcut: "⌃⌘S"),
            CommandPaletteItem(id: "format.code", title: "Inline Code", keywords: "monospace", shortcut: "⌘E"),
            CommandPaletteItem(id: "format.link", title: "Insert Link", keywords: "url", shortcut: "⌘K"),
            CommandPaletteItem(id: "paragraph.h1", title: "Heading 1", keywords: "paragraph title", shortcut: "⌘1"),
            CommandPaletteItem(id: "paragraph.h2", title: "Heading 2", keywords: "paragraph title", shortcut: "⌘2"),
            CommandPaletteItem(id: "paragraph.h3", title: "Heading 3", keywords: "paragraph title", shortcut: "⌘3"),
            CommandPaletteItem(id: "paragraph.h4", title: "Heading 4", keywords: "paragraph title", shortcut: "⌘4"),
            CommandPaletteItem(id: "paragraph.h5", title: "Heading 5", keywords: "paragraph title", shortcut: "⌘5"),
            CommandPaletteItem(id: "paragraph.h6", title: "Heading 6", keywords: "paragraph title", shortcut: "⌘6"),
            CommandPaletteItem(id: "paragraph.body", title: "Paragraph", keywords: "body text", shortcut: "⌘0"),
            CommandPaletteItem(id: "paragraph.ul", title: "Unordered List", keywords: "bullet paragraph"),
            CommandPaletteItem(id: "paragraph.ol", title: "Ordered List", keywords: "number paragraph"),
            CommandPaletteItem(id: "paragraph.task", title: "Task List", keywords: "checkbox paragraph"),
            CommandPaletteItem(id: "paragraph.quote", title: "Quote", keywords: "blockquote paragraph"),
            CommandPaletteItem(id: "paragraph.codeblock", title: "Code Fences", keywords: "code block fenced paragraph"),
            CommandPaletteItem(id: "paragraph.table", title: "Insert Table", keywords: "grid paragraph"),
            CommandPaletteItem(id: "paragraph.math", title: "Math Block", keywords: "equation latex paragraph"),
            CommandPaletteItem(id: "paragraph.hr", title: "Horizontal Rule", keywords: "divider paragraph"),
            CommandPaletteItem(id: "view.source", title: "Toggle Source Mode", keywords: "markdown code", shortcut: "⌘/"),
            CommandPaletteItem(id: "view.focus", title: "Toggle Focus Mode", keywords: "reading", shortcut: "F8"),
            CommandPaletteItem(id: "view.typewriter", title: "Toggle Typewriter Mode", keywords: "typing", shortcut: "F9"),
            CommandPaletteItem(id: "view.toggle-sidebar", title: "Toggle Sidebar", keywords: "panel", shortcut: "⇧⌘L"),
            CommandPaletteItem(id: "view.search-sidebar", title: "Show Folder Search", keywords: "sidebar", shortcut: "⇧⌘F"),
            CommandPaletteItem(id: "view.files-sidebar", title: "Show File Browser", keywords: "sidebar", shortcut: "⌃⌘3"),
            CommandPaletteItem(id: "view.outline-sidebar", title: "Show Outline", keywords: "sidebar headings", shortcut: "⌃⌘1"),
            CommandPaletteItem(id: "view.actual-size", title: "Actual Size", keywords: "zoom text", shortcut: "⇧⌘0"),
            CommandPaletteItem(id: "view.zoom-in", title: "Zoom In", keywords: "text larger", shortcut: "⇧⌘="),
            CommandPaletteItem(id: "view.zoom-out", title: "Zoom Out", keywords: "text smaller", shortcut: "⇧⌘-"),
            CommandPaletteItem(id: "help.about", title: "About Ouro MD", keywords: "version build info app"),
            CommandPaletteItem(id: "help.whats-new", title: "What's New", keywords: "release notes changes latest version"),
            CommandPaletteItem(id: "help.check-updates", title: "Check for Updates", keywords: "software update latest version install release"),
            CommandPaletteItem(id: "help.open-latest-release", title: "Open Latest Release", keywords: "github release notes latest update"),
            CommandPaletteItem(id: "help.keyboard-shortcuts", title: "Keyboard Shortcuts", keywords: "help commands reference", shortcut: "⌘?"),
        ]
        items.append(contentsOf: themes.map {
            CommandPaletteItem(id: "theme.\($0.id)", title: "Theme: \($0.displayName)", keywords: "appearance color \($0.id)")
        })
        return items
    }

    public static func filter(
        _ items: [CommandPaletteItem],
        query: String,
        emptyLimit: Int = 10,
        resultLimit: Int = 20
    ) -> [CommandPaletteItem] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return Array(items.prefix(emptyLimit)) }
        return items
            .filter { item in terms.allSatisfy { item.searchableText.contains($0) } }
            .prefix(resultLimit)
            .map { $0 }
    }
}
