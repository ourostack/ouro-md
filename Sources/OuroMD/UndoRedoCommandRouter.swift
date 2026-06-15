import AppKit

/// Routes Undo/Redo between native AppKit text fields and the web editor.
@MainActor
enum UndoRedoCommandRouter {
    @discardableResult
    static func performUndo(firstResponder: NSResponder?, fallback: () -> Void) -> Bool {
        guard let textView = firstResponder as? NSTextView else {
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
        guard let textView = firstResponder as? NSTextView else {
            fallback()
            return false
        }
        if let undoManager = textView.undoManager, undoManager.canRedo {
            undoManager.redo()
        }
        return true
    }
}
