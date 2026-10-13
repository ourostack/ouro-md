import Foundation
@testable import OuroMD

final class InMemoryPrintLayoutPreferenceStore: PrintLayoutPreferenceStore {
    private var doubles: [String: Double] = [:]
    private var bools: [String: Bool] = [:]

    func double(forKey key: String) -> Double? { doubles[key] }
    func bool(forKey key: String) -> Bool? { bools[key] }
    func set(_ value: Double, forKey key: String) { doubles[key] = value }
    func set(_ value: Bool, forKey key: String) { bools[key] = value }
}

enum PrintLayoutTestPaths {
    static func makeScratchDirectory(label: String) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/print-layout-test-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
