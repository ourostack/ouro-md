import Foundation
import XCTest
@testable import OuroMD
import OuroAppShellCore
import OuroMDCore

final class ReleaseUpdateTests: XCTestCase {
    func testReleaseDescriptorMatchesCurrentDistribution() {
        XCTAssertEqual(OuroMDRelease.appName, "Ouro MD")
        XCTAssertEqual(OuroMDRelease.bundleIdentifier, "org.ourostack.ouro-md")
        XCTAssertEqual(OuroMDRelease.repository, "ourostack/ouro-md")
        XCTAssertFalse(OuroMDRelease.releaseDate.isEmpty)
        XCTAssertFalse(OuroMDRelease.releaseHighlights.isEmpty)
        XCTAssertTrue(
            OuroMDRelease.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
            "version should be semver, got \(OuroMDRelease.version)"
        )
        XCTAssertEqual(OuroMDRelease.userAgent, "OuroMD/\(OuroMDRelease.version)")
    }

    func testDefaultConfigurationTargetsStableOuroMDGitHubReleases() {
        let configuration = OuroMDReleaseUpdate.configuration()

        XCTAssertEqual(configuration.repository, OuroMDRelease.repository)
        XCTAssertEqual(configuration.currentVersion, OuroMDRelease.version)
        XCTAssertEqual(configuration.identity.appName, OuroMDRelease.appName)
        XCTAssertEqual(configuration.identity.bundleIdentifier, OuroMDRelease.bundleIdentifier)
        XCTAssertEqual(configuration.identity.repository, OuroMDRelease.repository)
        XCTAssertEqual(configuration.identity.version, OuroMDRelease.version)
        XCTAssertEqual(configuration.identity.userAgent, OuroMDRelease.userAgent)
        XCTAssertEqual(configuration.releasePolicy, OuroMDShellContract.releaseUpdatePolicy)
        XCTAssertEqual(
            configuration.releasePolicy,
            .stable(assetNamingPolicy: .versionedArchiveAndManifest(namePrefix: "Ouro-MD-"))
        )
        XCTAssertFalse(configuration.includePrereleases)
        XCTAssertEqual(
            configuration.releasesURL.absoluteString,
            "https://api.github.com/repos/ourostack/ouro-md/releases?per_page=10"
        )
    }

    func testCustomConfigurationFlowsIntoShellConfiguration() {
        let releasesURL = URL(string: "https://updates.example.test/ouro-md/releases")!
        let configuration = OuroMDReleaseUpdate.configuration(
            repository: "example/ouro-md",
            currentVersion: "0.8.0",
            releasesURL: releasesURL,
            timeout: 42
        )

        XCTAssertEqual(configuration.repository, "example/ouro-md")
        XCTAssertEqual(configuration.currentVersion, "0.8.0")
        XCTAssertEqual(configuration.identity.repository, "example/ouro-md")
        XCTAssertEqual(configuration.identity.version, "0.8.0")
        XCTAssertEqual(configuration.identity.appName, OuroMDRelease.appName)
        XCTAssertEqual(configuration.identity.bundleIdentifier, OuroMDRelease.bundleIdentifier)
        XCTAssertEqual(configuration.identity.userAgent, OuroMDRelease.userAgent)
        XCTAssertEqual(configuration.releasePolicy, OuroMDShellContract.releaseUpdatePolicy)
        XCTAssertEqual(configuration.releasesURL, releasesURL)
        XCTAssertEqual(configuration.timeout, 42)
    }

    func testCheckerConstructionUsesOuroMDConfiguration() {
        let releasesURL = URL(string: "https://updates.example.test/ouro-md/releases")!
        let configuration = OuroMDReleaseUpdate.configuration(
            currentVersion: "0.8.0",
            releasesURL: releasesURL,
            timeout: 42
        )

        let checker = OuroMDReleaseUpdate.checker(configuration: configuration)

        XCTAssertEqual(checker.configuration, configuration)
    }
}
