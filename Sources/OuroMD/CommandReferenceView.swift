import SwiftUI

struct ShortcutBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary, lineWidth: 1))
            .accessibilityLabel(spokenShortcut(text))
    }
}

struct CommandReferenceView: View {
    let items: [CommandPaletteItem]
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search commands")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.items) { item in
                                commandRow(item)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 500, idealHeight: 620)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }

    private var filteredItems: [CommandPaletteItem] {
        CommandPaletteCatalog.filter(items, query: query, emptyLimit: Int.max, resultLimit: Int.max)
    }

    private var sections: [CommandReferenceSection] {
        let grouped = Dictionary(grouping: filteredItems, by: { category(for: $0.id) })
        return categoryOrder.compactMap { name in
            guard let items = grouped[name], !items.isEmpty else { return nil }
            return CommandReferenceSection(name: name, items: items)
        }
    }

    private func commandRow(_ item: CommandPaletteItem) -> some View {
        HStack(spacing: 10) {
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 16)
            if let shortcut = item.shortcut {
                ShortcutBadge(text: shortcut)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(commandAccessibilityLabel(item))
    }

    private func commandAccessibilityLabel(_ item: CommandPaletteItem) -> String {
        if let shortcut = item.shortcut {
            return "\(item.title), \(spokenShortcut(shortcut))"
        }
        return item.title
    }

    private var categoryOrder: [String] {
        ["File", "Edit", "Format", "Paragraph", "View", "Themes", "Help", "Other"]
    }

    private func category(for id: String) -> String {
        switch id.split(separator: ".").first.map(String.init) {
        case "file": return "File"
        case "edit": return "Edit"
        case "format": return "Format"
        case "paragraph": return "Paragraph"
        case "view": return "View"
        case "theme": return "Themes"
        case "help": return "Help"
        default: return "Other"
        }
    }
}

private struct CommandReferenceSection: Identifiable {
    let name: String
    let items: [CommandPaletteItem]

    var id: String { name }
}

func spokenShortcut(_ shortcut: String) -> String {
    shortcut
        .replacingOccurrences(of: "⌘", with: "Command ")
        .replacingOccurrences(of: "⇧", with: "Shift ")
        .replacingOccurrences(of: "⌥", with: "Option ")
        .replacingOccurrences(of: "⌃", with: "Control ")
        .replacingOccurrences(of: "/", with: "Slash")
        .replacingOccurrences(of: "?", with: "Question Mark")
}
