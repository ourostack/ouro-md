import AppKit
import OuroAppShellAppKit
import OuroAppShellContract
import OuroAppShellUI
import SwiftUI

typealias ShortcutBadge = AppShellShortcutBadge

struct CommandReferenceView: View {
    let items: [CommandPaletteItem]
    var onDone: (() -> Void)?

    var body: some View {
        AppShellCommandReferenceView(
            items: items.map(\.appShellCommandReferenceItem),
            preferredSectionOrder: Self.sectionOrder,
            onDone: onDone
        )
    }

    static let sectionOrder = ["File", "Edit", "Format", "Paragraph", "View", "Themes", "Help", "Other"]
}

func spokenShortcut(_ shortcut: String) -> String {
    AppShellCommandReferenceCatalog.spokenShortcut(shortcut)
}

@MainActor
enum OuroMDShellWindow {
    static let updateProgress = AppShellWindowSpec(
        title: "Software Update",
        width: 420,
        height: 160,
        styleMask: [.titled]
    )

    static let updateInstalled = AppShellWindowSpec(
        title: "Ouro MD Updated",
        width: 360,
        height: 140
    )

    static let preferences = AppShellWindowSpec(
        title: "Preferences",
        width: 560,
        height: 430,
        minSize: NSSize(width: 520, height: 400),
        styleMask: [.titled, .closable, .resizable]
    )

    static let keyboardShortcuts = AppShellWindowSpec(
        title: "Keyboard Shortcuts",
        width: 560,
        height: 620,
        minSize: NSSize(width: 520, height: 500),
        styleMask: [.titled, .closable, .resizable]
    )

    static let about = AppShellWindowSpec(
        title: "About Ouro MD",
        width: 520,
        height: 520,
        minSize: NSSize(width: 500, height: 480),
        styleMask: [.titled, .closable, .resizable]
    )
}

extension CommandPaletteItem {
    static func sortedForAppShellCommandReference(_ items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        items.sorted { lhs, rhs in
            let lhsSection = CommandReferenceView.sectionOrder.firstIndex(of: lhs.appShellSection) ?? Int.max
            let rhsSection = CommandReferenceView.sectionOrder.firstIndex(of: rhs.appShellSection) ?? Int.max
            if lhsSection != rhsSection {
                return lhsSection < rhsSection
            }
            return lhs.id < rhs.id
        }
    }

    var appShellCommandSurface: OuroAppShellCommandSurface {
        OuroAppShellCommandSurface(
            id: id,
            title: title,
            section: appShellSection,
            shortcut: shortcut,
            menuPath: appShellMenuPath,
            commandPaletteTitle: title,
            referenceTitle: title
        )
    }

    var appShellCommandReferenceItem: AppShellCommandReferenceItem {
        AppShellCommandReferenceItem(
            id: id,
            title: title,
            section: appShellSection,
            shortcut: shortcut,
            keywords: keywords
        )
    }

    var appShellMenuPath: String? {
        switch id {
        case "file.new": return "File > New"
        case "file.open": return "File > Open..."
        case "file.open-folder": return "File > Open Folder..."
        case "file.save": return "File > Save"
        case "file.save-as": return "File > Save As..."
        case "file.export-html": return "File > Export > HTML..."
        case "file.export-pdf": return "File > Export > PDF..."
        case "file.print": return "File > Print..."
        case "edit.command-palette": return "Edit > Command Palette..."
        case "edit.find": return "Edit > Find > Find..."
        case "edit.replace": return "Edit > Find > Replace..."
        case "edit.find-next": return "Edit > Find > Find Next"
        case "edit.find-previous": return "Edit > Find > Find Previous"
        case "edit.paste-plain": return "Edit > Paste as Plain Text"
        case "edit.copy-markdown": return "Edit > Copy as > Markdown"
        case "edit.copy-html": return "Edit > Copy as > Rendered (HTML)"
        case "format.bold": return "Format > Bold"
        case "format.italic": return "Format > Italic"
        case "format.strike": return "Format > Strikethrough"
        case "format.code": return "Format > Inline Code"
        case "format.link": return "Format > Insert Link"
        case "view.source": return "View > Source Code Mode"
        case "view.focus": return "View > Focus Mode"
        case "view.typewriter": return "View > Typewriter Mode"
        case "view.toggle-sidebar": return "View > Toggle Sidebar"
        case "view.search-sidebar": return "View > Search"
        case "view.files-sidebar": return "View > File Tree"
        case "view.outline-sidebar": return "View > Outline"
        case "view.actual-size": return "View > Actual Size"
        case "view.zoom-in": return "View > Zoom In"
        case "view.zoom-out": return "View > Zoom Out"
        case "help.about": return "Ouro MD > About Ouro MD"
        case "help.whats-new": return "Help > What's New"
        case "help.check-updates": return "Help > Check for Updates..."
        case "help.open-latest-release": return "Help > Open Latest Release"
        case "help.keyboard-shortcuts": return "Help > Keyboard Shortcuts..."
        default:
            if id.hasPrefix("paragraph.") {
                return "Paragraph > \(title)"
            }
            if id.hasPrefix("theme.") {
                return "Themes > \(title.replacingOccurrences(of: "Theme: ", with: ""))"
            }
            return nil
        }
    }

    var appShellSection: String {
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

extension Array where Element == CommandPaletteItem {
    func sortedForAppShellCommandReference() -> [CommandPaletteItem] {
        CommandPaletteItem.sortedForAppShellCommandReference(self)
    }
}

extension OuroMDUpdateCoordinator {
    var appShellUpdateState: ReleaseUpdateViewState {
        var state = ReleaseUpdateViewState.from(
            presentation: ReleaseUpdatePresentationInput(
                snapshot: releaseSnapshot,
                channel: OuroMDShellContract.identity.distributionChannel,
                installCapability: OuroMDShellContract.contract.releaseUpdates?.installCapability ?? .none,
                isChecking: isChecking,
                isInstalling: isInstalling,
                installStatus: isInstalling ? installStatus : nil,
                installError: installProgress.phase == .failed ? installProgress.detail : nil,
                stagedUpdateVersion: stagedUpdateVersion,
                recentlyInstalledVersion: recentlyInstalledVersion,
                installPlan: releaseSnapshot.map { OuroMDUpdatePlanner.plan(from: $0) }
            )
        )
        state.statusLine = releaseUpdateStatusLine
        state.canReviewUpdate = updateBadgeText != nil
        state.canInstallUpdate = false
        state.warning = appShellUpdateWarning ?? state.warning
        state.detail = appShellUpdateDetail ?? state.detail
        return state
    }

    var appShellUpdateActions: ReleaseUpdateActions {
        ReleaseUpdateActions(
            checkForUpdates: { Task { await self.checkForUpdatesAndPromptInstall() } },
            reviewUpdate: { self.presentUpdatePrompt() },
            openReleasePage: {
                if let url = self.releasePageURL {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }

    var appShellUpdateDetail: String? {
        guard let snapshot = releaseSnapshot, snapshot.status == .updateAvailable, snapshot.hasInstallableAssets else {
            return nil
        }
        return "Before installing, Ouro MD verifies the release manifest, SHA-256 checksum, byte count, bundle identity, and newer version."
    }

    var appShellUpdateWarning: String? {
        guard let snapshot = releaseSnapshot, snapshot.status == .updateAvailable, !snapshot.hasInstallableAssets else {
            return nil
        }
        return "A newer release exists, but the app archive or manifest is missing."
    }
}
