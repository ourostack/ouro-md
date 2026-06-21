import Foundation

/// One match within a file: the line, where in it the match falls (for
/// highlighting), and the 1-based line number.
struct SearchSnippet: Identifiable, Hashable {
    let id = UUID()
    let lineNumber: Int
    let text: String
    let matchStart: Int
    let matchLength: Int
    let sourceMatchStart: Int
    let sourceMatchLength: Int
    let matchedText: String
    let matchOrdinal: Int
}

/// A file with at least one content match, plus whether the filename matched.
struct SearchResult: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let parent: String
    let nameMatched: Bool
    let snippets: [SearchSnippet]
    var count: Int { snippets.count }
}

struct SearchCompletion: Equatable {
    var isTruncated: Bool
    var skippedUnreadableCount: Int
    var skippedBinaryCount: Int
    var isCancelled: Bool

    static let empty = SearchCompletion(
        isTruncated: false,
        skippedUnreadableCount: 0,
        skippedBinaryCount: 0,
        isCancelled: false
    )
}

/// Streams whole-folder content-search results off the main thread. New
/// searches cancel in-flight ones. Filename hits rank first, then by match
/// count, without a bundled external search binary.
final class ContentSearcher {
    private let queue = DispatchQueue(label: "md.ouro.contentsearch", qos: .userInitiated)
    private var current: SearchToken?

    private static let maxMatchesPerFile = 30
    private static let maxFileBytes = 2_000_000
    private static let snippetRadius = 60

    func cancel() {
        current?.cancel()
        current = nil
    }

    func search(_ query: String, in folder: URL,
                caseSensitive: Bool, wholeWord: Bool, regexp: Bool,
                onResult: @escaping (SearchResult) -> Void,
                onComplete: @escaping (SearchCompletion) -> Void) {
        cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let regex = Self.makeRegex(trimmed, caseSensitive: caseSensitive, wholeWord: wholeWord, regexp: regexp) else {
            onComplete(.empty); return
        }
        let nameQuery = trimmed.lowercased()
        let token = SearchToken()
        let work = DispatchWorkItem { [weak self] in
            guard self != nil, !token.isCancelled else { return }
            let snapshot = FolderScanner.snapshot(at: folder, sort: .name, shouldCancel: { token.isCancelled })
            if snapshot.isCancelled || token.isCancelled { return }
            let files = snapshot.flat
            var skippedUnreadableCount = 0
            var skippedBinaryCount = 0
            for node in files {
                if token.isCancelled { return }
                let nameMatched = node.name.lowercased().contains(nameQuery)
                var snippets: [SearchSnippet] = []
                switch Self.searchableText(at: node.url) {
                case let .text(text):
                    snippets = Self.matches(in: text, regex: regex)
                case .binary:
                    skippedBinaryCount += 1
                case .unreadable:
                    skippedUnreadableCount += 1
                }
                guard nameMatched || !snippets.isEmpty else { continue }
                let result = SearchResult(id: node.url, url: node.url, name: node.name,
                                          parent: FolderDisplay.parentHint(node.url, under: folder),
                                          nameMatched: nameMatched, snippets: snippets)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.current === token, !token.isCancelled else { return }
                    onResult(result)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.current === token, !token.isCancelled else { return }
                self.current = nil
                onComplete(SearchCompletion(
                    isTruncated: snapshot.isTruncated,
                    skippedUnreadableCount: skippedUnreadableCount,
                    skippedBinaryCount: skippedBinaryCount,
                    isCancelled: false
                ))
            }
        }
        current = token
        queue.async(execute: work)
    }

    private final class SearchToken {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    private enum SearchableText {
        case text(String)
        case unreadable
        case binary
    }

    private static func searchableText(at url: URL) -> SearchableText {
        guard let text = AppModel.readText(at: url), text.utf8.count <= maxFileBytes else {
            return .unreadable
        }
        return looksBinary(text) ? .binary : .text(text)
    }

    private static func looksBinary(_ text: String) -> Bool {
        var controlCount = 0
        var scalarCount = 0
        for scalar in text.unicodeScalars {
            scalarCount += 1
            if scalar.value == 0 { return true }
            if scalar.value < 32, scalar.value != 10, scalar.value != 13, scalar.value != 9 {
                controlCount += 1
            }
        }
        return controlCount > max(8, scalarCount / 100)
    }

    private static func matches(in text: String, regex: NSRegularExpression) -> [SearchSnippet] {
        var out: [SearchSnippet] = []
        var ordinal = 0
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if out.count >= maxMatchesPerFile { break }
            let ns = line as NSString
            guard ns.length > 0 else { continue }
            let lineMatches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
            guard let match = lineMatches.first else { continue }
            let (snippet, start) = truncate(ns, around: match.range)
            let matchedText = match.range.length > 0 ? ns.substring(with: match.range) : ""
            out.append(SearchSnippet(lineNumber: i + 1, text: snippet,
                                      matchStart: start, matchLength: match.range.length,
                                      sourceMatchStart: match.range.location,
                                      sourceMatchLength: match.range.length,
                                      matchedText: matchedText,
                                      matchOrdinal: ordinal))
            ordinal += lineMatches.count
        }
        return out
    }

    /// Centers a long line on the match so the snippet stays readable.
    private static func truncate(_ line: NSString, around range: NSRange) -> (String, Int) {
        let full = line as String
        guard line.length > snippetRadius * 2 else { return (full, range.location) }
        let lower = max(0, range.location - snippetRadius)
        let upper = min(line.length, range.location + range.length + snippetRadius)
        var snippet = line.substring(with: NSRange(location: lower, length: upper - lower))
        var newStart = range.location - lower
        if lower > 0 { snippet = "…" + snippet; newStart += 1 }
        if upper < line.length { snippet += "…" }
        return (snippet, newStart)
    }

    static func makeRegex(_ query: String, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) -> NSRegularExpression? {
        try? makeRegexOrThrow(query, caseSensitive: caseSensitive, wholeWord: wholeWord, regexp: regexp)
    }

    static func regexError(_ query: String, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) -> String? {
        do {
            _ = try makeRegexOrThrow(query, caseSensitive: caseSensitive, wholeWord: wholeWord, regexp: regexp)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func makeRegexOrThrow(_ query: String, caseSensitive: Bool, wholeWord: Bool, regexp: Bool) throws -> NSRegularExpression {
        var pattern = regexp ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord { pattern = "\\b" + pattern + "\\b" }
        var options: NSRegularExpression.Options = []
        if !caseSensitive { options.insert(.caseInsensitive) }
        return try NSRegularExpression(pattern: pattern, options: options)
    }
}
