import XCTest

final class OuroMDAppStoreRequestPlanTests: XCTestCase {
    func testDryRunPlanBuildsExactTargetVersionRequestGraph() throws {
        let result = try runRequestPlanner(arguments: ["--selftest", "--json"])

        XCTAssertEqual(result.status, 0, result.stderr)
        let plan = try parseJSONObject(result.stdout)
        XCTAssertEqual(plan["schemaVersion"] as? Int, 1)
        XCTAssertEqual(plan["mode"] as? String, "dry-run")
        XCTAssertEqual(plan["appId"] as? String, "6787262892")
        XCTAssertEqual(plan["bundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(plan["teamId"] as? String, "743GT2AJ24")
        XCTAssertEqual(plan["platform"] as? String, "MAC_OS")
        XCTAssertEqual(plan["targetVersion"] as? String, "0.9.80")
        XCTAssertEqual(plan["locale"] as? String, "en-US")
        XCTAssertEqual(plan["staleRejectedVersionIds"] as? [String], [
            "7309944f-cbe8-4518-960c-444e6116ab46",
            "5dca4b0b-3e0d-4913-acbd-b172f6c1bacb",
            "3bc7284e-27d5-4dd3-a049-b9e859289bd1",
            "f37ecb51-c96e-451d-9b29-20d86d7f118e",
            "80a8620a-643a-46bd-9e39-ab19f26ba424"
        ])

        let requests = try XCTUnwrap(plan["requests"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(requests.count, 18)

        let fetchVersion = try request(in: requests, id: "fetch-target-app-store-version")
        XCTAssertEqual(fetchVersion["method"] as? String, "GET")
        XCTAssertEqual(fetchVersion["path"] as? String, "/v1/apps/6787262892/appStoreVersions")
        XCTAssertEqual(fetchVersion["query"] as? [String: String], [
            "filter[platform]": "MAC_OS",
            "filter[versionString]": "0.9.80",
            "limit": "1"
        ])

        let createVersion = try request(in: requests, id: "create-target-app-store-version")
        XCTAssertEqual(createVersion["method"] as? String, "POST")
        XCTAssertEqual(createVersion["path"] as? String, "/v1/appStoreVersions")
        let createVersionBody = try XCTUnwrap(createVersion["body"] as? [String: Any])
        let createVersionData = try dataObject(createVersionBody)
        XCTAssertEqual(createVersionData["type"] as? String, "appStoreVersions")
        XCTAssertEqual(createVersionData["attributes"] as? [String: String], [
            "platform": "MAC_OS",
            "versionString": "0.9.80",
            "copyright": "Copyright © 2026 Ari Mendelow"
        ])
        XCTAssertEqual(
            relationshipId(createVersionData, relationship: "app", type: "apps"),
            "6787262892"
        )

        let createVersionLocalization = try request(in: requests, id: "create-version-localization")
        XCTAssertEqual(createVersionLocalization["method"] as? String, "POST")
        XCTAssertEqual(createVersionLocalization["path"] as? String, "/v1/appStoreVersionLocalizations")
        let versionLocalizationData = try dataObject(try XCTUnwrap(createVersionLocalization["body"] as? [String: Any]))
        let versionLocalizationAttributes = try XCTUnwrap(versionLocalizationData["attributes"] as? [String: String])
        XCTAssertEqual(versionLocalizationAttributes["locale"], "en-US")
        XCTAssertEqual(versionLocalizationAttributes["promotionalText"], "Local Markdown workspace for Mac files: folder search, outline, command palette, themes, PDF/HTML export, no account.")
        XCTAssertTrue(versionLocalizationAttributes["description"]?.hasPrefix("Ouro MD is a local Markdown workspace") == true)
        XCTAssertEqual(versionLocalizationAttributes["keywords"], "markdown,local files,folder search,outline,command palette,pdf,html export,gfm,mac")
        XCTAssertEqual(versionLocalizationAttributes["supportUrl"], "https://ouro.bot/support/")
        XCTAssertEqual(versionLocalizationAttributes["marketingUrl"], "https://ouro.bot/apps/ouro-md/")
        XCTAssertTrue(versionLocalizationAttributes["whatsNew"]?.localizedCaseInsensitiveContains("local Markdown workspace") == true)
        XCTAssertEqual(
            relationshipId(versionLocalizationData, relationship: "appStoreVersion", type: "appStoreVersions"),
            "${targetAppStoreVersionId}"
        )

        let updateAppInfoLocalization = try request(in: requests, id: "update-app-info-localization")
        XCTAssertEqual(updateAppInfoLocalization["method"] as? String, "PATCH")
        XCTAssertEqual(updateAppInfoLocalization["path"] as? String, "/v1/appInfoLocalizations/${appInfoLocalizationId}")
        let appInfoLocalizationData = try dataObject(try XCTUnwrap(updateAppInfoLocalization["body"] as? [String: Any]))
        XCTAssertEqual(appInfoLocalizationData["type"] as? String, "appInfoLocalizations")
        XCTAssertEqual(appInfoLocalizationData["id"] as? String, "${appInfoLocalizationId}")
        XCTAssertEqual(appInfoLocalizationData["attributes"] as? [String: String], [
            "name": "Ouro MD",
            "subtitle": "Local Markdown Workspace",
            "privacyPolicyUrl": "https://ouro.bot/privacy/"
        ])

        let updateAppCategory = try request(in: requests, id: "update-app-category")
        XCTAssertEqual(updateAppCategory["method"] as? String, "PATCH")
        XCTAssertEqual(updateAppCategory["path"] as? String, "/v1/appInfos/${appInfoId}")
        let appInfoData = try dataObject(try XCTUnwrap(updateAppCategory["body"] as? [String: Any]))
        XCTAssertEqual(relationshipId(appInfoData, relationship: "primaryCategory", type: "appCategories"), "DEVELOPER_TOOLS")

        let updateReviewDetail = try request(in: requests, id: "update-app-review-detail")
        XCTAssertEqual(updateReviewDetail["method"] as? String, "PATCH")
        XCTAssertEqual(updateReviewDetail["path"] as? String, "/v1/appStoreReviewDetails/${appStoreReviewDetailId}")
        let reviewDetailData = try dataObject(try XCTUnwrap(updateReviewDetail["body"] as? [String: Any]))
        let reviewDetailAttributes = try XCTUnwrap(reviewDetailData["attributes"] as? [String: String])
        XCTAssertTrue(reviewDetailAttributes["notes"]?.contains("Shift-Command-O") == true)
        XCTAssertTrue(reviewDetailAttributes["notes"]?.contains("Command Palette") == true)
        XCTAssertTrue(reviewDetailAttributes["notes"]?.contains("telemetry disabled") == true)

        let associateBuild = try request(in: requests, id: "associate-processed-build")
        XCTAssertEqual(associateBuild["method"] as? String, "PATCH")
        XCTAssertEqual(associateBuild["path"] as? String, "/v1/appStoreVersions/${targetAppStoreVersionId}/relationships/build")
        let associateBuildBody = try XCTUnwrap(associateBuild["body"] as? [String: Any])
        let associateBuildData = try XCTUnwrap(associateBuildBody["data"] as? [String: String])
        XCTAssertEqual(associateBuildData, ["type": "builds", "id": "${processedBuildId}"])

        let createSubmission = try request(in: requests, id: "create-review-submission")
        XCTAssertEqual(createSubmission["method"] as? String, "POST")
        XCTAssertEqual(createSubmission["path"] as? String, "/v1/reviewSubmissions")
        let submissionData = try dataObject(try XCTUnwrap(createSubmission["body"] as? [String: Any]))
        XCTAssertEqual(submissionData["attributes"] as? [String: String], ["platform": "MAC_OS"])
        XCTAssertEqual(relationshipId(submissionData, relationship: "app", type: "apps"), "6787262892")

        let createSubmissionItem = try request(in: requests, id: "create-review-submission-item")
        XCTAssertEqual(createSubmissionItem["method"] as? String, "POST")
        XCTAssertEqual(createSubmissionItem["path"] as? String, "/v1/reviewSubmissionItems")
        let submissionItemData = try dataObject(try XCTUnwrap(createSubmissionItem["body"] as? [String: Any]))
        XCTAssertEqual(relationshipId(submissionItemData, relationship: "reviewSubmission", type: "reviewSubmissions"), "${reviewSubmissionId}")
        XCTAssertEqual(relationshipId(submissionItemData, relationship: "appStoreVersion", type: "appStoreVersions"), "${targetAppStoreVersionId}")

        let submit = try request(in: requests, id: "submit-review-submission")
        XCTAssertEqual(submit["method"] as? String, "PATCH")
        XCTAssertEqual(submit["path"] as? String, "/v1/reviewSubmissions/${reviewSubmissionId}")
        let submitData = try dataObject(try XCTUnwrap(submit["body"] as? [String: Any]))
        XCTAssertEqual(submitData["attributes"] as? [String: Bool], ["submitted": true])
    }

    func testDryRunPlanIncludesMacScreenshotReservationUploadAndCommitSteps() throws {
        let result = try runRequestPlanner(arguments: ["--selftest", "--json"])

        XCTAssertEqual(result.status, 0, result.stderr)
        let plan = try parseJSONObject(result.stdout)
        let screenshots = try XCTUnwrap(plan["screenshots"] as? [[String: Any]])
        XCTAssertEqual(screenshots.map { $0["scene"] as? String }, [
            "folder-workspace",
            "command-palette",
            "search-outline",
            "themed-export-readability"
        ])
        XCTAssertTrue(screenshots.allSatisfy { ($0["fileSize"] as? Int ?? 0) > 0 })
        XCTAssertTrue(screenshots.allSatisfy { ($0["sourceFileChecksum"] as? String)?.hasPrefix("sha256:") == true })

        let requests = try XCTUnwrap(plan["requests"] as? [[String: Any]])
        let createSet = try request(in: requests, id: "create-desktop-screenshot-set")
        XCTAssertEqual(createSet["method"] as? String, "POST")
        XCTAssertEqual(createSet["path"] as? String, "/v1/appScreenshotSets")
        let createSetData = try dataObject(try XCTUnwrap(createSet["body"] as? [String: Any]))
        XCTAssertEqual(createSetData["attributes"] as? [String: String], ["screenshotDisplayType": "APP_DESKTOP"])
        XCTAssertEqual(
            relationshipId(createSetData, relationship: "appStoreVersionLocalization", type: "appStoreVersionLocalizations"),
            "${appStoreVersionLocalizationId}"
        )

        for (index, scene) in ["folder-workspace", "command-palette", "search-outline", "themed-export-readability"].enumerated() {
            let ordinal = String(format: "%02d", index + 1)
            let createScreenshot = try request(in: requests, id: "reserve-screenshot-\(ordinal)-\(scene)")
            XCTAssertEqual(createScreenshot["method"] as? String, "POST")
            XCTAssertEqual(createScreenshot["path"] as? String, "/v1/appScreenshots")
            let createScreenshotData = try dataObject(try XCTUnwrap(createScreenshot["body"] as? [String: Any]))
            XCTAssertEqual(relationshipId(createScreenshotData, relationship: "appScreenshotSet", type: "appScreenshotSets"), "${appScreenshotSetId}")
            let createAttributes = try XCTUnwrap(createScreenshotData["attributes"] as? [String: Any])
            XCTAssertEqual(createAttributes["fileName"] as? String, "\(ordinal)-\(scene).png")
            XCTAssertGreaterThan(createAttributes["fileSize"] as? Int ?? 0, 0)

            let upload = try request(in: requests, id: "upload-screenshot-\(ordinal)-\(scene)")
            XCTAssertEqual(upload["method"] as? String, "UPLOAD_OPERATIONS")
            XCTAssertEqual(upload["dependsOn"] as? String, "reserve-screenshot-\(ordinal)-\(scene)")
            XCTAssertEqual(upload["uploadOperationsSource"] as? String, "response.data.attributes.uploadOperations")
            XCTAssertTrue((upload["sourceFileChecksum"] as? String)?.hasPrefix("sha256:") == true)
            XCTAssertFalse((upload["body"] as? [String: Any])?.keys.contains("assetToken") == true)

            let commit = try request(in: requests, id: "commit-screenshot-\(ordinal)-\(scene)")
            XCTAssertEqual(commit["method"] as? String, "PATCH")
            XCTAssertEqual(commit["path"] as? String, "/v1/appScreenshots/${appScreenshotId:\(ordinal)-\(scene)}")
            let commitData = try dataObject(try XCTUnwrap(commit["body"] as? [String: Any]))
            XCTAssertEqual(commitData["type"] as? String, "appScreenshots")
            let commitAttributes = try XCTUnwrap(commitData["attributes"] as? [String: Any])
            XCTAssertEqual(commitAttributes["uploaded"] as? Bool, true)
            XCTAssertTrue((commitAttributes["sourceFileChecksum"] as? String)?.hasPrefix("sha256:") == true)
        }
    }

    func testDryRunPlanRecordsExistingRejectionThreadStrategyWithoutMutatingStaleSubmission() throws {
        let result = try runRequestPlanner(arguments: ["--selftest", "--json"])

        XCTAssertEqual(result.status, 0, result.stderr)
        let plan = try parseJSONObject(result.stdout)
        let rejectionThread = try XCTUnwrap(plan["existingRejectionThread"] as? [String: String])
        XCTAssertEqual(rejectionThread["reviewSubmissionId"], "b37f847e-0ecb-4e7a-bb00-14e3038b0f4c")
        XCTAssertEqual(rejectionThread["strategy"], "new-submission-review-notes")
        XCTAssertEqual(rejectionThread["reason"], "No supported App Store Connect API reply endpoint was planned for the rejected review thread.")

        let requests = try XCTUnwrap(plan["requests"] as? [[String: Any]])
        XCTAssertFalse(requests.contains { ($0["path"] as? String)?.contains("b37f847e-0ecb-4e7a-bb00-14e3038b0f4c") == true })
    }

    func testDryRunPlanRejectsStaleRejectedIdsForTargetGraph() throws {
        let result = try runRequestPlanner(arguments: ["--selftest-stale-ids", "--json"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("stale rejected App Store Connect id"))
        XCTAssertTrue(result.stderr.contains("7309944f-cbe8-4518-960c-444e6116ab46"))
        XCTAssertFalse(result.stderr.contains("assetToken"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testDryRunPlanOutputAndErrorsAreRedacted() throws {
        let result = try runRequestPlanner(arguments: ["--selftest", "--json"])

        XCTAssertEqual(result.status, 0, result.stderr)
        let combined = result.stdout + result.stderr
        for forbidden in [
            "PRIVATE KEY",
            "BEGIN PRIVATE KEY",
            "assetToken",
            "Authorization",
            "Bearer ",
            "AuthKey_",
            "eyJ"
        ] {
            XCTAssertFalse(combined.contains(forbidden), "request plan output leaked \(forbidden)")
        }
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

    private func parseJSONObject(_ text: String) throws -> [String: Any] {
        let data = try XCTUnwrap(text.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func request(in requests: [[String: Any]], id: String) throws -> [String: Any] {
        try XCTUnwrap(requests.first { $0["id"] as? String == id }, "Missing request \(id)")
    }

    private func dataObject(_ body: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(body["data"] as? [String: Any])
    }

    private func relationshipId(_ data: [String: Any], relationship: String, type: String) -> String? {
        guard
            let relationships = data["relationships"] as? [String: Any],
            let relationshipObject = relationships[relationship] as? [String: Any],
            let relationshipData = relationshipObject["data"] as? [String: String],
            relationshipData["type"] == type
        else { return nil }
        return relationshipData["id"]
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }
}
