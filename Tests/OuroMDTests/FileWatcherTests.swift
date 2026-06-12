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
}
