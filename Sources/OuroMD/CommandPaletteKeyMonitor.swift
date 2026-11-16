import AppKit

/// The command palette's arrow keys. The palette's text field keeps the cursor, and a text field takes the up and down
/// arrows for itself (to the start or end of its line) before SwiftUI's key handlers see them, so the palette reads
/// them first, here, while its field has focus: down and up move the selection, as in Spotlight.
@MainActor
final class CommandPaletteKeyMonitor {
    private var monitor: Any?
    /// The palette's own window: arrow keys in any other window (another document, an Open panel) are left alone.
    private weak var window: NSWindow?
    private let move: @MainActor (Int) -> Void

    init(move: @escaping @MainActor (Int) -> Void) {
        self.move = move
    }

    /// How far a key moves the selection: down 1, up -1, or nil for any other key, or an arrow held with
    /// Command, Option or Control, which keeps its usual meaning.
    nonisolated static func offset(for event: NSEvent) -> Int? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        switch event.keyCode {
        case 125: return 1
        case 126: return -1
        default: return nil
        }
    }

    /// Starts reading the arrow keys in `window`, the key window when the palette's field takes focus.
    func install(in window: NSWindow? = nil) {
        guard monitor == nil else { return }
        self.window = window ?? NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window != nil, event.window === MainActor.assumeIsolated({ self.window }),
                  let offset = Self.offset(for: event) else { return event }
            MainActor.assumeIsolated { self.move(offset) }
            return nil
        }
    }

    func invalidate() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
