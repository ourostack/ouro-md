import Foundation
import XCTest
@testable import OuroMD

@MainActor
final class OuroMDUpdateCoordinatorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OuroMDUpdateCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAutoUpdateDefaultsToEnabledAndPersistsOptOut() {
        let coordinator = makeCoordinator()

        XCTAssertTrue(coordinator.autoUpdateEnabled)
        coordinator.setAutoUpdateEnabled(false)
        XCTAssertFalse(coordinator.autoUpdateEnabled)
        XCTAssertEqual(defaults.object(forKey: OuroMDUpdateCoordinator.autoUpdateEnabledDefaultsKey) as? Bool, false)

        let restored = makeCoordinator()
        XCTAssertFalse(restored.autoUpdateEnabled)
    }

    func testManualCheckPromptsInstallableCurrentAndUnavailableStates() async {
        let installable = makeCoordinator(checker: { self.updateSnapshot() })
        await installable.checkForUpdatesAndPromptInstall()
        XCTAssertEqual(installable.updatePrompt, .installable(version: "0.10.0"))

        let current = makeCoordinator(checker: { self.currentSnapshot() })
        await current.checkForUpdatesAndPromptInstall()
        XCTAssertEqual(current.updatePrompt, .upToDate(version: "0.9.0"))

        let unavailable = makeCoordinator(checker: { self.unavailableSnapshot(detail: "offline") })
        await unavailable.checkForUpdatesAndPromptInstall()
        XCTAssertEqual(unavailable.updatePrompt, .failed(detail: "offline"))
    }

    func testManualCheckReportsMissingInstallableAssets() async {
        let coordinator = makeCoordinator(
            checker: {
                self.updateSnapshot(assets: [
                    ReleaseUpdateAsset(name: "notes.txt", downloadURL: "https://example.test/notes.txt", size: 10),
                ])
            }
        )

        await coordinator.checkForUpdatesAndPromptInstall()

        XCTAssertEqual(
            coordinator.updatePrompt,
            .failed(detail: "A newer version is published but has no installable assets yet.")
        )
    }

    func testAutoUpdateCheckIsDefaultOnThrottledAndOncePerSession() async {
        let now = Date(timeIntervalSince1970: 10_000)
        var checkCount = 0
        let coordinator = makeCoordinator(
            checker: {
                checkCount += 1
                return self.currentSnapshot()
            },
            now: { now }
        )

        await coordinator.runAutoUpdateCheckIfDue()
        await coordinator.runAutoUpdateCheckIfDue()

        XCTAssertEqual(checkCount, 1)
        XCTAssertEqual(defaults.object(forKey: OuroMDUpdateCoordinator.lastUpdateCheckAtDefaultsKey) as? Date, now)

        defaults.set(now.addingTimeInterval(-120), forKey: OuroMDUpdateCoordinator.lastUpdateCheckAtDefaultsKey)
        let throttled = makeCoordinator(
            checker: {
                XCTFail("Throttled coordinator should not hit checker")
                return self.currentSnapshot()
            },
            now: { now }
        )
        await throttled.runAutoUpdateCheckIfDue()
    }

    func testAutoUpdateCheckSkipsWhenDisabled() async {
        let coordinator = makeCoordinator(
            checker: {
                XCTFail("Disabled coordinator should not hit checker")
                return self.currentSnapshot()
            }
        )
        coordinator.setAutoUpdateEnabled(false)

        await coordinator.runAutoUpdateCheckIfDue()

        XCTAssertNil(defaults.object(forKey: OuroMDUpdateCoordinator.lastUpdateCheckAtDefaultsKey))
    }

    func testAutoUpdateStagesInstallableUpdateInBackground() async throws {
        let staged = stagedUpdate(version: "0.10.0")
        var stagedPlan: OuroMDUpdatePlan?
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { plan, progress in
                stagedPlan = plan
                await progress("Downloading")
                return staged
            }
        )

        await coordinator.runAutoUpdateCheckIfDue()

        XCTAssertEqual(stagedPlan?.version, "0.10.0")
        XCTAssertEqual(coordinator.stagedUpdateVersion, "0.10.0")
        XCTAssertEqual(coordinator.updateBadgeText, "Update 0.10.0")
    }

    func testApplyStagedUpdateOnQuitOnlyWhenEnabledAndNotManualInstall() async {
        let staged = stagedUpdate(version: "0.10.0")
        var quitApplications: [OuroMDUpdateInstaller.Staged] = []
        let destination = URL(fileURLWithPath: "/tmp/Ouro MD.app")
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, _ in staged },
            applyOnQuit: { staged, destinationBundle in
                quitApplications.append(staged)
                XCTAssertEqual(destinationBundle, destination)
            }
        )
        await coordinator.runAutoUpdateCheckIfDue()

        coordinator.applyStagedUpdateOnQuitIfNeeded(destinationBundle: destination)
        coordinator.applyStagedUpdateOnQuitIfNeeded(destinationBundle: destination)

        XCTAssertEqual(quitApplications, [staged])
    }

    func testManualInstallUsesAlreadyStagedUpdateAndSuppressesQuitApply() async {
        let staged = stagedUpdate(version: "0.10.0")
        var relaunchApplications: [OuroMDUpdateInstaller.Staged] = []
        var quitApplications: [OuroMDUpdateInstaller.Staged] = []
        var didTerminate = false
        let destination = URL(fileURLWithPath: "/tmp/Ouro MD.app")
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, _ in staged },
            applyAndRelaunch: { staged, destinationBundle in
                relaunchApplications.append(staged)
                XCTAssertEqual(destinationBundle, destination)
            },
            applyOnQuit: { staged, _ in quitApplications.append(staged) },
            terminate: { didTerminate = true }
        )
        await coordinator.runAutoUpdateCheckIfDue()

        await coordinator.installReleaseUpdate(destinationBundle: destination)
        coordinator.applyStagedUpdateOnQuitIfNeeded(destinationBundle: destination)

        XCTAssertEqual(relaunchApplications, [staged])
        XCTAssertTrue(didTerminate)
        XCTAssertTrue(quitApplications.isEmpty)
        XCTAssertEqual(coordinator.installStatus, "Installing 0.10.0 and relaunching...")
    }

    private func makeCoordinator(
        checker: @escaping () async -> ReleaseUpdateSnapshot = { ReleaseUpdateSnapshot(
            status: .current,
            currentVersion: "0.9.0",
            latestVersion: nil,
            tagName: nil,
            htmlURL: nil,
            assets: [],
            detail: "Version 0.9.0 is current."
        ) },
        stageUpdate: @escaping (OuroMDUpdatePlan, @escaping @Sendable (String) async -> Void) async throws -> OuroMDUpdateInstaller.Staged = { _, _ in
            throw OuroMDUpdateInstaller.InstallError.download("not stubbed")
        },
        applyAndRelaunch: @escaping (OuroMDUpdateInstaller.Staged, URL) -> Void = { _, _ in },
        applyOnQuit: @escaping (OuroMDUpdateInstaller.Staged, URL) -> Void = { _, _ in },
        terminate: @escaping () -> Void = {},
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) -> OuroMDUpdateCoordinator {
        OuroMDUpdateCoordinator(
            defaults: defaults,
            checker: checker,
            stageUpdate: stageUpdate,
            applyAndRelaunch: applyAndRelaunch,
            applyOnQuit: applyOnQuit,
            terminate: terminate,
            now: now
        )
    }

    private func updateSnapshot(assets: [ReleaseUpdateAsset]? = nil) -> ReleaseUpdateSnapshot {
        ReleaseUpdateSnapshot(
            status: .updateAvailable,
            currentVersion: "0.9.0",
            latestVersion: "0.10.0",
            tagName: "v0.10.0",
            htmlURL: "https://github.com/ourostack/ouro-md/releases/tag/v0.10.0",
            assets: assets ?? [
                ReleaseUpdateAsset(
                    name: "Ouro-MD-0.10.0.zip",
                    downloadURL: "https://example.test/Ouro-MD-0.10.0.zip",
                    size: 100
                ),
                ReleaseUpdateAsset(
                    name: "Ouro-MD-0.10.0.manifest.json",
                    downloadURL: "https://example.test/Ouro-MD-0.10.0.manifest.json",
                    size: 50
                ),
            ],
            detail: "Version 0.10.0 is available."
        )
    }

    private func currentSnapshot() -> ReleaseUpdateSnapshot {
        ReleaseUpdateSnapshot(
            status: .current,
            currentVersion: "0.9.0",
            latestVersion: "0.9.0",
            tagName: "v0.9.0",
            htmlURL: "https://github.com/ourostack/ouro-md/releases/tag/v0.9.0",
            assets: [],
            detail: "Version 0.9.0 is current."
        )
    }

    private func unavailableSnapshot(detail: String) -> ReleaseUpdateSnapshot {
        ReleaseUpdateSnapshot(
            status: .unavailable,
            currentVersion: "0.9.0",
            latestVersion: nil,
            tagName: nil,
            htmlURL: nil,
            assets: [],
            detail: detail
        )
    }

    private func stagedUpdate(version: String) -> OuroMDUpdateInstaller.Staged {
        OuroMDUpdateInstaller.Staged(
            appURL: URL(fileURLWithPath: "/tmp/staged/Ouro MD.app"),
            stagingRoot: URL(fileURLWithPath: "/tmp/staged"),
            version: version
        )
    }
}
