import XCTest

final class OuroMDAppStorePackageReadinessTests: XCTestCase {
    func testPackageReadinessWritesStructuredNonSecretArtifact() throws {
        let root = try makeTempDirectory()
        let artifact = root.appendingPathComponent("app-store-package-readiness.json")

        let result = try runPackageReadiness(arguments: [
            "--readiness",
            "--artifact", artifact.path
        ])

        assertNoSecretValueLeak(result.stdout, surface: "readiness stdout")
        assertNoSecretValueLeak(result.stderr, surface: "readiness stderr")
        XCTAssertEqual(result.status, 0, sanitizedDiagnostics(result))
        guard result.status == 0 else { return }

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.path), "readiness artifact was not written")
        guard FileManager.default.fileExists(atPath: artifact.path) else { return }

        let artifactBody = try String(contentsOf: artifact, encoding: .utf8)
        assertNoSecretValueLeak(artifactBody, surface: "readiness artifact")
        let readiness = try parseJSONObject(artifactBody)
        XCTAssertEqual(readiness["schemaVersion"] as? Int, 1)
        XCTAssertEqual(readiness["mode"] as? String, "readiness")

        let app = try XCTUnwrap(readiness["app"] as? [String: Any])
        XCTAssertEqual(app["bundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(app["sourceBundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(app["manifestBundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(app["channelBundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(app["buildScriptBundleId"] as? String, "bot.ouro.md")
        XCTAssertEqual(app["bundleIdCoherent"] as? Bool, true)
        XCTAssertEqual(app["sourceVersion"] as? String, try releaseVersion())
        XCTAssertEqual(app["manifestVersion"] as? String, try releaseVersion())
        XCTAssertEqual(app["versionCoherent"] as? Bool, true)

        let distribution = try XCTUnwrap(readiness["distribution"] as? [String: Any])
        XCTAssertEqual(distribution["channel"] as? String, "app-store")
        XCTAssertEqual(distribution["manifestDistribution"] as? String, "app-store")
        XCTAssertEqual(distribution["buildCommandChannel"] as? String, "app-store")
        XCTAssertEqual(distribution["packageScriptChannel"] as? String, "app-store")
        XCTAssertEqual(distribution["directUpdatesAllowed"] as? Bool, false)
        XCTAssertEqual(distribution["directUpdatesSource"] as? String, "Sources/OuroMD/OuroMDDistribution.swift")
        XCTAssertEqual(distribution["category"] as? String, "public.app-category.developer-tools")
        XCTAssertEqual(distribution["manifestCategory"] as? String, "public.app-category.developer-tools")
        XCTAssertEqual(distribution["buildScriptAppStoreCategory"] as? String, "public.app-category.developer-tools")
        XCTAssertEqual(distribution["usesNonExemptEncryption"] as? Bool, false)
        XCTAssertEqual(distribution["usesNonExemptEncryptionSource"] as? String, "make-app.sh")

        let telemetry = try XCTUnwrap(readiness["telemetry"] as? [String: Any])
        XCTAssertEqual(telemetry["defaultDisabled"] as? Bool, true)
        XCTAssertEqual(telemetry["posthogKeyEmbeddedByDefault"] as? Bool, false)
        XCTAssertEqual(telemetry["optInVariable"] as? String, "OURO_MD_APP_STORE_ENABLE_TELEMETRY")
        XCTAssertEqual(telemetry["manifestBuildCommandDisablesTelemetry"] as? Bool, true)
        XCTAssertEqual(telemetry["packageScriptDisablesTelemetryByDefault"] as? Bool, true)
        XCTAssertEqual(telemetry["buildScriptHonorsTelemetryDisable"] as? Bool, true)

        let package = try XCTUnwrap(readiness["package"] as? [String: Any])
        let buildEnvironment = try XCTUnwrap(package["buildEnvironment"] as? [String])
        XCTAssertTrue(buildEnvironment.contains("OURO_MD_DISTRIBUTION_CHANNEL=app-store"))
        XCTAssertTrue(buildEnvironment.contains("OURO_MD_TELEMETRY_DISABLED=1"))
        let manifestBuildEnvironment = try XCTUnwrap(package["manifestBuildEnvironment"] as? [String])
        XCTAssertTrue(manifestBuildEnvironment.contains("OURO_MD_DISTRIBUTION_CHANNEL=app-store"))
        XCTAssertTrue(manifestBuildEnvironment.contains("OURO_MD_TELEMETRY_DISABLED=1"))

        let secretScan = try XCTUnwrap(readiness["secretScan"] as? [String: Any])
        XCTAssertEqual(secretScan["ok"] as? Bool, true)
        XCTAssertTrue((secretScan["forbiddenMatches"] as? [String] ?? []).isEmpty)

        let blockers = try XCTUnwrap(readiness["blockers"] as? [[String: Any]])
        XCTAssertTrue(blockers.allSatisfy { blocker in
            guard let code = blocker["code"] as? String else { return false }
            return !code.localizedCaseInsensitiveContains("token")
                && !code.localizedCaseInsensitiveContains("key")
                && !code.localizedCaseInsensitiveContains("password")
        })

        for forbidden in ["BEGIN PRIVATE KEY", "Bearer ", "AuthKey_", "APPLE_APP_SPECIFIC_PASSWORD", "gho_", "eyJ"] {
            XCTAssertFalse(artifactBody.contains(forbidden), "readiness artifact leaked \(forbidden)")
        }
    }

    func testArtifactFlagRequiresReadinessMode() throws {
        let root = try makeTempDirectory()
        let artifact = root.appendingPathComponent("app-store-package-readiness.json")

        let result = try runPackageReadiness(arguments: [
            "--artifact", artifact.path
        ])

        assertNoSecretValueLeak(result.stdout, surface: "artifact misuse stdout")
        assertNoSecretValueLeak(result.stderr, surface: "artifact misuse stderr")
        XCTAssertEqual(result.status, 64, sanitizedDiagnostics(result))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path))
    }

    func testReadinessDoesNotEchoSecretShapedArtifactPath() throws {
        let root = try makeTempDirectory()
        let artifact = root.appendingPathComponent("AuthKey_1234567890.p8")

        let result = try runPackageReadiness(arguments: [
            "--readiness",
            "--artifact", artifact.path
        ])

        assertNoSecretValueLeak(result.stdout, surface: "secret-shaped artifact path stdout")
        assertNoSecretValueLeak(result.stderr, surface: "secret-shaped artifact path stderr")
        XCTAssertEqual(result.status, 0, sanitizedDiagnostics(result))
        guard result.status == 0 else { return }

        let artifactBody = try String(contentsOf: artifact, encoding: .utf8)
        assertNoSecretValueLeak(artifactBody, surface: "secret-shaped artifact path artifact")
    }

    func testReadinessSecretScanRedactsCredentialShapedFilenames() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let secretFixtureDirectory = repositoryRoot.appendingPathComponent(".unit-test-secret-scan", isDirectory: true)
        let secretFixture = secretFixtureDirectory.appendingPathComponent("AuthKey_1234567890.p8")
        try FileManager.default.createDirectory(at: secretFixtureDirectory, withIntermediateDirectories: true)
        try "not a real credential".write(to: secretFixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: secretFixtureDirectory) }

        let root = try makeTempDirectory()
        let artifact = root.appendingPathComponent("app-store-package-readiness.json")

        let result = try runPackageReadiness(arguments: [
            "--readiness",
            "--artifact", artifact.path
        ])

        assertNoSecretValueLeak(result.stdout, surface: "redacted secret scan stdout")
        assertNoSecretValueLeak(result.stderr, surface: "redacted secret scan stderr")
        XCTAssertEqual(result.status, 0, sanitizedDiagnostics(result))
        guard result.status == 0 else { return }

        let artifactBody = try String(contentsOf: artifact, encoding: .utf8)
        assertNoSecretValueLeak(artifactBody, surface: "redacted secret scan artifact")
        XCTAssertFalse(artifactBody.contains("AuthKey_1234567890.p8"))
        XCTAssertFalse(artifactBody.contains(".unit-test-secret-scan"))

        let readiness = try parseJSONObject(artifactBody)
        let secretScan = try XCTUnwrap(readiness["secretScan"] as? [String: Any])
        XCTAssertEqual(secretScan["ok"] as? Bool, false)
        XCTAssertEqual(secretScan["forbiddenMatches"] as? [String], ["[redacted-signing-material-filename]"])
    }

    private func runPackageReadiness(arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "scripts/package-app-store.sh"] + arguments
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

    private func releaseVersion() throws -> String {
        let source = try String(
            contentsOfFile: "Sources/OuroMDCore/OuroMDRelease.swift",
            encoding: .utf8
        )
        let pattern = #"static let version = "([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let match = try XCTUnwrap(regex.firstMatch(in: source, range: range))
        let versionRange = try XCTUnwrap(Range(match.range(at: 1), in: source))
        return String(source[versionRange])
    }

    private func assertNoSecretValueLeak(_ text: String, surface: String) {
        let patterns = [
            "-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----",
            "Bearer\\s+[A-Za-z0-9._-]{12,}",
            "gho_[A-Za-z0-9_]{20,}",
            "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
            "AuthKey_[A-Za-z0-9]{10}\\.p8"
        ]
        for pattern in patterns {
            XCTAssertNil(
                text.range(of: pattern, options: .regularExpression),
                "\(surface) leaked secret-shaped value matching \(pattern)"
            )
        }
    }

    private func sanitizedDiagnostics(_ result: ProcessResult) -> String {
        let firstLine = [result.stderr, result.stdout]
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .first
            .map(String.init) ?? ""
        let combined = "status=\(result.status); first diagnostic line: \(firstLine)"
        let replacements: [(String, String)] = [
            (#"-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH |)PRIVATE KEY-----"#, "[redacted-private-key]"),
            (#"Bearer\s+[A-Za-z0-9._-]{12,}"#, "Bearer [redacted]"),
            (#"gho_[A-Za-z0-9_]{20,}"#, "gho_[redacted]"),
            (#"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, "jwt.[redacted]"),
            (#"AuthKey_[A-Za-z0-9]{10}\.p8"#, "AuthKey_[redacted].p8")
        ]
        return replacements.reduce(combined) { current, replacement in
            current.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .regularExpression
            )
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-md-app-store-readiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }
}
