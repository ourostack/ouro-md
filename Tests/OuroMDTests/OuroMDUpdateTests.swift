import XCTest
@testable import OuroMD

final class OuroMDUpdateTests: XCTestCase {
    private func snapshot(
        status: ReleaseUpdateStatus,
        latest: String?,
        assets: [ReleaseUpdateAsset]
    ) -> ReleaseUpdateSnapshot {
        ReleaseUpdateSnapshot(
            status: status,
            currentVersion: "0.9.0",
            latestVersion: latest,
            tagName: latest.map { "v\($0)" },
            htmlURL: "https://github.com/ourostack/ouro-md/releases/latest",
            assets: assets,
            detail: ""
        )
    }

    private var installableAssets: [ReleaseUpdateAsset] {
        [
            ReleaseUpdateAsset(
                name: "Ouro-MD-0.10.0.zip",
                downloadURL: "https://example.com/Ouro-MD-0.10.0.zip",
                size: 7_400_000
            ),
            ReleaseUpdateAsset(
                name: "Ouro-MD-0.10.0.manifest.json",
                downloadURL: "https://example.com/Ouro-MD-0.10.0.manifest.json",
                size: 350
            ),
        ]
    }

    func testPlanPicksZipAndManifestAssets() throws {
        let plan = try OuroMDUpdatePlanner.plan(
            from: snapshot(status: .updateAvailable, latest: "0.10.0", assets: installableAssets)
        ).get()

        XCTAssertEqual(plan.version, "0.10.0")
        XCTAssertEqual(plan.archiveName, "Ouro-MD-0.10.0.zip")
        XCTAssertEqual(plan.archiveURL.lastPathComponent, "Ouro-MD-0.10.0.zip")
        XCTAssertEqual(plan.manifestURL.lastPathComponent, "Ouro-MD-0.10.0.manifest.json")
    }

    func testPlanFailsWhenNotAnUpdate() {
        let result = OuroMDUpdatePlanner.plan(
            from: snapshot(status: .current, latest: "0.9.0", assets: installableAssets)
        )

        XCTAssertEqual(result, .failure(.notAnUpdate))
    }

    func testPlanFailsWhenArchiveMissing() {
        let result = OuroMDUpdatePlanner.plan(
            from: snapshot(status: .updateAvailable, latest: "0.10.0", assets: [installableAssets[1]])
        )

        XCTAssertEqual(result, .failure(.missingArchiveAsset))
    }

    func testPlanFailsWhenManifestMissing() {
        let result = OuroMDUpdatePlanner.plan(
            from: snapshot(status: .updateAvailable, latest: "0.10.0", assets: [installableAssets[0]])
        )

        XCTAssertEqual(result, .failure(.missingManifestAsset))
    }

    func testPlanFailsWhenAssetURLIsInvalid() {
        let assets = [
            ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.zip", downloadURL: "not a url", size: 10),
            ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.manifest.json", downloadURL: "https://example.com/manifest.json", size: 10),
        ]

        let result = OuroMDUpdatePlanner.plan(
            from: snapshot(status: .updateAvailable, latest: "0.10.0", assets: assets)
        )

        XCTAssertEqual(result, .failure(.badAssetURL))
    }

    func testPlanRejectsPlainHTTPAssetURLs() {
        let assets = [
            ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.zip", downloadURL: "http://example.com/app.zip", size: 10),
            ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.manifest.json", downloadURL: "https://example.com/manifest.json", size: 10),
        ]

        let result = OuroMDUpdatePlanner.plan(
            from: snapshot(status: .updateAvailable, latest: "0.10.0", assets: assets)
        )

        XCTAssertEqual(result, .failure(.badAssetURL))
    }

    private func manifest(
        sha: String = "abc123",
        bytes: Int = 7_400_000,
        bundleID: String = "org.ourostack.ouro-md",
        version: String = "0.10.0",
        archive: String = "Ouro-MD-0.10.0.zip"
    ) -> OuroMDUpdateManifest {
        OuroMDUpdateManifest(
            appName: "Ouro MD",
            bundleIdentifier: bundleID,
            version: version,
            build: version,
            archive: archive,
            sha256: sha,
            bytes: bytes
        )
    }

    func testVerifyPassesWhenEverythingMatches() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(sha: "ABC123"),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0"
        )

        XCTAssertNil(failure)
    }

    func testVerifyFailsOnSHAMismatch() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(sha: "abc123"),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "deadbeef",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0"
        )

        XCTAssertEqual(failure, .sha256Mismatch(expected: "abc123", got: "deadbeef"))
    }

    func testVerifyFailsOnByteCountMismatch() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(bytes: 7_400_000),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 42,
            expectedBundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0"
        )

        XCTAssertEqual(failure, .byteCountMismatch(expected: 7_400_000, got: 42))
    }

    func testVerifyFailsOnBundleIdentifierMismatch() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(bundleID: "com.example.bad"),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0"
        )

        XCTAssertEqual(failure, .bundleIdentifierMismatch(expected: "org.ourostack.ouro-md", got: "com.example.bad"))
    }

    func testVerifyFailsWhenArchiveNameDiffersFromManifest() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(archive: "Ouro-MD-0.10.0.zip"),
            downloadedArchiveName: "different.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0"
        )

        XCTAssertEqual(failure, .archiveNameMismatch(expected: "Ouro-MD-0.10.0.zip", got: "different.zip"))
    }

    func testVerifyFailsWhenNotNewerThanCurrent() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(version: "0.9.0"),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0"
        )

        XCTAssertEqual(failure, .notNewerThanCurrent(current: "0.9.0", candidate: "0.9.0"))
    }

    func testVerifyFailsWhenVersionCannotBeCompared() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(version: "banana"),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0"
        )

        XCTAssertEqual(failure, .unreadableVersion(manifest: "banana", current: "0.9.0"))
    }

    func testAutoUpdatePolicyChecksWhenNeverCheckedBefore() {
        XCTAssertTrue(
            OuroMDAutoUpdatePolicy.shouldCheck(
                now: Date(timeIntervalSince1970: 1000),
                lastCheck: nil,
                minimumInterval: 3600,
                enabled: true
            )
        )
    }

    func testAutoUpdatePolicySkipsWhenDisabled() {
        XCTAssertFalse(
            OuroMDAutoUpdatePolicy.shouldCheck(
                now: Date(timeIntervalSince1970: 100_000),
                lastCheck: nil,
                minimumInterval: 3600,
                enabled: false
            )
        )
    }

    func testAutoUpdatePolicyThrottlesWithinInterval() {
        let last = Date(timeIntervalSince1970: 100_000)
        XCTAssertFalse(
            OuroMDAutoUpdatePolicy.shouldCheck(
                now: last.addingTimeInterval(1800),
                lastCheck: last,
                minimumInterval: 3600,
                enabled: true
            )
        )
    }

    func testAutoUpdatePolicyChecksAfterInterval() {
        let last = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(
            OuroMDAutoUpdatePolicy.shouldCheck(
                now: last.addingTimeInterval(3600),
                lastCheck: last,
                minimumInterval: 3600,
                enabled: true
            )
        )
    }

    func testManifestDecodesFromReleaseJSON() throws {
        let json = """
        {
          "appName": "Ouro MD",
          "bundleIdentifier": "org.ourostack.ouro-md",
          "version": "0.10.0",
          "build": "0.10.0",
          "gitSha": "abcdef1",
          "archive": "Ouro-MD-0.10.0.zip",
          "sha256": "05abb1975c8cb04afc0b5988428e6e0e9af5b46217ab519873c66f885a4d2050",
          "bytes": 7400000,
          "createdAt": "2026-06-14T00:00:00Z"
        }
        """

        let manifest = try JSONDecoder().decode(OuroMDUpdateManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.appName, "Ouro MD")
        XCTAssertEqual(manifest.version, "0.10.0")
        XCTAssertEqual(manifest.bytes, 7_400_000)
        XCTAssertEqual(manifest.sha256, "05abb1975c8cb04afc0b5988428e6e0e9af5b46217ab519873c66f885a4d2050")
    }
}
