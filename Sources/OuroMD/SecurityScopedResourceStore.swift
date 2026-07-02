import Foundation

/// Retains security-scoped file access for URLs restored from a prior user
/// selection. Direct-download builds do not need this, but the App Store sandbox
/// does after relaunch.
final class SecurityScopedResourceStore {
    private var activeURLs: [URL] = []

    deinit {
        stopAccessingAll()
    }

    func startAccessing(_ url: URL) -> URL {
        if url.startAccessingSecurityScopedResource() {
            activeURLs.append(url)
        }
        return url
    }

    func stopAccessingAll() {
        activeURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        activeURLs.removeAll()
    }

    static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        return stale ? nil : url
    }
}
