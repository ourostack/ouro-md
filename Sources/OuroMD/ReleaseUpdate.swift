import Foundation
import OuroAppShellCore
import OuroMDCore

typealias ReleaseUpdateStatus = OuroAppShellCore.ReleaseUpdateStatus
typealias ReleaseUpdateAsset = OuroAppShellCore.ReleaseUpdateAsset
typealias ReleaseUpdateSnapshot = OuroAppShellCore.ReleaseUpdateSnapshot
typealias ReleaseUpdateError = OuroAppShellCore.ReleaseUpdateError
typealias SemanticVersion = OuroAppShellCore.SemanticVersion

struct ReleaseUpdateConfiguration: Equatable, Sendable {
    var repository: String
    var currentVersion: String
    var releasesURL: URL

    init(
        repository: String = OuroMDRelease.repository,
        currentVersion: String = OuroMDRelease.version,
        releasesURL: URL? = nil
    ) {
        self.repository = repository
        self.currentVersion = currentVersion
        self.releasesURL = releasesURL ?? URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=10")!
    }

    var appShellIdentity: AppShellIdentity {
        AppShellIdentity(
            appName: OuroMDRelease.appName,
            bundleIdentifier: OuroMDRelease.bundleIdentifier,
            repository: repository,
            version: currentVersion,
            userAgent: OuroMDRelease.userAgent
        )
    }

    var appShellConfiguration: OuroAppShellCore.ReleaseUpdateConfiguration {
        OuroAppShellCore.ReleaseUpdateConfiguration(
            identity: appShellIdentity,
            releasePolicy: .stable(),
            releasesURL: releasesURL
        )
    }
}

struct ReleaseUpdateChecker: Sendable {
    var configuration: ReleaseUpdateConfiguration
    private let dataLoader: @Sendable (URL) async throws -> Data

    init(
        configuration: ReleaseUpdateConfiguration = ReleaseUpdateConfiguration(),
        dataLoader: @escaping @Sendable (URL) async throws -> Data = ReleaseUpdateChecker.defaultDataLoader
    ) {
        self.configuration = configuration
        self.dataLoader = dataLoader
    }

    func check() async -> ReleaseUpdateSnapshot {
        do {
            let data = try await dataLoader(configuration.releasesURL)
            return try Self.snapshot(from: data, configuration: configuration)
        } catch {
            return ReleaseUpdateSnapshot(
                status: .unavailable,
                currentVersion: configuration.currentVersion,
                latestVersion: nil,
                tagName: nil,
                htmlURL: nil,
                assets: [],
                assetNamingPolicy: configuration.appShellConfiguration.assetNamingPolicy,
                detail: "Release update check failed: \(error.localizedDescription)"
            )
        }
    }

    static func snapshot(from data: Data, currentVersion: String) throws -> ReleaseUpdateSnapshot {
        try OuroAppShellCore.ReleaseUpdateChecker.snapshot(
            from: data,
            currentVersion: currentVersion,
            assetNamingPolicy: .simpleArchiveAndManifest(),
            includePrereleases: false
        )
    }

    static func snapshot(from data: Data, configuration: ReleaseUpdateConfiguration) throws -> ReleaseUpdateSnapshot {
        try OuroAppShellCore.ReleaseUpdateChecker.snapshot(
            from: data,
            configuration: configuration.appShellConfiguration
        )
    }

    static let defaultDataLoader: @Sendable (URL) async throws -> Data = { url in
        try await OuroAppShellCore.ReleaseUpdateChecker.defaultDataLoader(
            request: ReleaseUpdateChecker.request(url: url)
        )
    }

    private static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(OuroMDRelease.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
