import Foundation
import XCTest
@testable import OuroMD

final class ReleaseUpdateTests: XCTestCase {
    func testReleaseDescriptorMatchesCurrentDistribution() {
        XCTAssertEqual(OuroMDRelease.appName, "Ouro MD")
        XCTAssertEqual(OuroMDRelease.bundleIdentifier, "org.ourostack.ouro-md")
        XCTAssertEqual(OuroMDRelease.repository, "ourostack/ouro-md")
        XCTAssertEqual(OuroMDRelease.version, "0.9.0")
        XCTAssertEqual(OuroMDRelease.userAgent, "OuroMD/0.9.0")
    }

    func testSnapshotReportsUpdateAvailableFromLatestPublishedRelease() throws {
        let data = Data("""
        [
          {
            "tag_name": "v0.10.0",
            "html_url": "https://github.com/ourostack/ouro-md/releases/tag/v0.10.0",
            "draft": false,
            "prerelease": false,
            "assets": [
              {"name": "Ouro-MD-0.10.0.zip", "browser_download_url": "https://example.test/app.zip", "size": 100},
              {"name": "Ouro-MD-0.10.0.manifest.json", "browser_download_url": "https://example.test/manifest.json", "size": 50}
            ]
          }
        ]
        """.utf8)

        let snapshot = try ReleaseUpdateChecker.snapshot(from: data, currentVersion: "0.9.0")

        XCTAssertEqual(snapshot.status, .updateAvailable)
        XCTAssertEqual(snapshot.latestVersion, "0.10.0")
        XCTAssertEqual(snapshot.tagName, "v0.10.0")
        XCTAssertTrue(snapshot.hasInstallableAssets)
    }

    func testSnapshotReportsCurrentWhenLatestIsNotNewer() throws {
        let data = Data("""
        [
          {
            "tag_name": "v0.9.0",
            "html_url": "https://github.com/ourostack/ouro-md/releases/tag/v0.9.0",
            "draft": false,
            "prerelease": false,
            "assets": []
          }
        ]
        """.utf8)

        let snapshot = try ReleaseUpdateChecker.snapshot(from: data, currentVersion: "0.9.0")

        XCTAssertEqual(snapshot.status, .current)
        XCTAssertEqual(snapshot.detail, "Version 0.9.0 is current.")
    }

    func testSnapshotIgnoresDraftsAndReportsNoPublishedRelease() throws {
        let data = Data("""
        [
          {
            "tag_name": "v1.0.0",
            "html_url": "https://github.com/ourostack/ouro-md/releases/tag/v1.0.0",
            "draft": true,
            "prerelease": false,
            "assets": []
          }
        ]
        """.utf8)

        let snapshot = try ReleaseUpdateChecker.snapshot(from: data, currentVersion: "0.9.0")

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertNil(snapshot.latestVersion)
        XCTAssertEqual(snapshot.detail, "No published release found.")
    }

    func testSnapshotThrowsOnMalformedReleaseJSON() {
        let data = Data("{\"not\":\"an array\"}".utf8)

        XCTAssertThrowsError(try ReleaseUpdateChecker.snapshot(from: data, currentVersion: "0.9.0"))
    }

    func testAsyncCheckReturnsUnavailableSnapshotOnNetworkFailure() async {
        let checker = ReleaseUpdateChecker { _ in
            throw ReleaseUpdateError.badResponse
        }

        let snapshot = await checker.check()

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertEqual(snapshot.currentVersion, OuroMDRelease.version)
        XCTAssertTrue(snapshot.detail.contains("Release update check failed"))
    }
}
