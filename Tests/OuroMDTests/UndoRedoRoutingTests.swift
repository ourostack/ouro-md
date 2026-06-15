import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class UndoRedoRoutingTests: XCTestCase {
    func testUndoAndRedoMenuItemsTargetNativeAppDelegateSelectors() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        MenuBuilder.install(into: app, target: delegate)

        let editMenu = app.mainMenu?.item(withTitle: "Edit")?.submenu
        let undo = editMenu?.item(withTitle: "Undo")
        let redo = editMenu?.item(withTitle: "Redo")
        XCTAssertEqual(undo?.action, #selector(AppDelegate.undoEdit(_:)))
        XCTAssertTrue(undo?.target === delegate)
        XCTAssertEqual(redo?.action, #selector(AppDelegate.redoEdit(_:)))
        XCTAssertTrue(redo?.target === delegate)
    }

    func testUndoDoesNotFallThroughWhenNativeTextViewHasEmptyStack() {
        let manager = RecordingUndoManager()
        let textView = NativeTextView(undoManager: manager)
        var fallbackCount = 0

        let handledNative = UndoRedoCommandRouter.performUndo(firstResponder: textView) {
            fallbackCount += 1
        }

        XCTAssertTrue(handledNative)
        XCTAssertEqual(manager.undoCalls, 0)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testRedoDoesNotFallThroughWhenNativeTextViewHasEmptyStack() {
        let manager = RecordingUndoManager()
        let textView = NativeTextView(undoManager: manager)
        var fallbackCount = 0

        let handledNative = UndoRedoCommandRouter.performRedo(firstResponder: textView) {
            fallbackCount += 1
        }

        XCTAssertTrue(handledNative)
        XCTAssertEqual(manager.redoCalls, 0)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testUndoAndRedoUseNativeTextViewManagerWhenAvailable() {
        let manager = RecordingUndoManager(canUndo: true, canRedo: true)
        let textView = NativeTextView(undoManager: manager)
        var fallbackCount = 0

        XCTAssertTrue(UndoRedoCommandRouter.performUndo(firstResponder: textView) { fallbackCount += 1 })
        XCTAssertTrue(UndoRedoCommandRouter.performRedo(firstResponder: textView) { fallbackCount += 1 })

        XCTAssertEqual(manager.undoCalls, 1)
        XCTAssertEqual(manager.redoCalls, 1)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testUndoAndRedoFallBackWhenResponderIsNotNativeTextView() {
        let responder = NSResponder()
        var undoFallbackCount = 0
        var redoFallbackCount = 0

        XCTAssertFalse(UndoRedoCommandRouter.performUndo(firstResponder: responder) { undoFallbackCount += 1 })
        XCTAssertFalse(UndoRedoCommandRouter.performRedo(firstResponder: responder) { redoFallbackCount += 1 })

        XCTAssertEqual(undoFallbackCount, 1)
        XCTAssertEqual(redoFallbackCount, 1)
    }
}

private final class NativeTextView: NSTextView {
    private let testUndoManager: UndoManager

    init(undoManager: UndoManager) {
        self.testUndoManager = undoManager
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable in tests")
    }

    override var undoManager: UndoManager? { testUndoManager }
}

private final class RecordingUndoManager: UndoManager {
    private let canUndoValue: Bool
    private let canRedoValue: Bool
    private(set) var undoCalls = 0
    private(set) var redoCalls = 0

    init(canUndo: Bool = false, canRedo: Bool = false) {
        self.canUndoValue = canUndo
        self.canRedoValue = canRedo
        super.init()
    }

    override var canUndo: Bool { canUndoValue }
    override var canRedo: Bool { canRedoValue }

    override func undo() {
        undoCalls += 1
    }

    override func redo() {
        redoCalls += 1
    }
}
