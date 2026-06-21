import XCTest
@testable import OuroMD

@MainActor
final class TerminationSaveCoordinatorTests: XCTestCase {
    func testRepliesTrueImmediatelyWhenNothingIsDirty() async {
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []

        TerminationSaveCoordinator.saveAll(
            [],
            timeout: nil,
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        )

        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(replies, [true])
    }

    func testRepliesTrueOnlyAfterAllSavesSucceed() async {
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []
        var didCancel = false
        var firstSave: ((Bool) -> Void)?
        var secondSave: ((Bool) -> Void)?

        TerminationSaveCoordinator.saveAll(
            [
                { firstSave = $0 },
                { secondSave = $0 },
            ],
            timeout: nil,
            onCancel: { didCancel = true },
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        )

        firstSave?(true)
        await Task.yield()
        XCTAssertTrue(replies.isEmpty)

        secondSave?(true)
        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(replies, [true])
        XCTAssertFalse(didCancel)
    }

    func testRepliesFalseAndCancelsWhenAnySaveFails() async {
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []
        var cancelCount = 0
        var lateSave: ((Bool) -> Void)?

        TerminationSaveCoordinator.saveAll(
            [
                { $0(false) },
                { lateSave = $0 },
            ],
            timeout: nil,
            onCancel: { cancelCount += 1 },
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        )

        await fulfillment(of: [replied], timeout: 1)
        lateSave?(true)
        await Task.yield()

        XCTAssertEqual(replies, [false])
        XCTAssertEqual(cancelCount, 1)
    }

    func testDefaultCancelHandlerIsSafeWhenSaveFails() async {
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []

        TerminationSaveCoordinator.saveAll(
            [{ $0(false) }],
            timeout: nil,
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        )

        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(replies, [false])
    }

    func testTimeoutCancelsInsteadOfForcingQuit() async {
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []
        var didCancel = false

        TerminationSaveCoordinator.saveAll(
            [{ _ in }],
            timeout: 0.01,
            onCancel: { didCancel = true },
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        )

        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(replies, [false])
        XCTAssertTrue(didCancel)
    }

    func testSaveFailureCancelsPendingManualUpdateBeforeQuitReply() async {
        let replied = expectation(description: "termination reply")
        var replies: [Bool] = []
        var didApply = false
        let destination = URL(fileURLWithPath: "/tmp/Ouro MD.app")
        let staged = OuroMDUpdateInstaller.Staged(
            appURL: URL(fileURLWithPath: "/tmp/staged/Ouro MD.app"),
            stagingRoot: URL(fileURLWithPath: "/tmp/staged"),
            version: "0.10.0"
        )
        let suiteName = "TerminationSaveCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let coordinator = OuroMDUpdateCoordinator(
            defaults: defaults,
            checker: {
                ReleaseUpdateSnapshot(
                    status: .updateAvailable,
                    currentVersion: "0.9.0",
                    latestVersion: "0.10.0",
                    tagName: "v0.10.0",
                    htmlURL: "https://github.com/ourostack/ouro-md/releases/tag/v0.10.0",
                    assets: [
                        ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.zip", downloadURL: "https://example.test/Ouro-MD-0.10.0.zip", size: 100),
                        ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.manifest.json", downloadURL: "https://example.test/Ouro-MD-0.10.0.manifest.json", size: 50),
                    ],
                    detail: "Version 0.10.0 is available."
                )
            },
            stageUpdate: { _, _ in staged },
            applyAndRelaunch: { _, _ in didApply = true },
            terminate: {}
        )
        await coordinator.checkForReleaseUpdate()
        await coordinator.installReleaseUpdate(destinationBundle: destination)
        XCTAssertTrue(coordinator.isInstalling)

        TerminationSaveCoordinator.saveAll(
            [{ $0(false) }],
            timeout: nil,
            onCancel: { coordinator.cancelPendingManualInstall() },
            reply: {
                replies.append($0)
                replied.fulfill()
            }
        )

        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(replies, [false])
        XCTAssertFalse(coordinator.applyPendingManualUpdateAndRelaunchIfNeeded())
        XCTAssertFalse(didApply)
        XCTAssertEqual(coordinator.installProgress.phase, .cancelled)
        XCTAssertTrue(coordinator.installProgress.canRetry)
    }

}
