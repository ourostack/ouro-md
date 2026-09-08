import XCTest
@testable import OuroMD

final class FileWatcherTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-watch-\(UUID().uuidString).md")
    }

    func testDetectsInPlaceWrite() {
        let url = tempFile()
        try? "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let exp = expectation(description: "in-place write detected")
        exp.assertForOverFulfill = false
        let watcher = FileWatcher(url: url) { exp.fulfill() }
        watcher.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? "changed in place".write(to: url, atomically: false, encoding: .utf8)
        }
        wait(for: [exp], timeout: 5)
        watcher.stop()
    }

    func testReArmsAcrossAtomicReplace() {
        // Atomic writes (temp file + rename) replace the inode — the watcher
        // must re-arm and still fire on a subsequent external change. This is
        // the common case: most editors/agents save atomically.
        let url = tempFile()
        try? "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let exp = expectation(description: "change after atomic replace detected")
        exp.assertForOverFulfill = false
        let watcher = FileWatcher(url: url) { exp.fulfill() }
        watcher.start()
        // First atomic write triggers rename/delete + re-arm; second change
        // must still be observed via the re-armed watch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? "agent edit one".write(to: url, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            try? "agent edit two".write(to: url, atomically: true, encoding: .utf8)
        }
        wait(for: [exp], timeout: 6)
        watcher.stop()
    }

    func testRestartWhileFileChanges() throws {
        let url = tempFile()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let writesFinished = expectation(description: "external writes finished")
        let finalChange = expectation(description: "watcher remains live after restarts")
        finalChange.assertForOverFulfill = false
        let watcher = FileWatcher(url: url) {
            if (try? String(contentsOf: url, encoding: .utf8)) == "final" {
                finalChange.fulfill()
            }
        }
        watcher.start()
        defer { watcher.stop() }

        DispatchQueue.global(qos: .userInitiated).async {
            defer { writesFinished.fulfill() }
            do {
                for index in 0..<200 {
                    try "edit \(index)".write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                XCTFail("External write failed: \(error)")
            }
        }
        for _ in 0..<200 {
            watcher.stop()
            watcher.start()
        }
        wait(for: [writesFinished], timeout: 5)
        try "final".write(to: url, atomically: false, encoding: .utf8)
        wait(for: [finalChange], timeout: 3)
    }

    func testStopWhileFileIsMissingDoesNotRearm() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let unexpectedChange = expectation(description: "stopped watcher stays stopped")
        unexpectedChange.isInverted = true
        let watcher = FileWatcher(url: url) { unexpectedChange.fulfill() }
        watcher.start()
        watcher.stop()
        defer { watcher.stop() }

        try "restored".write(to: url, atomically: true, encoding: .utf8)
        wait(for: [unexpectedChange], timeout: 0.6)
    }

    func testStopSuppressesAlreadyQueuedChange() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let unexpectedChange = expectation(description: "queued notification is cancelled")
        unexpectedChange.isInverted = true
        let watcher = FileWatcher(url: url) { unexpectedChange.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        try "restored".write(to: url, atomically: true, encoding: .utf8)
        // Let recovery enqueue its notification while the main queue is occupied.
        Thread.sleep(forTimeInterval: 0.35)
        watcher.stop()
        wait(for: [unexpectedChange], timeout: 0.6)
    }
}
