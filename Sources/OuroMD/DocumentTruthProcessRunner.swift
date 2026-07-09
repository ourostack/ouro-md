import Foundation
import OuroMDAppSupport

struct ProcessDocumentTruthGitRunner: DocumentTruthGitRunning {
    func run(_ command: DocumentTruthGitCommand, workingDirectory: URL) throws -> DocumentTruthGitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = command.arguments
        process.currentDirectoryURL = workingDirectory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            throw DocumentTruthGitError.unavailable
        }
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return DocumentTruthGitResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
