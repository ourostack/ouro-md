import AppKit
import OuroAppShellAppKit
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

private extension CommandPaletteItem {
    var appShellCommandReferenceItem: AppShellCommandReferenceItem {
        AppShellCommandReferenceItem(
            id: id,
            title: title,
            section: appShellSection,
            shortcut: shortcut,
            keywords: keywords
        )
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
