import AppKit
import OuroAppShellUI
import OuroMDCore
import SwiftUI

struct OuroMDAboutView: View {
    @ObservedObject var updateCoordinator: OuroMDUpdateCoordinator
    var onDismiss: () -> Void = {}

    private var buildLine: String {
        if let gitSHA = OuroCLI.gitSHA {
            return "Build \(gitSHA)"
        }
        if let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !bundleBuild.isEmpty,
           bundleBuild != OuroMDRelease.version {
            return "Build \(bundleBuild)"
        }
        return "Source build"
    }

    private var versionLine: String {
        "Version \(OuroMDRelease.version) - \(buildLine)"
    }

    var body: some View {
        OuroAppShellUI.AppShellAboutView(
            model: aboutModel,
            updateState: updateCoordinator.appShellUpdateState,
            updateActions: updateCoordinator.appShellUpdateActions,
            aboutActions: AppShellAboutActions(
                openRepository: { NSWorkspace.shared.open(repositoryURL) },
                copyVersion: copyVersion,
                dismiss: onDismiss
            )
        )
        .frame(width: 520, height: 520)
    }

    private func copyVersion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(versionLine, forType: .string)
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/\(OuroMDRelease.repository)")!
    }

    private var aboutModel: AppShellAboutModel {
        AppShellAboutModel(
            appName: OuroMDRelease.appName,
            versionLine: versionLine,
            subtitle: "Independent Markdown editor for fast local writing.",
            repositoryURL: repositoryURL,
            iconSystemName: "doc.richtext",
            whatsNew: AppShellWhatsNewModel(
                title: "What's New in \(OuroMDRelease.version)",
                releasedText: "Released \(OuroMDRelease.releaseDate)",
                highlights: OuroMDRelease.releaseHighlights,
                releaseNotesPreview: updateCoordinator.releaseNotesPreview
            )
        )
    }
}

struct ReleaseUpdateControls: View {
    @ObservedObject var updateCoordinator: OuroMDUpdateCoordinator
    var showTitle: Bool

    var body: some View {
        OuroAppShellUI.ReleaseUpdateControls(
            state: updateCoordinator.appShellUpdateState,
            actions: updateCoordinator.appShellUpdateActions,
            labels: ReleaseUpdateActionLabels(
                check: "Check for Updates",
                review: "Review Update",
                install: "Install & Relaunch",
                openRelease: "Open Release"
            ),
            showTitle: showTitle
        )
    }
}

struct UpdateInstalledConfirmationView: View {
    let version: String
    let onOpenAbout: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        OuroAppShellUI.UpdateInstalledConfirmationView(
            appName: OuroMDRelease.appName,
            version: version,
            openAboutLabel: "What's New",
            openAboutSystemImage: nil,
            dismissLabel: "OK",
            onOpenAbout: onOpenAbout,
            onDismiss: onDismiss
        )
        .frame(width: 360)
    }
}

extension OuroMDUpdateCoordinator {
    var appShellUpdateState: ReleaseUpdateViewState {
        ReleaseUpdateViewState(
            kind: appShellUpdateKind,
            statusLine: releaseUpdateStatusLine,
            metadata: appShellUpdateMetadata,
            detail: appShellUpdateDetail,
            warning: appShellUpdateWarning,
            canReviewUpdate: updateBadgeText != nil,
            canOpenReleasePage: releasePageURL != nil
        )
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

    var appShellUpdateKind: ReleaseUpdateStateKind {
        if isChecking { return .checking }
        if isInstalling { return .installing }
        if stagedUpdateVersion != nil { return .readyToRelaunch }
        if let status = releaseUpdateStatusKind {
            switch status {
            case .current: return .current
            case .updateAvailable: return .updateAvailable
            case .unavailable: return .unavailable
            }
        }
        if recentlyInstalledVersion != nil { return .installed }
        return .notChecked
    }

    var appShellUpdateMetadata: [ReleaseUpdateMetadataItem] {
        var items: [ReleaseUpdateMetadataItem] = []
        if let latest = latestKnownVersion {
            items.append(ReleaseUpdateMetadataItem(id: "latest", label: "Latest", value: latest))
        }
        if let published = releasePublishedAtText {
            items.append(ReleaseUpdateMetadataItem(id: "published", label: "Published", value: published))
        }
        items.append(ReleaseUpdateMetadataItem(id: "channel", label: "Channel", value: "Direct download"))
        return items
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
