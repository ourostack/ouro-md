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
}
