import CryptoKit
import Foundation

public protocol ReadingBaselineStoring {
    func read(for file: URL) throws -> String?
    func write(_ markdown: String, for file: URL) throws
}

/// Private reading history, separate from the document and its Git history.
public struct ReadingBaselineStore: ReadingBaselineStoring {
    private struct Record: Codable {
        let version: Int
        let markdown: String
    }

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ouro MD/Reading Baselines", isDirectory: true)
    }

    public func read(for file: URL) throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: recordURL(for: file))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.version == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return record.markdown
    }

    public func write(_ markdown: String, for file: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let destination = recordURL(for: file)
        let data = try JSONEncoder().encode(Record(version: 1, markdown: markdown))
        try data.write(to: destination, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private func recordURL(for file: URL) -> URL {
        let identity = file.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
}
