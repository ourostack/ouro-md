import Foundation
import XCTest
@testable import OuroMDAppSupport

final class DocumentTruthTests: XCTestCase {
    func testUntitledAndNonFileURLsHaveHonestUnavailableState() {
        let provider = DocumentTruthProvider(gitRunner: FakeGitRunner())

        XCTAssertEqual(provider.snapshot(for: nil).state, .untitled)
        XCTAssertEqual(provider.snapshot(for: nil).label, "Untitled")
        XCTAssertFalse(provider.snapshot(for: nil).canCopyPath)
        XCTAssertNil(provider.snapshot(for: nil).gitDiffCommand)

        let remote = provider.snapshot(for: URL(string: "https://example.com/note.md"))
        XCTAssertEqual(remote.state, .unavailable)
        XCTAssertEqual(remote.label, "File unavailable")
        XCTAssertFalse(remote.canCopyPath)
        XCTAssertFalse(remote.canCopyRelativePath)
        XCTAssertFalse(remote.canCopyGitDiffCommand)
    }

    func testMissingOrUnreadableFileFallsBackWithoutGitCertainty() {
        let url = URL(fileURLWithPath: "/tmp/ouro-missing.md")
        let provider = DocumentTruthProvider(gitRunner: FakeGitRunner(), fileExists: { _ in false })

        let snapshot = provider.snapshot(for: url)

        XCTAssertEqual(snapshot.state, .unavailable)
        XCTAssertEqual(snapshot.absolutePath, "/tmp/ouro-missing.md")
        XCTAssertEqual(snapshot.label, "File unavailable")
        XCTAssertTrue(snapshot.canCopyPath)
        XCTAssertFalse(snapshot.canCopyRelativePath)
        XCTAssertFalse(snapshot.canCopyGitDiffCommand)
    }

    func testGitUnavailableIsDifferentFromLocalNonRepositoryFile() {
        let gitUnavailable = DocumentTruthProvider(
            gitRunner: FakeGitRunner { _, _ in throw DocumentTruthGitError.unavailable },
            fileExists: { _ in true }
        )
        let local = DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                XCTAssertEqual(command.arguments, ["rev-parse", "--show-toplevel"])
                return .failure
            },
            fileExists: { _ in true }
        )
        let url = URL(fileURLWithPath: "/tmp/notes/today.md")

        XCTAssertEqual(gitUnavailable.snapshot(for: url).state, .gitUnavailable)
        XCTAssertEqual(gitUnavailable.snapshot(for: url).label, "Git unavailable")
        XCTAssertEqual(local.snapshot(for: url).state, .notInGit)
        XCTAssertEqual(local.snapshot(for: url).label, "Local file")
    }

    func testDefaultFileExistenceProbeWorksForExistingFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-truth-default-exists-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.md")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let provider = DocumentTruthProvider(gitRunner: FakeGitRunner { _, _ in .failure })

        XCTAssertEqual(provider.snapshot(for: file).state, .notInGit)
        XCTAssertEqual(provider.snapshot(for: file).absolutePath, file.path)
    }

    func testTrackedCleanFileCarriesRepositoryPathsAndDiffCommand() {
        let provider = providerForTracked(status: "")
        let url = URL(fileURLWithPath: "/repo/docs/today.md")

        let snapshot = provider.snapshot(for: url)

        XCTAssertEqual(snapshot.state, .trackedClean)
        XCTAssertEqual(snapshot.label, "Tracked · Clean")
        XCTAssertEqual(snapshot.absolutePath, "/repo/docs/today.md")
        XCTAssertEqual(snapshot.repositoryRoot, "/repo")
        XCTAssertEqual(snapshot.relativePath, "docs/today.md")
        XCTAssertTrue(snapshot.canCopyPath)
        XCTAssertTrue(snapshot.canCopyRelativePath)
        XCTAssertTrue(snapshot.canCopyGitDiffCommand)
        XCTAssertEqual(snapshot.gitDiffCommand, "git -C /repo diff -- docs/today.md")
    }

    func testTrackedModifiedAndMixedStatesUseMechanicalPorcelainStatus() {
        XCTAssertEqual(providerForTracked(status: " M docs/today.md\n").snapshot(for: fileURL).state, .trackedModified)
        XCTAssertEqual(providerForTracked(status: " M docs/today.md\n").snapshot(for: fileURL).label, "Modified · visible in git diff")
        XCTAssertEqual(providerForTracked(status: "M  docs/today.md\n").snapshot(for: fileURL).state, .trackedStaged)
        XCTAssertEqual(providerForTracked(status: "M  docs/today.md\n").snapshot(for: fileURL).label, "Staged changes")
        XCTAssertEqual(providerForTracked(status: "MM docs/today.md\n").snapshot(for: fileURL).state, .trackedMixed)
        XCTAssertEqual(providerForTracked(status: "MM docs/today.md\n").snapshot(for: fileURL).label, "Mixed changes")
    }

    func testUntrackedAndIgnoredFilesAreNotPresentedAsTrackedDiffs() {
        let untracked = providerForUntracked(status: "?? docs/draft.md\n")
        let ignored = providerForUntracked(status: "")

        XCTAssertEqual(untracked.snapshot(for: fileURL).state, .untracked)
        XCTAssertEqual(untracked.snapshot(for: fileURL).label, "Not tracked")
        XCTAssertTrue(untracked.snapshot(for: fileURL).canCopyGitDiffCommand)
        XCTAssertEqual(ignored.snapshot(for: fileURL).state, .notInGit)
        XCTAssertEqual(ignored.snapshot(for: fileURL).label, "Local file")
    }

    func testShellEscapesDiffCommandComponents() {
        let provider = DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                switch command.arguments {
                case ["rev-parse", "--show-toplevel"]:
                    return .success("/repo with spaces")
                case ["ls-files", "--error-unmatch", "--", "docs/today's note.md"]:
                    return .success("docs/today's note.md")
                case ["status", "--porcelain=v1", "--", "docs/today's note.md"]:
                    return .success(" M docs/today's note.md\n")
                default:
                    XCTFail("Unexpected command: \(command.arguments)")
                    return .failure
                }
            },
            fileExists: { _ in true }
        )

        let snapshot = provider.snapshot(for: URL(fileURLWithPath: "/repo with spaces/docs/today's note.md"))

        XCTAssertEqual(snapshot.relativePath, "docs/today's note.md")
        XCTAssertEqual(snapshot.gitDiffCommand, "git -C '/repo with spaces' diff -- 'docs/today'\\''s note.md'")
        XCTAssertEqual(DocumentTruthSnapshot.shellEscape(""), "''")
    }

    func testRepositoryMismatchAndStatusFailureFallBackHonestly() {
        let outsideRepo = DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                XCTAssertEqual(command.arguments, ["rev-parse", "--show-toplevel"])
                return .success("/elsewhere")
            },
            fileExists: { _ in true }
        )
        let statusFailure = DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                switch command.arguments {
                case ["rev-parse", "--show-toplevel"]:
                    return .success("/repo")
                case ["ls-files", "--error-unmatch", "--", "docs/today.md"]:
                    return .success("docs/today.md")
                case ["status", "--porcelain=v1", "--", "docs/today.md"]:
                    return .failure
                default:
                    XCTFail("Unexpected command: \(command.arguments)")
                    return .failure
                }
            },
            fileExists: { _ in true }
        )

        XCTAssertEqual(outsideRepo.snapshot(for: fileURL).state, .notInGit)
        XCTAssertEqual(statusFailure.snapshot(for: fileURL).state, .gitUnavailable)
    }

    func testThrownSubcommandsAndRepositoryRootFilePathAreCovered() {
        let thrownSubcommand = DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                switch command.arguments {
                case ["rev-parse", "--show-toplevel"]:
                    return .success("/repo")
                case ["ls-files", "--error-unmatch", "--", "docs/today.md"]:
                    throw DocumentTruthGitError.unavailable
                case ["status", "--porcelain=v1", "--", "docs/today.md"]:
                    return .success("?? docs/today.md\n")
                default:
                    XCTFail("Unexpected command: \(command.arguments)")
                    return .failure
                }
            },
            fileExists: { _ in true }
        )
        let rootFile = DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                switch command.arguments {
                case ["rev-parse", "--show-toplevel"]:
                    return .success("/repo")
                case ["ls-files", "--error-unmatch", "--", ""]:
                    return .success("")
                case ["status", "--porcelain=v1", "--", ""]:
                    return .success("")
                default:
                    XCTFail("Unexpected command: \(command.arguments)")
                    return .failure
                }
            },
            fileExists: { _ in true }
        )

        XCTAssertEqual(thrownSubcommand.snapshot(for: fileURL).state, .untracked)
        let rootSnapshot = rootFile.snapshot(for: URL(fileURLWithPath: "/repo"))
        XCTAssertEqual(rootSnapshot.state, .trackedClean)
        XCTAssertEqual(rootSnapshot.relativePath, "")
    }

    private var fileURL: URL {
        URL(fileURLWithPath: "/repo/docs/today.md")
    }

    private func providerForTracked(status: String) -> DocumentTruthProvider {
        DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                switch command.arguments {
                case ["rev-parse", "--show-toplevel"]:
                    return .success("/repo")
                case ["ls-files", "--error-unmatch", "--", "docs/today.md"]:
                    return .success("docs/today.md")
                case ["status", "--porcelain=v1", "--", "docs/today.md"]:
                    return .success(status)
                default:
                    XCTFail("Unexpected command: \(command.arguments)")
                    return .failure
                }
            },
            fileExists: { _ in true }
        )
    }

    private func providerForUntracked(status: String) -> DocumentTruthProvider {
        DocumentTruthProvider(
            gitRunner: FakeGitRunner { command, _ in
                switch command.arguments {
                case ["rev-parse", "--show-toplevel"]:
                    return .success("/repo")
                case ["ls-files", "--error-unmatch", "--", "docs/today.md"]:
                    return .failure
                case ["status", "--porcelain=v1", "--", "docs/today.md"]:
                    return .success(status)
                default:
                    XCTFail("Unexpected command: \(command.arguments)")
                    return .failure
                }
            },
            fileExists: { _ in true }
        )
    }
}

private struct FakeGitRunner: DocumentTruthGitRunning {
    var handler: (DocumentTruthGitCommand, URL) throws -> DocumentTruthGitResult

    init(handler: @escaping (DocumentTruthGitCommand, URL) throws -> DocumentTruthGitResult = { _, _ in .failure }) {
        self.handler = handler
    }

    func run(_ command: DocumentTruthGitCommand, workingDirectory: URL) throws -> DocumentTruthGitResult {
        try handler(command, workingDirectory)
    }
}

private extension DocumentTruthGitResult {
    static func success(_ stdout: String) -> DocumentTruthGitResult {
        DocumentTruthGitResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    static var failure: DocumentTruthGitResult {
        DocumentTruthGitResult(exitCode: 1, stdout: "", stderr: "not git")
    }
}
