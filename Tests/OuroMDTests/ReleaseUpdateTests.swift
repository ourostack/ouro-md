import Foundation
import XCTest
@testable import OuroMD

final class ReleaseUpdateTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(RecordingURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(RecordingURLProtocol.self)
        super.tearDown()
    }

    override func tearDown() {
        RecordingURLProtocol.reset()
        super.tearDown()
    }

    func testReleaseDescriptorMatchesCurrentDistribution() {
        XCTAssertEqual(OuroMDRelease.appName, "Ouro MD")
        XCTAssertEqual(OuroMDRelease.bundleIdentifier, "org.ourostack.ouro-md")
        XCTAssertEqual(OuroMDRelease.repository, "ourostack/ouro-md")
        XCTAssertEqual(OuroMDRelease.version, "0.9.6")
        XCTAssertEqual(OuroMDRelease.userAgent, "OuroMD/0.9.6")
    }

    func testDefaultConfigurationTargetsOuroMDGitHubReleases() {
        let configuration = ReleaseUpdateConfiguration()

        XCTAssertEqual(configuration.repository, "ourostack/ouro-md")
        XCTAssertEqual(configuration.currentVersion, "0.9.6")
        XCTAssertEqual(
            configuration.releasesURL.absoluteString,
            "https://api.github.com/repos/ourostack/ouro-md/releases?per_page=10"
        )
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

    func testSnapshotIgnoresPrereleasesAndUsesLatestStableRelease() throws {
        let data = Data("""
        [
          {
            "tag_name": "v9.0.0-beta.1",
            "html_url": "https://github.com/ourostack/ouro-md/releases/tag/v9.0.0-beta.1",
            "draft": false,
            "prerelease": true,
            "assets": []
          },
          {
            "tag_name": "v0.10.0",
            "html_url": "https://github.com/ourostack/ouro-md/releases/tag/v0.10.0",
            "draft": false,
            "prerelease": false,
            "assets": []
          }
        ]
        """.utf8)

        let snapshot = try ReleaseUpdateChecker.snapshot(from: data, currentVersion: "0.9.0")

        XCTAssertEqual(snapshot.status, .updateAvailable)
        XCTAssertEqual(snapshot.latestVersion, "0.10.0")
        XCTAssertEqual(snapshot.tagName, "v0.10.0")
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

    func testSnapshotReportsUnavailableWhenReleaseTagCannotBeCompared() throws {
        let data = Data("""
        [
          {
            "tag_name": "banana",
            "html_url": "https://github.com/ourostack/ouro-md/releases/tag/banana",
            "draft": false,
            "prerelease": false,
            "assets": []
          }
        ]
        """.utf8)

        let snapshot = try ReleaseUpdateChecker.snapshot(from: data, currentVersion: "0.9.0")

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertEqual(snapshot.latestVersion, "banana")
        XCTAssertEqual(snapshot.detail, "Latest release banana could not be compared to 0.9.0.")
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

    func testAsyncCheckReturnsSnapshotOnLoaderSuccess() async {
        let data = Data("""
        [
          {
            "tag_name": "v0.9.1",
            "html_url": "https://github.com/ourostack/ouro-md/releases/tag/v0.9.1",
            "draft": false,
            "prerelease": false,
            "assets": []
          }
        ]
        """.utf8)
        let checker = ReleaseUpdateChecker { url in
            XCTAssertEqual(url.absoluteString, "https://api.github.com/repos/ourostack/ouro-md/releases?per_page=10")
            return data
        }

        let snapshot = await checker.check()

        XCTAssertEqual(snapshot.status, .current)
        XCTAssertEqual(snapshot.currentVersion, OuroMDRelease.version)
    }

    func testUpdatePlanErrorDescriptionsAreUserFacing() {
        XCTAssertEqual(
            OuroMDUpdatePlanError.notAnUpdate.errorDescription,
            "No newer release is available to install."
        )
        XCTAssertEqual(
            OuroMDUpdatePlanError.missingArchiveAsset.errorDescription,
            "The release is missing a downloadable app archive (.zip)."
        )
        XCTAssertEqual(
            OuroMDUpdatePlanError.missingManifestAsset.errorDescription,
            "The release is missing its artifact manifest (.manifest.json)."
        )
        XCTAssertEqual(
            OuroMDUpdatePlanError.badAssetURL.errorDescription,
            "The release asset download URL was not valid."
        )
    }

    func testUpdateVerificationFailureDescriptionsAreUserFacing() {
        let failures: [OuroMDUpdateVerification.Failure] = [
            .archiveNameMismatch(expected: "expected.zip", got: "actual.zip"),
            .sha256Mismatch(expected: "abc", got: "def"),
            .byteCountMismatch(expected: 10, got: 9),
            .bundleIdentifierMismatch(expected: "org.ourostack.ouro-md", got: "other.bundle"),
            .unreadableVersion(manifest: "banana", current: "0.9.1"),
            .notNewerThanCurrent(current: "0.9.1", candidate: "0.9.1"),
        ]

        for failure in failures {
            XCTAssertFalse((failure.errorDescription ?? "").isEmpty)
        }
    }

    func testSemanticVersionComparesMajorMinorAndPatch() throws {
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("1.0.0")), try XCTUnwrap(SemanticVersion("0.999.999")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("1.2.0")), try XCTUnwrap(SemanticVersion("1.1.9")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("1.2.3")), try XCTUnwrap(SemanticVersion("1.2.2")))
    }

    func testDefaultLoaderSendsExpectedGitHubRequestAndReturnsBody() async throws {
        let expectedData = Data("[{\"tag_name\":\"v0.9.0\",\"html_url\":\"https://example.test\",\"draft\":false,\"prerelease\":false,\"assets\":[]}]".utf8)
        RecordingURLProtocol.stub(statusCode: 200, data: expectedData)

        let data = try await ReleaseUpdateChecker.defaultDataLoader(
            URL(string: "https://api.github.com/repos/ourostack/ouro-md/releases?per_page=10")!
        )

        XCTAssertEqual(data, expectedData)
        let request = try XCTUnwrap(RecordingURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/ourostack/ouro-md/releases?per_page=10")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "OuroMD/0.9.6")
    }

    func testDefaultLoaderThrowsOnNonSuccessStatus() async {
        RecordingURLProtocol.stub(statusCode: 503, data: Data("unavailable".utf8))

        do {
            _ = try await ReleaseUpdateChecker.defaultDataLoader(
                URL(string: "https://api.github.com/repos/ourostack/ouro-md/releases?per_page=10")!
            )
            XCTFail("Expected badResponse for non-2xx status.")
        } catch {
            XCTAssertEqual(error as? ReleaseUpdateError, .badResponse)
        }
    }
}

private final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var stubStatusCode = 200
    private static var stubData = Data()
    private static var storedLastRequest: URLRequest?

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastRequest
    }

    static func stub(statusCode: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        stubStatusCode = statusCode
        stubData = data
        storedLastRequest = nil
    }

    static func reset() {
        stub(statusCode: 200, data: Data())
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.github.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let statusCode: Int
        let data: Data
        Self.lock.lock()
        Self.storedLastRequest = request
        statusCode = Self.stubStatusCode
        data = Self.stubData
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
