import Foundation

/// Watches a single file for external changes and invokes `onChange` on the main
/// queue (debounced). Combines two mechanisms so a live reload is **never**
/// silently missed — the agent↔human review loop must not strand the reader on
/// stale content until relaunch:
///
///  1. A vnode `DispatchSource` for instant reaction to in-place writes and the
///     first atomic replace. Fast, but it can go deaf across a *burst* of atomic
///     saves: write-to-temp + rename repeatedly replaces the inode faster than a
///     single fd-bound source can re-arm, so later events land on an inode
///     nobody is watching. (This is the "often goes stale" failure — agents
///     rewrite files in quick succession.)
///  2. A ~1s `stat` poll as a hard guarantee. Even if every vnode event is
///     missed, a changed modification time or size is caught within a second.
///     It needs only the file access the app already holds, so it also covers
///     the sandboxed case where watching the parent directory would be denied.
///
/// Together they give instant reloads in the common case and a bounded-latency
/// guarantee in the pathological one.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "md.ouro.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounce: DispatchWorkItem?
    private var poll: DispatchSourceTimer?
    /// Last on-disk identity we reconciled, so the poll only fires on real change.
    private var lastStamp: FileStamp?

    /// Modification time + size — cheap to read and enough to detect any external
    /// rewrite (content edits bump mtime; truncations/growth change size).
    private struct FileStamp: Equatable {
        var seconds: Int
        var nanoseconds: Int
        var size: Int64
    }

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit { stop() }

    func start() { start(notifyOnAcquire: false) }

    /// `notifyOnAcquire` fires `onChange` once the vnode watch is (re)established
    /// after the file had been missing — so a delete-then-recreate (e.g. an agent
    /// that removes a file before rewriting it) is reconciled instead of leaving
    /// the reader on a stale "deleted" view.
    private func start(notifyOnAcquire: Bool) {
        stopSources()
        lastStamp = Self.stamp(of: url.path)
        armVnode(notifyOnAcquire: notifyOnAcquire)
        armPoll()
    }

    private func armVnode(notifyOnAcquire: Bool) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File may be momentarily absent (mid-rename) or genuinely gone; the
            // poll still covers reappearance. Retry the vnode, notifying once it
            // returns so a delete-recreate reconciles promptly.
            queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.source == nil else { return }
                self.armVnode(notifyOnAcquire: true)
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
            fire()
        }
    }

    private func armPoll() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = Self.stamp(of: self.url.path)
            guard current != self.lastStamp else { return }
            self.lastStamp = current
            self.scheduleChange()
        }
        poll = timer
        timer.resume()
    }

    func stop() {
        stopSources()
    }

    private func stopSources() {
        debounce?.cancel()
        debounce = nil
        poll?.cancel()
        poll = nil
        source?.cancel()
        source = nil
    }

    private func handle(flags: DispatchSource.FileSystemEvent) {
        lastStamp = Self.stamp(of: url.path)
        scheduleChange()

        // Atomic replace unlinks the watched inode — re-establish the vnode on the
        // new file once the rename settles. The poll bridges any gap, so a missed
        // re-arm can only ever cost up to one poll interval, never a lost reload.
        if !flags.intersection([.delete, .rename, .revoke]).isEmpty {
            source?.cancel()
            source = nil
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.source == nil else { return }
                self.armVnode(notifyOnAcquire: false)
            }
        }
    }

    /// Coalesce bursts (an atomic save fires several events) into one reload.
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fire() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func fire() {
        DispatchQueue.main.async { [weak self] in self?.onChange() }
    }

    private static func stamp(of path: String) -> FileStamp? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileStamp(
            seconds: info.st_mtimespec.tv_sec,
            nanoseconds: info.st_mtimespec.tv_nsec,
            size: Int64(info.st_size))
    }
}
