import AppKit
import WebKit

enum UndoRedoCommand {
    case undo
    case redo
}

@MainActor
final class UndoRedoShortcutMonitor {
    private var monitor: Any?
    private let handler: @MainActor (UndoRedoCommand, NSResponder?) -> Bool

    init(handler: @escaping @MainActor (UndoRedoCommand, NSResponder?) -> Bool) {
        self.handler = handler
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let command = UndoRedoCommandRouter.command(for: event) else {
                return event
            }
            let handled = MainActor.assumeIsolated {
                self.handler(command, NSApp.keyWindow?.firstResponder)
            }
            return handled ? nil : event
        }
    }

    func invalidate() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

}

/// Routes Undo/Redo between native AppKit text fields and the web editor.
@MainActor
enum UndoRedoCommandRouter {
    nonisolated static func command(for event: NSEvent) -> UndoRedoCommand? {
        guard event.type == .keyDown else { return nil }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return nil }

        if key == "z" {
            return flags.contains(.shift) ? .redo : .undo
        }
        if key == "y", !flags.contains(.shift) {
            return .redo
        }
        return nil
    }

    @discardableResult
    static func perform(_ command: UndoRedoCommand, firstResponder: NSResponder?, fallback: () -> Void) -> Bool {
        switch command {
        case .undo:
            return performUndo(firstResponder: firstResponder, fallback: fallback)
        case .redo:
            return performRedo(firstResponder: firstResponder, fallback: fallback)
        }
    }

    @discardableResult
    static func perform(_ command: UndoRedoCommand,
                        firstResponder: NSResponder?,
                        editorIsReady: Bool,
                        editorUndo: () -> Void,
                        editorRedo: () -> Void) -> Bool {
        var handledEditorFallback = false
        let handledNative = perform(command, firstResponder: firstResponder) {
            guard editorIsReady else { return }
            handledEditorFallback = true
            switch command {
            case .undo:
                editorUndo()
            case .redo:
                editorRedo()
            }
        }
        return handledNative || handledEditorFallback
    }

    @discardableResult
    static func performUndo(firstResponder: NSResponder?, fallback: () -> Void) -> Bool {
        guard let textView = firstResponder as? NSTextView,
              !isInsideWebView(textView) else {
            fallback()
            return false
        }
        if let undoManager = textView.undoManager, undoManager.canUndo {
            undoManager.undo()
        }
        return true
    }

    @discardableResult
    static func performRedo(firstResponder: NSResponder?, fallback: () -> Void) -> Bool {
        guard let textView = firstResponder as? NSTextView,
              !isInsideWebView(textView) else {
            fallback()
            return false
        }
        if let undoManager = textView.undoManager, undoManager.canRedo {
            undoManager.redo()
        }
        return true
    }

    private static func isInsideWebView(_ responder: NSResponder) -> Bool {
        var current: NSResponder? = responder
        while let candidate = current {
            if candidate is WKWebView { return true }
            if let view = candidate as? NSView {
                var ancestor: NSView? = view
                while let node = ancestor {
                    if node is WKWebView { return true }
                    ancestor = node.superview
                }
            }
            current = candidate.nextResponder
        }
        return false
    }
}
