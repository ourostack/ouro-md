import Foundation

public enum DocumentTruthState: Equatable {
    case untitled
    case unavailable
    case gitUnavailable
    case notInGit
    case untracked
    case trackedClean
    case trackedModified
    case trackedStaged
    case trackedMixed
}

public struct DocumentTruthSnapshot: Equatable {
    public let state: DocumentTruthState
    public let absolutePath: String?
    public let repositoryRoot: String?
    public let relativePath: String?

    public init(
        state: DocumentTruthState,
        absolutePath: String?,
        repositoryRoot: String?,
        relativePath: String?
    ) {
        self.state = state
        self.absolutePath = absolutePath
        self.repositoryRoot = repositoryRoot
        self.relativePath = relativePath
    }

    public var label: String {
        switch state {
        case .untitled:
            return "Untitled"
        case .unavailable:
            return "File unavailable"
        case .gitUnavailable:
            return "Git unavailable"
        case .notInGit:
            return "Local file"
        case .untracked:
            return "Not tracked"
        case .trackedClean:
            return "Tracked · Clean"
        case .trackedModified:
            return "Modified · visible in git diff"
        case .trackedStaged:
            return "Staged changes"
        case .trackedMixed:
            return "Mixed changes"
        }
    }

    public var canCopyPath: Bool {
        absolutePath != nil
    }

    public var canCopyRelativePath: Bool {
        relativePath != nil
    }

    public var canCopyGitDiffCommand: Bool {
        repositoryRoot != nil && relativePath != nil
    }

    public var gitDiffCommand: String? {
        guard let repositoryRoot, let relativePath else { return nil }
        let root = Self.shellEscape(repositoryRoot)
        let path = Self.shellEscape(relativePath)
        switch state {
        case .trackedStaged:
            return "git -C \(root) diff --cached -- \(path)"
        case .trackedMixed:
            return "git -C \(root) diff HEAD -- \(path)"
        case .untracked:
            return "git -C \(root) diff --no-index -- /dev/null \(path)"
        default:
            return "git -C \(root) diff -- \(path)"
        }
    }

    static func shellEscape(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-"))
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct DocumentTruthGitCommand: Equatable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }
}

public struct DocumentTruthGitResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool {
        exitCode == 0
    }
}

public enum DocumentTruthGitError: Error, Equatable {
    case unavailable
}

public protocol DocumentTruthGitRunning {
    func run(_ command: DocumentTruthGitCommand, workingDirectory: URL) throws -> DocumentTruthGitResult
}

public struct DocumentTruthProvider {
    private let gitRunner: any DocumentTruthGitRunning
    private let fileExists: (URL) -> Bool

    public init(
        gitRunner: any DocumentTruthGitRunning,
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.gitRunner = gitRunner
        self.fileExists = fileExists
    }

    public func snapshot(for url: URL?) -> DocumentTruthSnapshot {
        guard let url else {
            return DocumentTruthSnapshot(state: .untitled, absolutePath: nil, repositoryRoot: nil, relativePath: nil)
        }
        guard url.isFileURL else {
            return DocumentTruthSnapshot(state: .unavailable, absolutePath: nil, repositoryRoot: nil, relativePath: nil)
        }

        let absolutePath = url.path
        guard fileExists(url) else {
            return DocumentTruthSnapshot(state: .unavailable, absolutePath: absolutePath, repositoryRoot: nil, relativePath: nil)
        }

        let workingDirectory = url.deletingLastPathComponent()
        let rootResult: DocumentTruthGitResult
        do {
            rootResult = try gitRunner.run(
                DocumentTruthGitCommand(arguments: ["rev-parse", "--show-toplevel"]),
                workingDirectory: workingDirectory
            )
        } catch {
            return DocumentTruthSnapshot(state: .gitUnavailable, absolutePath: absolutePath, repositoryRoot: nil, relativePath: nil)
        }
        guard rootResult.succeeded else {
            guard rootResult.indicatesNotRepository else {
                return DocumentTruthSnapshot(state: .gitUnavailable, absolutePath: absolutePath, repositoryRoot: nil, relativePath: nil)
            }
            return DocumentTruthSnapshot(state: .notInGit, absolutePath: absolutePath, repositoryRoot: nil, relativePath: nil)
        }

        let repositoryRoot = rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let relativePath = Self.relativePath(for: url, repositoryRoot: repositoryRoot) else {
            return DocumentTruthSnapshot(state: .notInGit, absolutePath: absolutePath, repositoryRoot: nil, relativePath: nil)
        }

        let trackedResult = runGit(["ls-files", "--error-unmatch", "--", relativePath], workingDirectory: workingDirectory)
        let statusResult = runGit(["status", "--porcelain=v1", "--", relativePath], workingDirectory: workingDirectory)
        guard statusResult.succeeded else {
            return DocumentTruthSnapshot(state: .gitUnavailable, absolutePath: absolutePath, repositoryRoot: nil, relativePath: nil)
        }

        let status = statusResult.stdout
        let state = Self.state(tracked: trackedResult.succeeded, porcelain: status)
        return DocumentTruthSnapshot(
            state: state,
            absolutePath: absolutePath,
            repositoryRoot: repositoryRoot,
            relativePath: relativePath
        )
    }

    private func runGit(_ arguments: [String], workingDirectory: URL) -> DocumentTruthGitResult {
        do {
            return try gitRunner.run(DocumentTruthGitCommand(arguments: arguments), workingDirectory: workingDirectory)
        } catch {
            return DocumentTruthGitResult(exitCode: 127, stdout: "", stderr: "")
        }
    }

    private static func relativePath(for url: URL, repositoryRoot: String) -> String? {
        let root = URL(fileURLWithPath: repositoryRoot).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { return nil }
        let start = path.index(path.startIndex, offsetBy: root.count)
        let suffix = path[start...].drop(while: { $0 == "/" })
        return String(suffix)
    }

    private static func state(tracked: Bool, porcelain: String) -> DocumentTruthState {
        let firstLine = porcelain.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if !tracked {
            return firstLine.hasPrefix("??") ? .untracked : .notInGit
        }
        guard !firstLine.isEmpty else { return .trackedClean }
        let index = firstLine[firstLine.startIndex]
        let worktree = firstLine[firstLine.index(after: firstLine.startIndex)]
        if index != " " && worktree != " " {
            return .trackedMixed
        }
        if index != " " {
            return .trackedStaged
        }
        return .trackedModified
    }
}

private extension DocumentTruthGitResult {
    var indicatesNotRepository: Bool {
        let text = "\(stdout)\n\(stderr)".lowercased()
        return text.contains("not a git repository") || text.contains("not git")
    }
}
