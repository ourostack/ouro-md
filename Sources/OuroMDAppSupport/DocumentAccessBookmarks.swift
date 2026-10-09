import Foundation

/// Remembers security-scoped bookmarks for documents and folders the user
/// opened, so the sandboxed App Store build can reach them again later without
/// a window open (for Siri, Shortcuts and Spotlight). The sandbox only grants
/// access to what the user picked, and only until the app quits; a bookmark
/// carries that grant across launches.
public struct DocumentAccessBookmarks {
    /// How many documents and folders to remember, newest first.
    public static let limit = 50

    struct Entry: Codable, Equatable {
        let path: String
        let bookmark: Data
    }

    private let load: () -> Data?
    private let save: (Data) -> Void
    private let makeBookmark: (URL) -> Data?
    private let resolveBookmark: (Data) -> URL?

    public init(
        load: @escaping () -> Data?,
        save: @escaping (Data) -> Void,
        makeBookmark: @escaping (URL) -> Data?,
        resolveBookmark: @escaping (Data) -> URL?
    ) {
        self.load = load
        self.save = save
        self.makeBookmark = makeBookmark
        self.resolveBookmark = resolveBookmark
    }

    var entries: [Entry] {
        guard let data = load(), let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    /// Records (or refreshes) the bookmark for a document or folder the user
    /// opened. Does nothing when no bookmark can be made.
    public func record(_ url: URL) {
        let path = Self.key(url)
        guard let bookmark = makeBookmark(url) else { return }
        var kept = entries.filter { $0.path != path }
        kept.insert(Entry(path: path, bookmark: bookmark), at: 0)
        if let data = try? JSONEncoder().encode(Array(kept.prefix(Self.limit))) { save(data) }
    }

    /// The bookmarked URL that grants access to `url`: its own bookmark, or
    /// the nearest bookmarked folder that contains it. Nil when none resolves.
    public func grantingURL(for url: URL) -> URL? {
        let path = Self.key(url)
        let candidates = entries
            .filter { path == $0.path || path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
            .sorted { $0.path.count > $1.path.count }
        for entry in candidates {
            if let resolved = resolveBookmark(entry.bookmark) { return resolved }
        }
        return nil
    }

    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
