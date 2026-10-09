import Foundation
import XCTest
@testable import OuroMD

/// Guards against tests and harnesses leaving `UserDefaults` domains behind in
/// `~/Library/Preferences`. A named suite there survives
/// `removePersistentDomain(forName:)` as an empty plist, so every per-run suite
/// name used to add one file per test. Test-owned code must use
/// `ScratchUserDefaults`, which keeps its store in a temporary directory.
final class TestDefaultsHygieneTests: XCTestCase {
    private var preferencesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    func testScratchDefaultsNeverWriteToUserPreferences() throws {
        let label = "OuroMDDefaultsHygieneTests-\(UUID().uuidString)"
        let scratch = ScratchUserDefaults(label: label)
        scratch.defaults.set("value", forKey: "key")
        scratch.defaults.set(Date(), forKey: "date")
        XCTAssertEqual(scratch.defaults.string(forKey: "key"), "value")

        scratch.reset()
        XCTAssertNil(scratch.defaults.string(forKey: "key"))
        scratch.defaults.set("again", forKey: "key")
        XCTAssertEqual(scratch.defaults.string(forKey: "key"), "again")

        XCTAssertTrue(scratch.suiteName.hasPrefix(scratch.directory.path))
        let preferencesFile = preferencesDirectory.appendingPathComponent("\(label).plist")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: preferencesFile.path),
            "scratch defaults must not create \(preferencesFile.path)"
        )

        scratch.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferencesFile.path))
    }

    func testTestOwnedCodeDoesNotOpenNamedDefaultsSuites() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileManager = FileManager.default

        var files: [URL] = []
        let testsDirectory = root.appendingPathComponent("Tests", isDirectory: true)
        if let enumerator = fileManager.enumerator(at: testsDirectory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        let harnessDirectory = root.appendingPathComponent("Sources/OuroMD", isDirectory: true)
        for name in try fileManager.contentsOfDirectory(atPath: harnessDirectory.path)
        where name.hasSuffix("Test.swift") || name.hasSuffix("Probe.swift") {
            files.append(harnessDirectory.appendingPathComponent(name))
        }
        XCTAssertFalse(files.isEmpty, "found no test sources under \(root.path)")

        let forbidden = ["UserDefaults(suiteName:", "removePersistentDomain(forName:"]
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var offenders: [String] = []
        for file in files where file.standardizedFileURL != thisFile {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated()
            where forbidden.contains(where: { line.contains($0) }) {
                let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
                offenders.append("\(relative):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "Use ScratchUserDefaults instead of a named UserDefaults suite; named suites leave plists in ~/Library/Preferences:\n"
                + offenders.joined(separator: "\n")
        )
    }
}
