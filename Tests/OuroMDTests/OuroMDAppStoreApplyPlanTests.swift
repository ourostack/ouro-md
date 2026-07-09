import XCTest

final class OuroMDAppStoreApplyPlanTests: XCTestCase {
    func testApplyExecutorRequiresExplicitApplyMode() throws {
        let root = try makeTempDirectory()
        let plan = try makeSubmitCapablePlan(in: root)
        let transport = try makeSuccessfulFakeTransport(in: root)

        let result = try runApplyExecutor(arguments: [
            "--plan", plan.path,
            "--transport-fixture", transport.path,
            "--artifact-dir", root.appendingPathComponent("artifacts").path,
            "--json"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("mutation executor requires --mode apply"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testApplyExecutorRejectsBlockedDryRunPlans() throws {
        let root = try makeTempDirectory()
        let blockedPlan = try makeBlockedPlan(in: root)
        let transport = try makeSuccessfulFakeTransport(in: root)

        let result = try runApplyExecutor(arguments: [
            "--mode", "apply",
            "--plan", blockedPlan.path,
            "--transport-fixture", transport.path,
            "--artifact-dir", root.appendingPathComponent("artifacts").path,
            "--json"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("refusing to apply plan with blockers"))
        XCTAssertTrue(result.stderr.contains("local-screenshots-required-for-submit"))
        XCTAssertFalse(result.stderr.contains("assetToken"))
    }

    func testApplyExecutorExecutesFakeTransportAndWritesRedactedArtifacts() throws {
        let root = try makeTempDirectory()
        let plan = try makeSubmitCapablePlan(in: root)
        let transport = try makeSuccessfulFakeTransport(in: root)
        let artifactDir = root.appendingPathComponent("artifacts", isDirectory: true)

        let result = try runApplyExecutor(arguments: [
            "--mode", "apply",
            "--plan", plan.path,
            "--transport-fixture", transport.path,
            "--artifact-dir", artifactDir.path,
            "--json"
        ])

        XCTAssertEqual(result.status, 0, result.stderr)
        let summary = try parseJSONObject(result.stdout)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["mode"] as? String, "apply")
        XCTAssertEqual(summary["transport"] as? String, "fixture")
        XCTAssertEqual(summary["appId"] as? String, "6787262892")
        XCTAssertEqual(summary["targetVersion"] as? String, "0.9.80")
        XCTAssertEqual(summary["executedRequestCount"] as? Int, 30)
        XCTAssertEqual(summary["executedUploadOperationCount"] as? Int, 4)

        let resolvedIds = try XCTUnwrap(summary["resolvedIds"] as? [String: String])
        XCTAssertEqual(resolvedIds["targetAppStoreVersionId"], "target-version-0-9-80")
        XCTAssertEqual(resolvedIds["appStoreVersionLocalizationId"], "version-localization-en-us")
        XCTAssertEqual(resolvedIds["appScreenshotSetId"], "desktop-screenshot-set")
        XCTAssertEqual(resolvedIds["reviewSubmissionId"], "review-submission-new")

        let tracePath = try XCTUnwrap(summary["traceArtifact"] as? String)
        let trace = try parseJSONObject(String(contentsOfFile: tracePath, encoding: .utf8))
        let events = try XCTUnwrap(trace["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 34)
        XCTAssertTrue(events.contains { $0["kind"] as? String == "upload" })
        XCTAssertTrue(events.contains { $0["requestId"] as? String == "submit-review-submission" })

        let fetchVersionLocalizations = try event(in: events, requestId: "fetch-version-localizations")
        XCTAssertEqual(fetchVersionLocalizations["path"] as? String, "/v1/appStoreVersions/target-version-0-9-80/appStoreVersionLocalizations")

        let firstUpload = try event(in: events, requestId: "upload-screenshot-01-folder-workspace")
        XCTAssertEqual(firstUpload["kind"] as? String, "upload")
        XCTAssertEqual(firstUpload["url"] as? String, "https://upload.example.invalid/folder-workspace")
        XCTAssertEqual(firstUpload["fileSize"] as? Int, "ouro-md-folder-workspace-app-store-screenshot".utf8.count)
        XCTAssertTrue(isMD5Checksum(firstUpload["sourceFileChecksum"] as? String))
        XCTAssertFalse(String(describing: firstUpload).contains("assetToken"))

        let body = result.stdout + (try String(contentsOfFile: tracePath, encoding: .utf8))
        for forbidden in ["assetToken", "Bearer ", "PRIVATE KEY", "AuthKey_", "eyJ"] {
            XCTAssertFalse(body.contains(forbidden), "apply artifacts leaked \(forbidden)")
        }
    }

    func testApplyExecutorClassifiesRetryableFixtureErrors() throws {
        let root = try makeTempDirectory()
        let plan = try makeSubmitCapablePlan(in: root)
        let transport = try makeRetryableFakeTransport(in: root)

        let result = try runApplyExecutor(arguments: [
            "--mode", "apply",
            "--plan", plan.path,
            "--transport-fixture", transport.path,
            "--artifact-dir", root.appendingPathComponent("artifacts").path,
            "--json"
        ])

        XCTAssertNotEqual(result.status, 0)
        let failure = try parseJSONObject(result.stdout)
        XCTAssertEqual(failure["ok"] as? Bool, false)
        XCTAssertEqual(failure["retryable"] as? Bool, true)
        XCTAssertEqual(failure["failedRequestId"] as? String, "create-target-app-store-version")
        XCTAssertEqual(failure["status"] as? Int, 503)
        XCTAssertFalse(result.stdout.contains("Bearer "))
    }

    private func runApplyExecutor(arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "scripts/app-store-apply-plan.mjs"] + arguments
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

    private func makeSubmitCapablePlan(in root: URL) throws -> URL {
        let screenshots = try [
            "folder-workspace",
            "command-palette",
            "search-outline",
            "themed-export-readability"
        ].flatMap { scene -> [String] in
            let screenshot = root.appendingPathComponent("\(scene).png")
            try Data("ouro-md-\(scene)-app-store-screenshot".utf8).write(to: screenshot)
            return ["--screenshot", screenshot.path]
        }
        let plan = root.appendingPathComponent("submit-plan.json")
        let result = try runRequestPlanner(arguments: ["--json", "--artifact", plan.path] + screenshots)
        XCTAssertEqual(result.status, 0, result.stderr)
        return plan
    }

    private func makeBlockedPlan(in root: URL) throws -> URL {
        let plan = root.appendingPathComponent("blocked-plan.json")
        let result = try runRequestPlanner(arguments: ["--json", "--artifact", plan.path])
        XCTAssertEqual(result.status, 0, result.stderr)
        return plan
    }

    private func runRequestPlanner(arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "scripts/app-store-request-plan.mjs"] + arguments
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

    private func makeSuccessfulFakeTransport(in root: URL) throws -> URL {
        let fixture = root.appendingPathComponent("transport.json")
        try writeJSON([
            "responses": [
                "create-target-app-store-version": resource("appStoreVersions", "target-version-0-9-80"),
                "create-version-localization": resource("appStoreVersionLocalizations", "version-localization-en-us"),
                "create-app-info-localization": resource("appInfoLocalizations", "app-info-localization-en-us"),
                "create-desktop-screenshot-set": resource("appScreenshotSets", "desktop-screenshot-set"),
                "reserve-screenshot-01-folder-workspace": screenshotResource("screenshot-folder", uploadURL: "https://upload.example.invalid/folder-workspace"),
                "reserve-screenshot-02-command-palette": screenshotResource("screenshot-command", uploadURL: "https://upload.example.invalid/command-palette"),
                "reserve-screenshot-03-search-outline": screenshotResource("screenshot-search", uploadURL: "https://upload.example.invalid/search-outline"),
                "reserve-screenshot-04-themed-export-readability": screenshotResource("screenshot-themed", uploadURL: "https://upload.example.invalid/themed-export-readability"),
                "create-review-submission": resource("reviewSubmissions", "review-submission-new"),
                "create-review-submission-item": resource("reviewSubmissionItems", "review-submission-item-version"),
                "submit-review-submission": [
                    "data": [
                        "type": "reviewSubmissions",
                        "id": "review-submission-new",
                        "attributes": ["state": "SUBMITTED"]
                    ]
                ]
            ]
        ], to: fixture)
        return fixture
    }

    private func makeRetryableFakeTransport(in root: URL) throws -> URL {
        let fixture = root.appendingPathComponent("transport-retryable.json")
        try writeJSON([
            "errors": [
                "create-target-app-store-version": [
                    "status": 503,
                    "message": "temporary App Store Connect outage Bearer secret"
                ]
            ]
        ], to: fixture)
        return fixture
    }

    private func resource(_ type: String, _ id: String) -> [String: Any] {
        ["data": ["type": type, "id": id]]
    }

    private func screenshotResource(_ id: String, uploadURL: String) -> [String: Any] {
        [
            "data": [
                "type": "appScreenshots",
                "id": id,
                "attributes": [
                    "assetToken": "Bearer secret-token",
                    "uploadOperations": [
                        [
                            "method": "PUT",
                            "url": uploadURL,
                            "headers": ["Authorization": "Bearer upload-token"]
                        ]
                    ]
                ]
            ]
        ]
    }

    private func parseJSONObject(_ text: String) throws -> [String: Any] {
        let data = try XCTUnwrap(text.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func event(in events: [[String: Any]], requestId: String) throws -> [String: Any] {
        try XCTUnwrap(events.first { $0["requestId"] as? String == requestId }, "Missing event \(requestId)")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-md-apply-plan-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func isMD5Checksum(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }
}
