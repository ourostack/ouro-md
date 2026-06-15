import Foundation

struct OuroMDUpdateManifest: Codable, Equatable, Sendable {
    var appName: String
    var bundleIdentifier: String
    var version: String
    var build: String
    var archive: String
    var sha256: String
    var bytes: Int
}

struct OuroMDUpdatePlan: Equatable, Sendable {
    var version: String
    var archiveURL: URL
    var archiveName: String
    var manifestURL: URL
}

enum OuroMDUpdatePlanError: Error, Equatable, LocalizedError, Sendable {
    case notAnUpdate
    case missingArchiveAsset
    case missingManifestAsset
    case badAssetURL

    var errorDescription: String? {
        switch self {
        case .notAnUpdate:
            return "No newer release is available to install."
        case .missingArchiveAsset:
            return "The release is missing a downloadable app archive (.zip)."
        case .missingManifestAsset:
            return "The release is missing its artifact manifest (.manifest.json)."
        case .badAssetURL:
            return "The release asset download URL was not valid."
        }
    }
}

enum OuroMDUpdatePlanner {
    static func plan(from snapshot: ReleaseUpdateSnapshot) -> Result<OuroMDUpdatePlan, OuroMDUpdatePlanError> {
        guard snapshot.status == .updateAvailable, let version = snapshot.latestVersion else {
            return .failure(.notAnUpdate)
        }
        guard let archive = snapshot.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            return .failure(.missingArchiveAsset)
        }
        guard let manifest = snapshot.assets.first(where: { $0.name.hasSuffix(".manifest.json") }) else {
            return .failure(.missingManifestAsset)
        }
        guard let archiveURL = validHTTPURL(archive.downloadURL),
              let manifestURL = validHTTPURL(manifest.downloadURL)
        else {
            return .failure(.badAssetURL)
        }
        return .success(
            OuroMDUpdatePlan(
                version: version,
                archiveURL: archiveURL,
                archiveName: archive.name,
                manifestURL: manifestURL
            )
        )
    }

    private static func validHTTPURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host != nil
        else {
            return nil
        }
        return url
    }
}

enum OuroMDAutoUpdatePolicy {
    static func shouldCheck(
        now: Date,
        lastCheck: Date?,
        minimumInterval: TimeInterval,
        enabled: Bool
    ) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= minimumInterval
    }
}

enum OuroMDUpdateVerification {
    enum Failure: Error, Equatable, LocalizedError, Sendable {
        case archiveNameMismatch(expected: String, got: String)
        case sha256Mismatch(expected: String, got: String)
        case byteCountMismatch(expected: Int, got: Int)
        case bundleIdentifierMismatch(expected: String, got: String)
        case unreadableVersion(manifest: String, current: String)
        case notNewerThanCurrent(current: String, candidate: String)

        var errorDescription: String? {
            switch self {
            case let .archiveNameMismatch(expected, got):
                return "Downloaded archive name \(got) did not match the manifest (\(expected))."
            case .sha256Mismatch:
                return "Downloaded archive failed its SHA-256 integrity check."
            case let .byteCountMismatch(expected, got):
                return "Downloaded archive size (\(got) bytes) did not match the manifest (\(expected) bytes)."
            case let .bundleIdentifierMismatch(expected, got):
                return "Update bundle identifier \(got) did not match this app (\(expected))."
            case let .unreadableVersion(manifest, current):
                return "Could not compare the update version (\(manifest)) to the current version (\(current))."
            case let .notNewerThanCurrent(current, candidate):
                return "Update version \(candidate) is not newer than the installed \(current)."
            }
        }
    }

    static func verify(
        manifest: OuroMDUpdateManifest,
        downloadedArchiveName: String,
        downloadedSHA256: String,
        downloadedBytes: Int,
        expectedBundleIdentifier: String,
        currentVersion: String
    ) -> Failure? {
        guard downloadedArchiveName == manifest.archive else {
            return .archiveNameMismatch(expected: manifest.archive, got: downloadedArchiveName)
        }

        let expectedSHA = manifest.sha256.lowercased()
        let actualSHA = downloadedSHA256.lowercased()
        guard actualSHA == expectedSHA else {
            return .sha256Mismatch(expected: expectedSHA, got: actualSHA)
        }

        guard downloadedBytes == manifest.bytes else {
            return .byteCountMismatch(expected: manifest.bytes, got: downloadedBytes)
        }

        guard manifest.bundleIdentifier == expectedBundleIdentifier else {
            return .bundleIdentifierMismatch(expected: expectedBundleIdentifier, got: manifest.bundleIdentifier)
        }

        guard let candidate = SemanticVersion(manifest.version),
              let current = SemanticVersion(currentVersion)
        else {
            return .unreadableVersion(manifest: manifest.version, current: currentVersion)
        }

        guard candidate > current else {
            return .notNewerThanCurrent(current: currentVersion, candidate: manifest.version)
        }

        return nil
    }
}
