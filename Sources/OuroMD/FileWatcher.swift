import Foundation

/// Watches a single file for external changes and invokes `onChange` on the
/// main queue (debounced). Re-arms itself across atomic saves (write-to-temp +
/// rename), which replace the inode and would otherwise leave a stale watch —
/// the common case when an agent or another editor rewrites the open file.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "md.ouro.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit { stop() }

    func start() { start(notifyOnAcquire: false) }

    /// `notifyOnAcquire` fires `onChange` once the watch is (re)established after
    /// the file had been missing — so a delete-then-recreate (e.g. an agent that
    /// removes a file before rewriting it) is reconciled instead of leaving the
    /// reader on a stale "deleted" view.
    private func start(notifyOnAcquire: Bool) {
        stop()
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File may be momentarily absent (mid-rename) or genuinely gone;
            // retry, and notify once it returns.
            queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.source == nil else { return }
                self.start(notifyOnAcquire: true)
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib, .link, .revoke],
            queue: queue)
        src.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            self.handle(flags: source.data)
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
        }
        source = src
        src.resume()
        if notifyOnAcquire {
            DispatchQueue.main.async { [weak self] in self?.onChange() }
        }
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
    }

    private func handle(flags: DispatchSource.FileSystemEvent) {
        // Coalesce bursts (atomic saves fire several events) into one reload.
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)

        // Atomic replace unlinks the watched inode — re-establish the watch on
        // the new file once the rename has settled, notifying when it returns.
        if !flags.intersection([.delete, .rename, .revoke]).isEmpty {
            queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.start(notifyOnAcquire: true) }
        }
    }
}
