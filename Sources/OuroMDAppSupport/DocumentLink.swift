import Foundation

public enum DocumentLinkTarget: Equatable {
    case external(URL)
    case markdownFile(URL, fragment: String?)
    case inDocumentAnchor(String)
    case unsupported
}

/// Resolves a Markdown link exactly as a local-file editor should:
/// web/mail links stay external, while Markdown paths are resolved beside the
/// currently open document so the app can open them in another document window.
public enum DocumentLinkResolver {
    private static let markdownExtensions = ["md", "markdown", "mdown", "mkd", "mdtext"]
    private static let externalSchemes = ["http", "https", "mailto"]

    public static func resolve(_ rawTarget: String, relativeTo documentURL: URL?) -> DocumentLinkTarget {
        var target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return .unsupported }

        if target.first == "<", target.last == ">", target.count >= 2 {
            target.removeFirst()
            target.removeLast()
            target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !target.isEmpty else { return .unsupported }

        if target.hasPrefix("#") {
            return .inDocumentAnchor(String(target.dropFirst()))
        }

        if let parsed = URL(string: target), let scheme = parsed.scheme?.lowercased() {
            if externalSchemes.contains(scheme) {
                return .external(parsed)
            }
            if scheme == "file" {
                let fileURL = URL(fileURLWithPath: parsed.path)
                guard isMarkdown(fileURL) else { return .unsupported }
                return .markdownFile(
                    fileURL.standardizedFileURL,
                    fragment: parsed.fragment
                )
            }
            return .unsupported
        }

        guard !target.hasPrefix("//"),
              let documentURL,
              documentURL.isFileURL else {
            return .unsupported
        }

        let fragmentParts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = fragmentParts[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard !rawPath.isEmpty else { return .unsupported }
        let rawFragment = fragmentParts.count > 1 ? String(fragmentParts[1]) : nil
        let fragment = rawFragment

        let path = String(rawPath).removingPercentEncoding ?? String(rawPath)
        let resolved: URL
        if path.hasPrefix("/") {
            resolved = URL(fileURLWithPath: path)
        } else {
            resolved = documentURL.deletingLastPathComponent().appendingPathComponent(path)
        }
        let standardized = resolved.standardizedFileURL
        return isMarkdown(standardized) ? .markdownFile(standardized, fragment: fragment) : .unsupported
    }

    private static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }
}
