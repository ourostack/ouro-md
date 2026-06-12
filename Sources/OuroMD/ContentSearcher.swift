import Foundation

/// One match within a file: the line, where in it the match falls (for
/// highlighting), and the 1-based line number.
struct SearchSnippet: Identifiable, Hashable {
    let id = UUID()
    let lineNumber: Int
    let text: String
    let matchStart: Int
    let matchLength: Int
}

/// A file with at least one content match, plus whether the filename matched.
struct SearchResult: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let nameMatched: Bool
    let snippets: [SearchSnippet]
    var count: Int { snippets.count }
}

/// Streams whole-folder content-search results off the main thread. New
/// searches cancel in-flight ones. Filename hits rank first, then by match
/// count — Typora-like behavior, dependency-free (no bundled ripgrep).
final class ContentSearcher {
    private let queue = DispatchQueue(label: "md.ouro.contentsearch", qos: .userInitiated)
    private var current: DispatchWorkItem?

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
                onComplete: @escaping () -> Void) {
        cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let regex = Self.makeRegex(trimmed, caseSensitive: caseSensitive, wholeWord: wholeWord, regexp: regexp) else {
            onComplete(); return
        }
        let nameQuery = trimmed.lowercased()
        var workItem: DispatchWorkItem!
        let work = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            let files = FolderScanner.flatList(at: folder, sort: .name)
            for node in files {
                if workItem.isCancelled { return }
                let nameMatched = node.name.lowercased().contains(nameQuery)
                var snippets: [SearchSnippet] = []
                if let text = AppModel.readText(at: node.url), text.utf8.count <= Self.maxFileBytes {
                    snippets = Self.matches(in: text, regex: regex)
                }
                guard nameMatched || !snippets.isEmpty else { continue }
                let result = SearchResult(id: node.url, url: node.url, name: node.name,
                                          nameMatched: nameMatched, snippets: snippets)
                DispatchQueue.main.async { if !workItem.isCancelled { onResult(result) } }
            }
            DispatchQueue.main.async { if !workItem.isCancelled { onComplete() } }
        }
        workItem = work
        current = work
        queue.async(execute: work)
    }

    private static func matches(in text: String, regex: NSRegularExpression) -> [SearchSnippet] {
        var out: [SearchSnippet] = []
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if out.count >= maxMatchesPerFile { break }
            let ns = line as NSString
            guard ns.length > 0 else { continue }
            let m = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length))
            guard let match = m else { continue }
            let (snippet, start) = truncate(ns, around: match.range)
            out.append(SearchSnippet(lineNumber: i + 1, text: snippet,
                                     matchStart: start, matchLength: match.range.length))
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
        var pattern = regexp ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord { pattern = "\\b" + pattern + "\\b" }
        var options: NSRegularExpression.Options = []
        if !caseSensitive { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }
}
