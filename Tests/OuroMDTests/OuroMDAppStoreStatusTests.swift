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
        XCTAssertEqual(summary["appId"] as? String, "6787262892")
        XCTAssertEqual(summary["bundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(summary["teamId"] as? String, "743GT2AJ24")
        XCTAssertEqual(summary["currentAppStoreVersionId"] as? String, "7309944f-cbe8-4518-960c-444e6116ab46")
        XCTAssertEqual(summary["currentVersionString"] as? String, "0.9.79")
        XCTAssertEqual(summary["reviewSubmissionId"] as? String, "b37f847e-0ecb-4e7a-bb00-14e3038b0f4c")
        XCTAssertEqual(summary["reviewSubmissionState"] as? String, "UNRESOLVED_ISSUES")
        XCTAssertEqual(summary["reviewSubmissionItemState"] as? String, "REJECTED")
        XCTAssertEqual(summary["screenshotSetId"] as? String, "f37ecb51-c96e-451d-9b29-20d86d7f118e")
        XCTAssertEqual(summary["screenshotDisplayType"] as? String, "APP_DESKTOP")
        XCTAssertEqual(summary["screenshotCount"] as? Int, 1)

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
        XCTAssertTrue(result.stdout.contains("App 6787262892 (bot.ouro.md) on team 743GT2AJ24"))
        XCTAssertTrue(result.stdout.contains("Version 0.9.79 REJECTED"))
        XCTAssertTrue(result.stdout.contains("Review submission UNRESOLVED_ISSUES; item REJECTED"))
        XCTAssertTrue(result.stdout.contains("Screenshots 1 APP_DESKTOP"))
        XCTAssertFalse(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
        XCTAssertFalse(result.stdout.contains("PRIVATE KEY"))
        XCTAssertFalse(result.stdout.contains("Bearer "))
        XCTAssertFalse(result.stdout.contains("assetToken"))
    }

    private func runStatusReaderSelftest(json: Bool = true, extraArgs: [String] = []) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = [
            "node",
            "scripts/app-store-status.mjs",
            "--selftest"
        ]
        if json {
            arguments.append("--json")
        }
        process.arguments = arguments + extraArgs
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

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }
}
