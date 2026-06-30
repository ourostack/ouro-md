import Foundation
import OuroAppShellContract
import OuroMDCore

enum OuroMDShellContract {
    static let requiredSurfaces: [AppShellSurface] = [
        .appIdentity,
        .releaseUpdates,
        .about,
        .keyboardShortcuts,
        .settings,
        .windowChrome
    ]

    static let releaseUpdatePolicy = ReleaseUpdatePolicy.stable(
        assetNamingPolicy: .versionedArchiveAndManifest(namePrefix: "Ouro-MD-")
    )

    @MainActor
    static var contract: OuroAppShellContract {
        OuroAppShellContract(
            identity: identity,
            requiredSurfaces: requiredSurfaces,
            releaseUpdates: OuroAppShellReleaseUpdateContract(
                policy: releaseUpdatePolicy,
                installCapability: .reviewThenInstall,
                supportsReleasePage: true
            ),
            about: OuroAppShellAboutContract(
                subtitle: "Markdown editor for fast local writing.",
                repositoryURL: identity.repositoryURL
            ),
            commandReference: OuroAppShellCommandReferenceContract(
                title: "Keyboard Shortcuts",
                commandCount: CommandPaletteCatalog.items().count,
                sections: CommandReferenceView.sectionOrder,
                entryPoint: "Help > Keyboard Shortcuts"
            ),
            utilityWindows: [
                .init(id: "update-progress", surface: .releaseUpdates, title: OuroMDShellWindow.updateProgress.title),
                .init(id: "update-installed", surface: .releaseUpdates, title: OuroMDShellWindow.updateInstalled.title),
                .init(id: "preferences", surface: .settings, title: OuroMDShellWindow.preferences.title),
                .init(id: "keyboard-shortcuts", surface: .keyboardShortcuts, title: OuroMDShellWindow.keyboardShortcuts.title),
                .init(id: "about", surface: .about, title: OuroMDShellWindow.about.title)
            ],
            settings: OuroAppShellSettingsContract(
                entryPoint: "Ouro MD > Settings",
                appOwnedSections: [
                    "Appearance",
                    "Theme",
                    "Auto-save",
                    "Auto-pair",
                    "Updates",
                    "Telemetry",
                    "Text size"
                ]
            )
        )
    }

    static var identity: AppShellIdentity {
        AppShellIdentity(
            appName: OuroMDRelease.appName,
            bundleIdentifier: OuroMDRelease.bundleIdentifier,
            repository: OuroMDRelease.repository,
            version: OuroMDRelease.version,
            userAgent: OuroMDRelease.userAgent,
            distributionChannel: .directDownload
        )
    }
}

private extension AppShellIdentity {
    var repositoryURL: URL {
        URL(string: "https://github.com/\(repository)")!
    }
}
