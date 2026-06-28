import Foundation
import OuroAppShellCore
import OuroMDCore

typealias ReleaseUpdateStatus = OuroAppShellCore.ReleaseUpdateStatus
typealias ReleaseUpdateAsset = OuroAppShellCore.ReleaseUpdateAsset
typealias ReleaseUpdateSnapshot = OuroAppShellCore.ReleaseUpdateSnapshot
typealias ReleaseUpdateError = OuroAppShellCore.ReleaseUpdateError
typealias SemanticVersion = OuroAppShellCore.SemanticVersion

enum OuroMDReleaseUpdate {
    static func configuration(
        repository: String = OuroMDRelease.repository,
        currentVersion: String = OuroMDRelease.version,
        releasesURL: URL? = nil,
        timeout: TimeInterval = 10
    ) -> OuroAppShellCore.ReleaseUpdateConfiguration {
        OuroAppShellCore.ReleaseUpdateConfiguration(
            identity: AppShellIdentity(
                appName: OuroMDRelease.appName,
                bundleIdentifier: OuroMDRelease.bundleIdentifier,
                repository: repository,
                version: currentVersion,
                userAgent: OuroMDRelease.userAgent
            ),
            releasePolicy: OuroMDShellContract.releaseUpdatePolicy,
            releasesURL: releasesURL,
            timeout: timeout
        )
    }

    static func checker(
        configuration: OuroAppShellCore.ReleaseUpdateConfiguration = configuration(),
        dataLoader: @escaping @Sendable (URLRequest) async throws -> Data = defaultDataLoader
    ) -> OuroAppShellCore.ReleaseUpdateChecker {
        OuroAppShellCore.ReleaseUpdateChecker(
            configuration: configuration,
            dataLoader: dataLoader
        )
    }

    static let defaultDataLoader: @Sendable (URLRequest) async throws -> Data = { request in
        try await OuroAppShellCore.ReleaseUpdateChecker.defaultDataLoader(request: request)
    }
}
