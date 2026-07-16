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
        XCTAssertEqual(plan["targetVersion"] as? String, "0.9.83")
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
            "filter[versionString]": "0.9.83",
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
            "versionString": "0.9.83",
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
        XCTAssertTrue(versionLocalizationAttributes["whatsNew"]?.localizedCaseInsensitiveContains("file status") == true)
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

    func testDryRunPlanReusesExistingAppInfoLocalizationWhenProvided() throws {
        let result = try runRequestPlanner(arguments: [
            "--selftest",
            "--json",
            "--app-info-id", "app-info-current",
            "--app-info-localization-id", "app-info-localization-en-us"
        ])

        XCTAssertEqual(result.status, 0, result.stderr)
        let plan = try parseJSONObject(result.stdout)
        let requests = try XCTUnwrap(plan["requests"] as? [[String: Any]])
        XCTAssertFalse(requests.contains { $0["id"] as? String == "create-app-info-localization" })

        let updateAppInfoLocalization = try request(in: requests, id: "update-app-info-localization")
        XCTAssertEqual(updateAppInfoLocalization["method"] as? String, "PATCH")
        XCTAssertEqual(updateAppInfoLocalization["path"] as? String, "/v1/appInfoLocalizations/app-info-localization-en-us")
        let data = try dataObject(try XCTUnwrap(updateAppInfoLocalization["body"] as? [String: Any]))
        XCTAssertEqual(data["id"] as? String, "app-info-localization-en-us")
        XCTAssertEqual(data["attributes"] as? [String: String], [
            "name": "Ouro MD",
            "subtitle": "Local Markdown Workspace",
            "privacyPolicyUrl": "https://ouro.bot/privacy/"
        ])
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
        XCTAssertTrue(screenshots.allSatisfy { isMD5Checksum($0["sourceFileChecksum"] as? String) })

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
            XCTAssertTrue(isMD5Checksum(upload["sourceFileChecksum"] as? String))
            XCTAssertFalse((upload["body"] as? [String: Any])?.keys.contains("assetToken") == true)

            let commit = try request(in: requests, id: "commit-screenshot-\(ordinal)-\(scene)")
            XCTAssertEqual(commit["method"] as? String, "PATCH")
            XCTAssertEqual(commit["path"] as? String, "/v1/appScreenshots/${appScreenshotId:\(ordinal)-\(scene)}")
            let commitData = try dataObject(try XCTUnwrap(commit["body"] as? [String: Any]))
            XCTAssertEqual(commitData["type"] as? String, "appScreenshots")
            let commitAttributes = try XCTUnwrap(commitData["attributes"] as? [String: Any])
            XCTAssertEqual(commitAttributes["uploaded"] as? Bool, true)
            XCTAssertTrue(isMD5Checksum(commitAttributes["sourceFileChecksum"] as? String))
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

    func testDryRunPlanRejectsExplicitGeneratedResourceIds() throws {
        for (flag, value) in [
            ("--target-version-id", "target-version-existing"),
            ("--version-localization-id", "localization-existing"),
            ("--screenshot-set-id", "screenshot-set-existing"),
            ("--review-submission-id", "b37f847e-0ecb-4e7a-bb00-14e3038b0f4c")
        ] {
            let result = try runRequestPlanner(arguments: ["--selftest", "--json", flag, value])

            XCTAssertNotEqual(result.status, 0, "Expected \(flag) to be rejected")
            XCTAssertTrue(result.stderr.contains("\(flag) is not accepted for create-mode request plans"))
            XCTAssertFalse(result.stderr.contains("Bearer "))
        }
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

    func testDryRunPlanWritesTextArtifactWhenRequested() throws {
        let root = try makeTempDirectory()
        let artifact = root.appendingPathComponent("plan.txt")
        let result = try runRequestPlanner(arguments: [
            "--selftest",
            "--artifact",
            artifact.path
        ])

        XCTAssertEqual(result.status, 0, result.stderr)
        let artifactBody = try String(contentsOf: artifact, encoding: .utf8)
        XCTAssertEqual(artifactBody, result.stdout)
        XCTAssertTrue(result.stdout.contains("Dry-run App Store request plan for 6787262892 0.9.83 (MAC_OS)"))
        XCTAssertTrue(result.stdout.contains("Requests 30; screenshots 4"))
        XCTAssertFalse(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
    }

    func testDryRunPlanUsesLocalScreenshotInputsAndIgnoresRemoteProofUris() throws {
        let root = try makeTempDirectory()
        let screenshot = root.appendingPathComponent("01-local-workspace.png")
        try Data("local screenshot bytes".utf8).write(to: screenshot)

        let result = try runRequestPlanner(arguments: [
            "--json",
            "--screenshot",
            screenshot.path,
            "--screenshot",
            "asc://screenshots/existing-remote-proof"
        ])

        XCTAssertEqual(result.status, 0, result.stderr)
        let plan = try parseJSONObject(result.stdout)
        let screenshots = try XCTUnwrap(plan["screenshots"] as? [[String: Any]])
        XCTAssertEqual(screenshots.count, 1)
        XCTAssertEqual(screenshots.first?["scene"] as? String, "local-workspace")
        XCTAssertEqual(screenshots.first?["fileName"] as? String, "01-local-workspace.png")
        XCTAssertEqual(screenshots.first?["fileSize"] as? Int, "local screenshot bytes".utf8.count)
        XCTAssertTrue(isMD5Checksum(screenshots.first?["sourceFileChecksum"] as? String))
    }

    func testDryRunPlanDoesNotSubmitWhenManifestOnlyHasRemoteScreenshotProof() throws {
        let root = try makeTempDirectory()
        let manifest = root.appendingPathComponent("remote-proof-manifest.json")
        try writeText(
            """
            {
              "schemaVersion": 1,
              "app": {
                "name": "Ouro MD",
                "bundleId": "bot.ouro.md",
                "sku": "bot-ouro-md-macos",
                "primaryLocale": "en-US"
              },
              "team": { "teamId": "743GT2AJ24" },
              "channels": [
                {
                  "id": "mac-app-store",
                  "platform": "macos",
                  "distribution": "app-store",
                  "bundleId": "bot.ouro.md",
                  "store": {
                    "version": "0.9.83",
                    "category": "DEVELOPER_TOOLS",
                    "subtitle": "Local Markdown Workspace",
                    "promotionalText": "Local Markdown workspace for Mac files.",
                    "description": "Ouro MD is a local Markdown workspace for Mac files.",
                    "keywords": "markdown,local files,folder search,outline,command palette,pdf,html export,gfm,mac",
                    "reviewNotes": "Review path: no account is required.",
                    "screenshotRequirements": {
                      "minimumCount": 4,
                      "requiredScenes": [
                        "folder-workspace",
                        "command-palette",
                        "search-outline",
                        "themed-export-readability"
                      ]
                    },
                    "screenshots": [
                      "asc://screenshots/existing-remote-proof"
                    ]
                  }
                }
              ]
            }
            """,
            to: manifest
        )

        let result = try runRequestPlanner(arguments: ["--json", "--manifest", manifest.path])

        XCTAssertEqual(result.status, 0, result.stderr)
        let plan = try parseJSONObject(result.stdout)
        let screenshots = try XCTUnwrap(plan["screenshots"] as? [[String: Any]])
        XCTAssertEqual(screenshots.count, 0)

        let blockers = try XCTUnwrap(plan["blockers"] as? [[String: Any]])
        XCTAssertTrue(blockers.contains { $0["code"] as? String == "local-screenshots-required-for-submit" })
        XCTAssertTrue(blockers.contains { $0["code"] as? String == "required-screenshot-scenes-missing" })

        let requests = try XCTUnwrap(plan["requests"] as? [[String: Any]])
        XCTAssertTrue(requests.contains { $0["id"] as? String == "create-review-submission" })
        XCTAssertFalse(requests.contains { $0["id"] as? String == "create-review-submission-item" })
        XCTAssertFalse(requests.contains { $0["id"] as? String == "submit-review-submission" })
    }

    func testDryRunPlanIncludesSubmitOnlyAfterRequiredLocalScreenshots() throws {
        let root = try makeTempDirectory()
        let screenshotArgs = try [
            "folder-workspace",
            "command-palette",
            "search-outline",
            "themed-export-readability"
        ].flatMap { scene -> [String] in
            let screenshot = root.appendingPathComponent("\(scene).png")
            try Data("screenshot-\(scene)".utf8).write(to: screenshot)
            return ["--screenshot", screenshot.path]
        }

        let result = try runRequestPlanner(arguments: ["--json"] + screenshotArgs)

        XCTAssertEqual(result.status, 0, result.stderr)
        let plan = try parseJSONObject(result.stdout)
        let blockers = try XCTUnwrap(plan["blockers"] as? [[String: Any]])
        XCTAssertTrue(blockers.isEmpty)
        let screenshots = try XCTUnwrap(plan["screenshots"] as? [[String: Any]])
        XCTAssertEqual(screenshots.map { $0["scene"] as? String }, [
            "folder-workspace",
            "command-palette",
            "search-outline",
            "themed-export-readability"
        ])

        let requests = try XCTUnwrap(plan["requests"] as? [[String: Any]])
        XCTAssertTrue(requests.contains { $0["id"] as? String == "create-review-submission-item" })
        XCTAssertTrue(requests.contains { $0["id"] as? String == "submit-review-submission" })
    }

    func testDryRunPlanRejectsUnknownArguments() throws {
        let result = try runRequestPlanner(arguments: ["--bogus"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("unknown argument: --bogus"))
        XCTAssertFalse(result.stderr.contains("Bearer "))
    }

    func testDryRunPlanRejectsUnexpectedBundleInManifest() throws {
        let root = try makeTempDirectory()
        let manifest = root.appendingPathComponent("manifest.json")
        try writeText(
            """
            {
              "schemaVersion": 1,
              "app": { "name": "Ouro MD", "bundleId": "example.wrong", "primaryLocale": "en-US" },
              "team": { "teamId": "743GT2AJ24" },
              "channels": [
                {
                  "id": "mac-app-store",
                  "platform": "macos",
                  "distribution": "app-store",
                  "bundleId": "example.wrong",
                  "store": { "version": "0.9.83" }
                }
              ]
            }
            """,
            to: manifest
        )

        let result = try runRequestPlanner(arguments: ["--manifest", manifest.path, "--json"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("unexpected bundle id in manifest: example.wrong"))
    }

    func testDryRunPlanRejectsMissingReleaseHighlights() throws {
        let root = try makeTempDirectory()
        let release = root.appendingPathComponent("Release.swift")
        try writeText("public enum EmptyRelease {}\n", to: release)

        let result = try runRequestPlanner(arguments: ["--release-source", release.path, "--json"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("missing release highlights"))
        XCTAssertFalse(result.stderr.contains("PRIVATE KEY"))
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

    private func isMD5Checksum(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-md-request-plan-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }
}
