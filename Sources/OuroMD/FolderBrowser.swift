import Foundation
import CoreServices

/// One entry in a mounted folder — a file or a directory (with children for the
/// tree view). `children == nil` marks a leaf file (drives SwiftUI's tree).
struct FolderNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let isDirectory: Bool
    let modified: Date
    let created: Date
    var children: [FolderNode]?
}

struct FolderScanSnapshot: Equatable {
    var tree: [FolderNode]
    var flat: [FolderNode]
    var isTruncated = false
}

enum FolderSort: String, CaseIterable {
    case natural, name, modified, created

    var label: String {
        switch self {
        case .natural: return "Sort Naturally"
        case .name: return "Sort by Name"
        case .modified: return "Sort by Modified Date"
        case .created: return "Sort by Created Date"
        }
    }
}

/// Recursively scans a mounted folder into file/dir nodes, off the main thread.
/// Uses a fixed set of openable extensions, skips dotfiles and `node_modules`,
/// ignores oversized files, and prunes empty dirs.
enum FolderScanner {
    static let supportedExtensions: Set<String> = [
        "md", "markdown", "mmd", "mkd", "mdwn", "mdown", "mdx",
        "mdtxt", "mdtext", "txt", "text", "apib", "rmd", "qmd"
    ]
    /// Safety caps so a huge tree can't wedge the UI.
    static let maxFiles = 5000
    private static let maxFileBytes = 2_000_000

    static func canOpen(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Recursive tree of openable files + the directories that contain them.
    static func tree(at folder: URL, sort: FolderSort) -> [FolderNode] {
        snapshot(at: folder, sort: sort).tree
    }

    /// Flat list of every openable file under the folder (List/"Articles" view).
    static func flatList(at folder: URL, sort: FolderSort) -> [FolderNode] {
        snapshot(at: folder, sort: sort).flat
    }

    /// Tree + flat views from one filesystem traversal. The sidebar needs both
    /// views at the same time, so this avoids scanning large folders twice.
    static func snapshot(at folder: URL, sort: FolderSort) -> FolderScanSnapshot {
        var budget = maxFiles
        let raw = scan(folder, sort: sort, budget: &budget)
        return FolderScanSnapshot(
            tree: raw.tree,
            flat: sortNodes(raw.flat, sort: sort, groupDirs: false),
            isTruncated: raw.isTruncated
        )
    }

    // MARK: - internals

    /// Recursion depth cap — a second guard (alongside skipping symlinks)
    /// against pathological trees / symlink cycles.
    private static let maxDepth = 24
    private static let scanKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey
    ]

    private static func scan(_ dir: URL, sort: FolderSort, budget: inout Int, depth: Int = 0) -> FolderScanSnapshot {
        guard depth < maxDepth else { return FolderScanSnapshot(tree: [], flat: []) }
        guard budget > 0 else { return FolderScanSnapshot(tree: [], flat: [], isTruncated: true) }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: scanKeys,
                                                        options: [.skipsHiddenFiles]) else {
            return FolderScanSnapshot(tree: [], flat: [])
        }
        var treeNodes: [FolderNode] = []
        var flatNodes: [FolderNode] = []
        for url in entries {
            let name = url.lastPathComponent
            if name == "node_modules" { continue }
            let values = try? url.resourceValues(forKeys: Set(scanKeys))
            if values?.isSymbolicLink ?? false { continue }   // don't follow symlinks (cycle-safe)
            let isDir = values?.isDirectory ?? false
            let mtime = values?.contentModificationDate ?? .distantPast
            let ctime = values?.creationDate ?? .distantPast
            if isDir {
                let child = scan(url, sort: sort, budget: &budget, depth: depth + 1)
                flatNodes.append(contentsOf: child.flat)
                if !child.tree.isEmpty {
                    treeNodes.append(FolderNode(url: url, name: name, isDirectory: true,
                                                modified: mtime, created: ctime, children: child.tree))
                }
                if child.isTruncated {
                    return FolderScanSnapshot(
                        tree: sortNodes(treeNodes, sort: sort, groupDirs: true),
                        flat: flatNodes,
                        isTruncated: true
                    )
                }
            } else if canOpen(url), (values?.fileSize ?? 0) <= maxFileBytes {
                budget -= 1
                let node = FolderNode(url: url, name: name, isDirectory: false,
                                      modified: mtime, created: ctime, children: nil)
                treeNodes.append(node)
                flatNodes.append(node)
                if budget <= 0 {
                    return FolderScanSnapshot(
                        tree: sortNodes(treeNodes, sort: sort, groupDirs: true),
                        flat: flatNodes,
                        isTruncated: true
                    )
                }
            }
        }
        return FolderScanSnapshot(
            tree: sortNodes(treeNodes, sort: sort, groupDirs: true),
            flat: flatNodes,
            isTruncated: false
        )
    }

    private static func sortNodes(_ nodes: [FolderNode], sort: FolderSort, groupDirs: Bool) -> [FolderNode] {
        nodes.sorted { a, b in
            if groupDirs, a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sort {
            case .name, .natural:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified:
                return a.modified > b.modified
            case .created:
                return a.created > b.created
            }
        }
    }
}

/// Watches a mounted folder recursively (FSEvents) and fires `onChange` on the
/// main queue, debounced — so external add/remove/rename/edit of any file under
/// the folder triggers a re-scan.
final class FolderWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        stop()
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context,
                                               [url.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               0.3, flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func fire() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
