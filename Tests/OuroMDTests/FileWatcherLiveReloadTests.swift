import XCTest
@testable import OuroMD

/// End-to-end coverage of the REAL `FileWatcher` DispatchSource firing on real
/// external edits — the agent↔human live-reload loop. The other reload tests
/// drive reconcile via a debug hook and never exercise the watcher itself.
final class FileWatcherLiveReloadTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private func makeDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-watch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A single atomic replace, made AFTER the initial establishment window, must
    /// reach the watcher (this bypasses the 0.25s reconcile-after-start net).
    func testWatcherFiresOnAtomicReplaceAfterInitialWindow() {
        let dir = makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("note.md")
        try? "v0".write(to: url, atomically: true, encoding: .utf8)

        let exp = expectation(description: "atomic replace observed")
        exp.assertForOverFulfill = false
        var seen = ""
        let watcher = FileWatcher(url: url) {
            seen = (try? String(contentsOf: url, encoding: .utf8)) ?? seen
            if seen == "v1" { exp.fulfill() }
        }
        watcher.start(); defer { watcher.stop() }

        spin(0.5)
        try? "v1".write(to: url, atomically: true, encoding: .utf8)

        wait(for: [exp], timeout: 4)
        XCTAssertEqual(seen, "v1")
    }

    /// Rapid successive atomic replaces (an agent streaming edits) must leave the
    /// watcher live enough to surface the FINAL content — the "often goes stale"
    /// scenario the operator hit.
    func testWatcherReflectsRapidAtomicReplaces() {
        let dir = makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("note.md")
        try? "v0".write(to: url, atomically: true, encoding: .utf8)

        let exp = expectation(description: "final content observed")
        exp.assertForOverFulfill = false
        var seen = ""
        let watcher = FileWatcher(url: url) {
            seen = (try? String(contentsOf: url, encoding: .utf8)) ?? seen
            if seen == "vFINAL" { exp.fulfill() }
        }
        watcher.start(); defer { watcher.stop() }

        spin(0.5)
        for i in 1...4 {
            try? "v\(i)".write(to: url, atomically: true, encoding: .utf8)
            spin(0.05)
        }
        try? "vFINAL".write(to: url, atomically: true, encoding: .utf8)

        wait(for: [exp], timeout: 4)
        XCTAssertEqual(seen, "vFINAL")
    }
}
