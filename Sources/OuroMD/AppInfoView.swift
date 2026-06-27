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
            subtitle: "Markdown editor for fast local writing.",
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

struct OuroMDReleaseControls: View {
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

struct OuroMDUpdateInstalledNotice: View {
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
