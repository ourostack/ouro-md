import XCTest
@testable import OuroMD
import OuroAppShellConsumerTesting
import OuroMDCore

final class OuroMDShellContractTests: XCTestCase {
    @MainActor
    func testShellContractIsValidAndDeclaresSharedSurfaces() {
        let contract = OuroMDShellContract.contract

        OuroAppShellContractAssertions.assertValid(contract)
        OuroAppShellContractAssertions.assertRequiresShellFirstSurfaces(
            contract,
            OuroMDShellContract.requiredSurfaces
        )
    }

    @MainActor
    func testShellContractMatchesRuntimeIdentityReleaseAndShortcutSurfaces() {
        let contract = OuroMDShellContract.contract

        XCTAssertEqual(contract.identity.appName, OuroMDRelease.appName)
        XCTAssertEqual(contract.identity.bundleIdentifier, OuroMDRelease.bundleIdentifier)
        XCTAssertEqual(contract.identity.repository, OuroMDRelease.repository)
        XCTAssertEqual(contract.identity.version, OuroMDRelease.version)
        XCTAssertEqual(contract.identity.userAgent, OuroMDRelease.userAgent)
        XCTAssertEqual(contract.identity.distributionChannel, .directDownload)
        XCTAssertEqual(contract.identity.releasePageURL.absoluteString, "https://github.com/ourostack/ouro-md/releases/latest")

        XCTAssertEqual(contract.releaseUpdates?.policy, OuroMDReleaseUpdate.configuration().releasePolicy)
        XCTAssertEqual(contract.releaseUpdates?.supportsInstallAndRelaunch, true)
        XCTAssertEqual(contract.releaseUpdates?.supportsReleasePage, true)

        XCTAssertEqual(contract.about?.subtitle, "Markdown editor for fast local writing.")
        XCTAssertEqual(contract.about?.repositoryURL?.absoluteString, "https://github.com/ourostack/ouro-md")

        XCTAssertEqual(contract.commandReference?.title, "Keyboard Shortcuts")
        XCTAssertEqual(contract.commandReference?.commandCount, CommandPaletteCatalog.items().count)
        XCTAssertEqual(contract.commandReference?.sections, CommandReferenceView.sectionOrder)
        XCTAssertEqual(contract.commandReference?.entryPoint, "Help > Keyboard Shortcuts")
    }

    @MainActor
    func testShellContractDocumentsUtilityWindowsAndSettingsEntryPoint() {
        let contract = OuroMDShellContract.contract

        XCTAssertEqual(contract.utilityWindows.map(\.id), [
            "update-progress",
            "update-installed",
            "preferences",
            "keyboard-shortcuts",
            "about"
        ])
        XCTAssertEqual(contract.utilityWindows.map(\.title), [
            OuroMDShellWindow.updateProgress.title,
            OuroMDShellWindow.updateInstalled.title,
            OuroMDShellWindow.preferences.title,
            OuroMDShellWindow.keyboardShortcuts.title,
            OuroMDShellWindow.about.title
        ])
        XCTAssertEqual(contract.utilityWindows.map(\.surface), [
            .releaseUpdates,
            .releaseUpdates,
            .settings,
            .keyboardShortcuts,
            .about
        ])

        XCTAssertEqual(contract.settings?.entryPoint, "Ouro MD > Settings")
        XCTAssertEqual(contract.settings?.sharedSections.map(\.kind), [
            .updates,
            .telemetry,
            .privacy,
            .about,
            .keyboardShortcuts
        ])
        XCTAssertEqual(contract.settings?.appOwnedSections, [
            "Appearance",
            "Theme",
            "Auto-save",
            "Auto-pair",
            "Text size"
        ])

        XCTAssertEqual(contract.privacyDiagnostics?.telemetryConsentEntryPoint, "Ouro MD > Settings > Telemetry")
        XCTAssertEqual(contract.privacyDiagnostics?.privacyDocumentURL.absoluteString, "https://github.com/ourostack/ouro-md/blob/main/PRIVACY.md")
        XCTAssertEqual(contract.privacyDiagnostics?.diagnosticsExportDisclosure, "Ouro MD privacy documentation describes anonymous telemetry and local-first document handling.")
        XCTAssertEqual(contract.privacyDiagnostics?.supportBundleContents, ["app version", "bundle id", "macOS version", "architecture", "anonymous install id"])
        XCTAssertEqual(contract.privacyDiagnostics?.redactionGuarantees, [
            "no document contents",
            "no filenames",
            "no folder paths",
            "no search queries",
            "no clipboard contents",
            "no raw error messages"
        ])
    }
}
