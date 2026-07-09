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
        XCTAssertEqual(app["sourceVersion"] as? String, try releaseVersion())
        XCTAssertEqual(app["manifestVersion"] as? String, try releaseVersion())
        XCTAssertEqual(app["versionCoherent"] as? Bool, true)

        let distribution = try XCTUnwrap(readiness["distribution"] as? [String: Any])
        XCTAssertEqual(distribution["channel"] as? String, "app-store")
        XCTAssertEqual(distribution["directUpdatesAllowed"] as? Bool, false)
        XCTAssertEqual(distribution["category"] as? String, "public.app-category.developer-tools")
        XCTAssertEqual(distribution["usesNonExemptEncryption"] as? Bool, false)

        let telemetry = try XCTUnwrap(readiness["telemetry"] as? [String: Any])
        XCTAssertEqual(telemetry["defaultDisabled"] as? Bool, true)
        XCTAssertEqual(telemetry["posthogKeyEmbeddedByDefault"] as? Bool, false)
        XCTAssertEqual(telemetry["optInVariable"] as? String, "OURO_MD_APP_STORE_ENABLE_TELEMETRY")

        let package = try XCTUnwrap(readiness["package"] as? [String: Any])
        let buildEnvironment = try XCTUnwrap(package["buildEnvironment"] as? [String])
        XCTAssertTrue(buildEnvironment.contains("OURO_MD_DISTRIBUTION_CHANNEL=app-store"))
        XCTAssertTrue(buildEnvironment.contains("OURO_MD_TELEMETRY_DISABLED=1"))

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
