import XCTest
@testable import OuroMD

final class OuroMDUpdateTests: XCTestCase {
    private let bundleIdentifier = "bot.ouro.md"

    private func snapshot(
        status: ReleaseUpdateStatus = .updateAvailable,
        latest: String? = "0.10.0",
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

    func testPlannerAcceptsOuroMDReleaseAssets() throws {
        let plan = try OuroMDUpdatePlanner.plan(from: snapshot(assets: installableAssets)).get()

        XCTAssertEqual(plan.version, "0.10.0")
        XCTAssertNil(plan.build)
        XCTAssertEqual(plan.archiveName, "Ouro-MD-0.10.0.zip")
        XCTAssertEqual(plan.archiveURL.lastPathComponent, "Ouro-MD-0.10.0.zip")
        XCTAssertEqual(plan.manifestURL.lastPathComponent, "Ouro-MD-0.10.0.manifest.json")
    }

    func testPlannerRequiresHTTPSReleaseAssets() {
        let assets = [
            ReleaseUpdateAsset(
                name: "Ouro-MD-0.10.0.zip",
                downloadURL: "http://example.com/Ouro-MD-0.10.0.zip",
                size: 7_400_000
            ),
            installableAssets[1],
        ]

        let result = OuroMDUpdatePlanner.plan(from: snapshot(assets: assets))

        XCTAssertEqual(result, .failure(.badAssetURL))
    }

    private func manifest(
        sha: String = "abc123",
        bytes: Int = 7_400_000,
        version: String = "0.10.0",
        build: String = "0.10.0",
        archive: String = "Ouro-MD-0.10.0.zip"
    ) -> OuroMDUpdateManifest {
        OuroMDUpdateManifest(
            appName: "Ouro MD",
            bundleIdentifier: bundleIdentifier,
            version: version,
            build: build,
            archive: archive,
            sha256: sha,
            bytes: bytes
        )
    }

    func testVerificationAcceptsNewerOuroMDManifest() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(sha: "ABC123"),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: bundleIdentifier,
            currentVersion: "0.9.0"
        )

        XCTAssertNil(failure)
    }

    func testVerificationIgnoresBuildIdentityForOuroMDReleases() {
        let failure = OuroMDUpdateVerification.verify(
            manifest: manifest(version: "0.10.0", build: "1001"),
            downloadedArchiveName: "Ouro-MD-0.10.0.zip",
            downloadedSHA256: "abc123",
            downloadedBytes: 7_400_000,
            expectedBundleIdentifier: bundleIdentifier,
            currentVersion: "0.10.0"
        )

        XCTAssertEqual(failure, .notNewerThanCurrent(current: "0.10.0", candidate: "0.10.0"))
    }
}
