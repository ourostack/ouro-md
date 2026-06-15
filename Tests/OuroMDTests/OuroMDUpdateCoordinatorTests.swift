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

    func testPromptDisplayHelpersAreUserFacing() {
        XCTAssertEqual(
            OuroMDUpdatePrompt.installable(version: "0.10.0").message,
            "Ouro MD 0.10.0 is available. Install it now and relaunch?"
        )
        XCTAssertEqual(
            OuroMDUpdatePrompt.upToDate(version: "0.9.1").message,
            "You're on the latest version (0.9.1)."
        )
        XCTAssertEqual(OuroMDUpdatePrompt.failed(detail: "offline").message, "offline")
        XCTAssertTrue(OuroMDUpdatePrompt.installable(version: "0.10.0").isInstallable)
        XCTAssertFalse(OuroMDUpdatePrompt.upToDate(version: "0.9.1").isInstallable)
    }

    func testPromptPresentationBindingDismissesPrompt() {
        var events: [(String, [String: OuroMDTelemetryValue])] = []
        let coordinator = makeCoordinator(telemetry: { event, properties in events.append((event, properties)) })
        coordinator.updatePrompt = .installable(version: "0.10.0")

        let binding = coordinator.updatePromptIsPresented

        XCTAssertTrue(binding.wrappedValue)
        binding.wrappedValue = false
        XCTAssertNil(coordinator.updatePrompt)
        XCTAssertFalse(binding.wrappedValue)
        XCTAssertEqual(events.last?.0, "ouro_md_update_install_deferred")
        XCTAssertEqual(events.last?.1["version"], .string("0.10.0"))
        XCTAssertEqual(events.last?.1["reason"], .string("binding"))
    }

    func testDismissingNonInstallablePromptDoesNotEmitDeferredTelemetry() {
        var events: [(String, [String: OuroMDTelemetryValue])] = []
        let coordinator = makeCoordinator(telemetry: { event, properties in events.append((event, properties)) })
        coordinator.updatePrompt = .upToDate(version: "0.9.0")

        coordinator.dismissUpdatePrompt(reason: "acknowledged")

        XCTAssertNil(coordinator.updatePrompt)
        XCTAssertTrue(events.isEmpty)
    }

    func testBadgeAndPromptUseCheckedReleaseWhenNoUpdateIsStaged() async {
        let coordinator = makeCoordinator(checker: { self.updateSnapshot() })

        await coordinator.checkForReleaseUpdate()
        coordinator.presentUpdatePrompt()

        XCTAssertEqual(coordinator.updateBadgeText, "Update 0.10.0")
        XCTAssertEqual(coordinator.updatePrompt, .installable(version: "0.10.0"))
    }

    func testPromptFallsBackToStagedVersionWhenLatestSnapshotIsNotInstallable() async {
        var snapshots = [
            updateSnapshot(version: "0.10.0"),
            currentSnapshot(),
        ]
        let coordinator = makeCoordinator(
            checker: { snapshots.removeFirst() },
            stageUpdate: { plan, _ in self.stagedUpdate(version: plan.version) }
        )
        await coordinator.runAutoUpdateCheckIfDue()
        _ = await coordinator.checkForReleaseUpdate()

        coordinator.presentUpdatePrompt()

        XCTAssertEqual(coordinator.updatePrompt, .installable(version: "0.10.0"))
    }

    func testManualCheckClearsPendingStageWhenReleaseIsNoLongerInstallable() async {
        var snapshots = [
            updateSnapshot(version: "0.10.0"),
            currentSnapshot(),
        ]
        let coordinator = makeCoordinator(
            checker: { snapshots.removeFirst() },
            stageUpdate: { plan, _ in self.stagedUpdate(version: plan.version) }
        )
        await coordinator.runAutoUpdateCheckIfDue()
        XCTAssertEqual(coordinator.stagedUpdateVersion, "0.10.0")

        await coordinator.checkForUpdatesAndPromptInstall()

        XCTAssertNil(coordinator.stagedUpdateVersion)
        XCTAssertNil(coordinator.updateBadgeText)
        XCTAssertEqual(coordinator.updatePrompt, .upToDate(version: "0.9.0"))
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

        XCTAssertTrue(relaunchApplications.isEmpty)
        XCTAssertTrue(didTerminate)
        XCTAssertTrue(quitApplications.isEmpty)
        XCTAssertEqual(coordinator.installStatus, "Ready to install 0.10.0 after Ouro MD quits...")

        XCTAssertTrue(coordinator.applyPendingManualUpdateAndRelaunchIfNeeded())
        XCTAssertEqual(relaunchApplications, [staged])
        XCTAssertEqual(coordinator.installStatus, "Installing 0.10.0 and relaunching...")
    }

    func testManualInstallReportsStagingProgressBeforeApplying() async {
        let staged = stagedUpdate(version: "0.10.0")
        var relaunchApplications: [OuroMDUpdateInstaller.Staged] = []
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, progress in
                await progress("Downloading")
                return staged
            },
            applyAndRelaunch: { staged, _ in relaunchApplications.append(staged) }
        )
        await coordinator.checkForReleaseUpdate()

        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertTrue(relaunchApplications.isEmpty)
        XCTAssertEqual(coordinator.installStatus, "Ready to install 0.10.0 after Ouro MD quits...")
        XCTAssertTrue(coordinator.applyPendingManualUpdateAndRelaunchIfNeeded())
        XCTAssertEqual(relaunchApplications, [staged])
        XCTAssertEqual(coordinator.installStatus, "Installing 0.10.0 and relaunching...")
    }

    func testManualInstallRestagesWhenCheckedReleaseIsNewerThanPendingStage() async {
        var snapshots = [
            updateSnapshot(version: "0.10.0"),
            updateSnapshot(version: "0.11.0"),
        ]
        var stagedVersions: [String] = []
        var relaunchVersions: [String] = []
        let coordinator = makeCoordinator(
            checker: { snapshots.removeFirst() },
            stageUpdate: { plan, _ in
                stagedVersions.append(plan.version)
                return self.stagedUpdate(version: plan.version)
            },
            applyAndRelaunch: { staged, _ in relaunchVersions.append(staged.version) }
        )

        await coordinator.runAutoUpdateCheckIfDue()
        await coordinator.checkForUpdatesAndPromptInstall()
        XCTAssertEqual(coordinator.updatePrompt, .installable(version: "0.11.0"))
        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertEqual(stagedVersions, ["0.10.0", "0.11.0"])
        XCTAssertTrue(relaunchVersions.isEmpty)
        XCTAssertTrue(coordinator.applyPendingManualUpdateAndRelaunchIfNeeded())
        XCTAssertEqual(relaunchVersions, ["0.11.0"])
    }

    func testManualInstallOfPendingStageIsIdempotent() async {
        let staged = stagedUpdate(version: "0.10.0")
        var relaunchApplications: [OuroMDUpdateInstaller.Staged] = []
        var terminateCount = 0
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, _ in staged },
            applyAndRelaunch: { staged, _ in relaunchApplications.append(staged) },
            terminate: { terminateCount += 1 }
        )
        await coordinator.runAutoUpdateCheckIfDue()

        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))
        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertTrue(relaunchApplications.isEmpty)
        XCTAssertEqual(terminateCount, 1)
        XCTAssertTrue(coordinator.isInstalling)
    }

    func testCancelPendingManualInstallPreventsLaterApply() async {
        let staged = stagedUpdate(version: "0.10.0")
        var relaunchApplications: [OuroMDUpdateInstaller.Staged] = []
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, _ in staged },
            applyAndRelaunch: { staged, _ in relaunchApplications.append(staged) }
        )
        await coordinator.runAutoUpdateCheckIfDue()
        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        coordinator.cancelPendingManualInstall()

        XCTAssertFalse(coordinator.isInstalling)
        XCTAssertNil(coordinator.installStatus)
        XCTAssertFalse(coordinator.applyPendingManualUpdateAndRelaunchIfNeeded())
        XCTAssertTrue(relaunchApplications.isEmpty)
    }

    func testManualCheckAwaitsInFlightLaunchCheckBeforePrompting() async {
        let started = expectation(description: "checker started")
        var checkCount = 0
        var continuation: CheckedContinuation<ReleaseUpdateSnapshot, Never>?
        let coordinator = makeCoordinator(
            checker: {
                checkCount += 1
                started.fulfill()
                return await withCheckedContinuation { continuation = $0 }
            }
        )

        let launchCheck = Task { await coordinator.runAutoUpdateCheckIfDue() }
        await fulfillment(of: [started], timeout: 1)
        let manualCheck = Task { await coordinator.checkForUpdatesAndPromptInstall() }
        await Task.yield()

        XCTAssertNil(coordinator.updatePrompt)

        continuation?.resume(returning: updateSnapshot())
        await launchCheck.value
        await manualCheck.value

        XCTAssertEqual(checkCount, 1)
        XCTAssertEqual(coordinator.updatePrompt, .installable(version: "0.10.0"))
    }

    func testManualInstallFailureSetsFailedPromptForAppObserver() async {
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, _ in throw OuroMDUpdateInstaller.InstallError.download("offline") }
        )
        await coordinator.checkForReleaseUpdate()

        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertEqual(coordinator.installError, "Download failed: offline")
        XCTAssertEqual(coordinator.updatePrompt, .failed(detail: "Download failed: offline"))
    }

    func testManualInstallRequiresPriorCheck() async {
        let coordinator = makeCoordinator()

        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertEqual(coordinator.installError, "Check for an update first.")
        XCTAssertEqual(coordinator.updatePrompt, .failed(detail: "Check for an update first."))
    }

    func testManualInstallReportsPlannerFailure() async {
        let coordinator = makeCoordinator(checker: { self.currentSnapshot() })
        await coordinator.checkForReleaseUpdate()

        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertEqual(coordinator.installError, "No newer release is available to install.")
        XCTAssertEqual(coordinator.updatePrompt, .failed(detail: "No newer release is available to install."))
    }

    func testManualUpdateFlowCapturesTelemetryWithoutRawErrorDetails() async {
        let staged = stagedUpdate(version: "0.10.0")
        var events: [(String, [String: OuroMDTelemetryValue])] = []
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, _ in staged },
            telemetry: { event, properties in events.append((event, properties)) }
        )

        await coordinator.checkForUpdatesAndPromptInstall()
        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertEqual(events.map { $0.0 }, [
            "ouro_md_update_check_completed",
            "ouro_md_update_install_requested",
            "ouro_md_update_install_scheduled",
        ])
        XCTAssertEqual(events[0].1["trigger"], .string("manual"))
        XCTAssertEqual(events[0].1["status"], .string("updateAvailable"))
        XCTAssertEqual(events[0].1["current_version"], .string("0.9.0"))
        XCTAssertEqual(events[0].1["latest_version"], .string("0.10.0"))
        XCTAssertEqual(events[0].1["has_installable_assets"], .bool(true))
        XCTAssertNil(events[0].1["detail"])
        XCTAssertEqual(events[2].1["version"], .string("0.10.0"))
    }

    func testManualUpdateFailureTelemetryDoesNotLeakRawErrorDetails() async {
        var events: [(String, [String: OuroMDTelemetryValue])] = []
        let coordinator = makeCoordinator(
            checker: { self.updateSnapshot() },
            stageUpdate: { _, _ in
                throw NSError(
                    domain: "test",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "failed at /Users/ari/private.md with phc_should_not_leak",
                    ]
                )
            },
            telemetry: { event, properties in events.append((event, properties)) }
        )

        await coordinator.checkForReleaseUpdate()
        await coordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))

        XCTAssertEqual(events.last?.0, "ouro_md_update_install_failed")
        XCTAssertEqual(events.last?.1, ["code": .string("stage_failed")])

        let renderedTelemetry = events.flatMap { event, properties in
            [event] + properties.keys + properties.values.map { "\($0)" }
        }.joined(separator: " ")
        XCTAssertFalse(renderedTelemetry.contains("/Users/ari/private.md"))
        XCTAssertFalse(renderedTelemetry.contains("phc_should_not_leak"))
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
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) },
        telemetry: @escaping (String, [String: OuroMDTelemetryValue]) -> Void = { _, _ in }
    ) -> OuroMDUpdateCoordinator {
        OuroMDUpdateCoordinator(
            defaults: defaults,
            checker: checker,
            stageUpdate: stageUpdate,
            applyAndRelaunch: applyAndRelaunch,
            applyOnQuit: applyOnQuit,
            terminate: terminate,
            now: now,
            telemetry: telemetry
        )
    }

    private func updateSnapshot(version: String = "0.10.0", assets: [ReleaseUpdateAsset]? = nil) -> ReleaseUpdateSnapshot {
        ReleaseUpdateSnapshot(
            status: .updateAvailable,
            currentVersion: "0.9.0",
            latestVersion: version,
            tagName: "v\(version)",
            htmlURL: "https://github.com/ourostack/ouro-md/releases/tag/v\(version)",
            assets: assets ?? [
                ReleaseUpdateAsset(
                    name: "Ouro-MD-\(version).zip",
                    downloadURL: "https://example.test/Ouro-MD-\(version).zip",
                    size: 100
                ),
                ReleaseUpdateAsset(
                    name: "Ouro-MD-\(version).manifest.json",
                    downloadURL: "https://example.test/Ouro-MD-\(version).manifest.json",
                    size: 50
                ),
            ],
            detail: "Version \(version) is available."
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
