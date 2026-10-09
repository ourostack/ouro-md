import AppKit
import OuroMDAppSupport

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

    /// Resolves a bookmark even when it is stale (the file moved or was
    /// renamed): a stale bookmark still grants access to where the file is now.
    static func resolveBookmarkAllowingStale(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
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

/// The App Store build's remembered access to documents and folders the user
/// opened, so Siri, Shortcuts and Spotlight can reach them with no window open.
/// Only the sandboxed build records anything; the direct-download build can
/// already read any file the user can.
enum DocumentAccess {
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static let bookmarks = DocumentAccessBookmarks(
        load: { UserDefaults.standard.data(forKey: "ouro.documentAccessBookmarks") },
        save: { UserDefaults.standard.set($0, forKey: "ouro.documentAccessBookmarks") },
        makeBookmark: SecurityScopedResourceStore.bookmarkData(for:),
        resolveBookmark: SecurityScopedResourceStore.resolveBookmarkAllowingStale(_:)
    )

    /// Adds a document or folder to Open Recent and, when sandboxed,
    /// remembers access to it.
    static func noteRecent(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        if isSandboxed { bookmarks.record(url) }
    }

    /// Runs `body` with access to `url`, using a remembered bookmark when the
    /// sandbox would otherwise refuse it.
    static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        guard isSandboxed, !FileManager.default.isReadableFile(atPath: url.path),
              let granting = bookmarks.grantingURL(for: url) else { return try body() }
        let started = granting.startAccessingSecurityScopedResource()
        defer { if started { granting.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
