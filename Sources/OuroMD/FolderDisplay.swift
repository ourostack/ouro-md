import Foundation

enum FolderDisplay {
    static func relativePath(_ url: URL, under folder: URL) -> String {
        let filePath = url.standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        guard filePath.hasPrefix(prefix) else { return url.lastPathComponent }
        let rel = String(filePath.dropFirst(prefix.count))
        return rel.isEmpty ? url.lastPathComponent : rel
    }

    static func parentHint(_ url: URL, under folder: URL) -> String {
        let rel = relativePath(url, under: folder)
        let parent = (rel as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "." ? folder.lastPathComponent : parent
    }

    static func hasDuplicateName(_ node: FolderNode, in nodes: [FolderNode]) -> Bool {
        hasDuplicateName(node, duplicateNames: duplicateNames(in: nodes))
    }

    static func hasDuplicateName(_ node: FolderNode, duplicateNames: Set<String>) -> Bool {
        duplicateNames.contains(normalizedName(node.name))
    }

    static func duplicateNames(in nodes: [FolderNode]) -> Set<String> {
        var counts: [String: Int] = [:]
        for node in nodes where !node.isDirectory {
            counts[normalizedName(node.name), default: 0] += 1
        }
        return Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
    }

    static func accessibilityLabel(for node: FolderNode, under folder: URL?, includeParent: Bool) -> String {
        guard includeParent, let folder else { return node.name }
        return "\(node.name), \(parentHint(node.url, under: folder))"
    }

    private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
