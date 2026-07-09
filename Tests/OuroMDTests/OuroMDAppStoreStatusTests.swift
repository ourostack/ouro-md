import XCTest

final class OuroMDAppStoreStatusTests: XCTestCase {
    func testStatusReaderSelftestNormalizesAndRedactsAppStoreConnectState() throws {
        let result = try runStatusReaderSelftest()

        guard result.status == 0 else {
            XCTFail(result.stderr)
            return
        }

        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let summary = try XCTUnwrap(object)

        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["statusPurpose"] as? String, "selftest")
        XCTAssertEqual(summary["usedRejectedAuditDefaults"] as? Bool, false)
        XCTAssertEqual(summary["appId"] as? String, "6787262892")
        XCTAssertEqual(summary["bundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(summary["teamId"] as? String, "743GT2AJ24")
        XCTAssertEqual(summary["currentAppStoreVersionId"] as? String, "7309944f-cbe8-4518-960c-444e6116ab46")
        XCTAssertEqual(summary["currentVersionString"] as? String, "0.9.79")
        XCTAssertEqual(summary["reviewSubmissionId"] as? String, "b37f847e-0ecb-4e7a-bb00-14e3038b0f4c")
        XCTAssertEqual(summary["reviewSubmissionState"] as? String, "UNRESOLVED_ISSUES")
        XCTAssertEqual(summary["reviewSubmissionItemAppStoreVersionId"] as? String, "7309944f-cbe8-4518-960c-444e6116ab46")
        XCTAssertEqual(summary["reviewSubmissionItemState"] as? String, "REJECTED")
        XCTAssertEqual(summary["screenshotSetId"] as? String, "f37ecb51-c96e-451d-9b29-20d86d7f118e")
        XCTAssertEqual(summary["screenshotDisplayType"] as? String, "APP_DESKTOP")
        XCTAssertEqual(summary["screenshotCount"] as? Int, 1)
        XCTAssertEqual(summary["screenshotDeliveryStates"] as? [String], ["COMPLETE"])

        let json = result.stdout
        for forbidden in [
            "PRIVATE KEY",
            "BEGIN PRIVATE KEY",
            "assetToken",
            "Authorization",
            "Bearer ",
            "AuthKey_",
            "eyJ"
        ] {
            XCTAssertFalse(json.contains(forbidden), "status output leaked \(forbidden)")
        }
    }

    func testStatusReaderFailsWhenRequiredLiveFieldsAreMissing() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--selftest-missing-fields"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("missing required field"))
        XCTAssertFalse(result.stderr.contains("PRIVATE KEY"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testStatusReaderTextSummaryIsCompactAndRedacted() throws {
        let result = try runStatusReaderSelftest(json: false)

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Purpose selftest"))
        XCTAssertTrue(result.stdout.contains("App 6787262892 (bot.ouro.md) on team 743GT2AJ24"))
        XCTAssertTrue(result.stdout.contains("Version 0.9.79 REJECTED"))
        XCTAssertTrue(result.stdout.contains("Review submission UNRESOLVED_ISSUES; item REJECTED"))
        XCTAssertTrue(result.stdout.contains("Screenshots 1 APP_DESKTOP COMPLETE"))
        XCTAssertFalse(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
        XCTAssertFalse(result.stdout.contains("PRIVATE KEY"))
        XCTAssertFalse(result.stdout.contains("Bearer "))
        XCTAssertFalse(result.stdout.contains("assetToken"))
    }

    func testStatusReaderRedactsMultilinePrivateKeysFromErrors() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--selftest-private-key-error"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(result.stderr.contains("BEGIN PRIVATE KEY"))
        XCTAssertFalse(result.stderr.contains("abc123"))
        XCTAssertFalse(result.stderr.contains("END PRIVATE KEY"))
    }

    func testStatusReaderMatchesReviewItemByAppStoreVersionRelationship() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--selftest-first-item-unrelated"])

        XCTAssertEqual(result.status, 0, result.stderr)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let summary = try XCTUnwrap(object)
        XCTAssertEqual(summary["reviewSubmissionItemId"] as? String, "matching-item")
        XCTAssertEqual(summary["reviewSubmissionItemState"] as? String, "REJECTED")
        XCTAssertEqual(summary["reviewSubmissionItemAppStoreVersionId"] as? String, "7309944f-cbe8-4518-960c-444e6116ab46")
    }

    func testStatusReaderRejectsReviewItemWithoutVersionRelationship() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--selftest-review-item-mismatch"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("no review submission item matched app store version"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testStatusReaderRequiresScreenshotDeliveryState() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--selftest-missing-screenshot-state"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("missing required field: screenshotDeliveryStates"))
        XCTAssertFalse(result.stderr.contains("assetToken"))
    }

    func testStatusReaderRequiresCompleteScreenshotDeliveryState() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--selftest-failed-screenshot-state"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("unexpected screenshot delivery state: FAILED"))
        XCTAssertFalse(result.stderr.contains("assetToken"))
    }

    func testStatusReaderRequiresDesktopScreenshotSet() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--selftest-non-desktop-screenshot-set"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("missing required field: APP_DESKTOP screenshot set"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testLiveStatusRequiresExplicitVersionIdsOrRejectedAuditFlag() throws {
        let result = try runStatusReader(arguments: [
            "node",
            "scripts/app-store-status.mjs",
            "--json"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("live status requires --version-id and --review-submission-id"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testRejectedAuditDefaultsAreExplicitInJsonAndText() throws {
        let jsonResult = try runStatusReader(arguments: [
            "node",
            "scripts/app-store-status.mjs",
            "--selftest",
            "--use-rejected-audit-defaults",
            "--json"
        ])

        XCTAssertEqual(jsonResult.status, 0, jsonResult.stderr)
        let data = try XCTUnwrap(jsonResult.stdout.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let summary = try XCTUnwrap(object)
        XCTAssertEqual(summary["statusPurpose"] as? String, "rejected-audit")
        XCTAssertEqual(summary["usedRejectedAuditDefaults"] as? Bool, true)
        XCTAssertEqual(summary["rejectedAuditDefaultVersionString"] as? String, "0.9.79")

        let textResult = try runStatusReader(arguments: [
            "node",
            "scripts/app-store-status.mjs",
            "--selftest",
            "--use-rejected-audit-defaults"
        ])

        XCTAssertEqual(textResult.status, 0, textResult.stderr)
        XCTAssertTrue(textResult.stdout.contains("Purpose rejected-audit; using rejected 0.9.79 defaults"))
    }

    func testStatusReaderRejectsUnexpectedBundleId() throws {
        let result = try runStatusReaderSelftest(extraArgs: ["--bundle-id", "example.wrong"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("unexpected bundle id"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testStatusReaderRejectsUnknownArguments() throws {
        let result = try runStatusReader(arguments: ["node", "scripts/app-store-status.mjs", "--selftest", "--bogus"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("unknown argument: --bogus"))
        XCTAssertFalse(result.stderr.contains("PRIVATE KEY"))
    }

    func testStatusReaderWritesJsonArtifactWhenRequested() throws {
        let root = try makeTempDirectory()
        let artifact = root.appendingPathComponent("status.json")
        let result = try runStatusReader(arguments: [
            "node",
            "scripts/app-store-status.mjs",
            "--selftest",
            "--json",
            "--artifact",
            artifact.path
        ])

        XCTAssertEqual(result.status, 0, result.stderr)
        let artifactBody = try String(contentsOf: artifact, encoding: .utf8)
        XCTAssertEqual(artifactBody, result.stdout)
        XCTAssertTrue(artifactBody.contains("\"schemaVersion\""))
        XCTAssertFalse(artifactBody.contains("Bearer "))
    }

    private func runStatusReaderSelftest(json: Bool = true, extraArgs: [String] = []) throws -> ProcessResult {
        var arguments = [
            "node",
            "scripts/app-store-status.mjs",
            "--selftest"
        ]
        if json {
            arguments.append("--json")
        }
        return try runStatusReader(arguments: arguments + extraArgs)
    }

    private func runStatusReader(arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-md-status-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }
}
