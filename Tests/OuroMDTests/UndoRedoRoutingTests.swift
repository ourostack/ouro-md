import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class UndoRedoRoutingTests: XCTestCase {
    func testUndoAndRedoMenuItemsTargetNativeAppDelegateSelectors() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        MenuBuilder.install(into: app, target: delegate)

        let editMenu = app.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Edit" }
        let undo = editMenu?.item(withTitle: "Undo")
        let redo = editMenu?.item(withTitle: "Redo")
        XCTAssertEqual(undo?.action, #selector(AppDelegate.undoEdit(_:)))
        XCTAssertTrue(undo?.target === delegate)
        XCTAssertEqual(redo?.action, #selector(AppDelegate.redoEdit(_:)))
        XCTAssertTrue(redo?.target === delegate)
    }

    func testMenuValidationDisablesEditorOnlyCommandsWithoutAWindow() {
        let delegate = AppDelegate()

        let save = NSMenuItem(title: "Save", action: #selector(AppDelegate.saveDocument(_:)), keyEquivalent: "")
        let rename = NSMenuItem(title: "Rename", action: #selector(AppDelegate.renameDocument(_:)), keyEquivalent: "")
        let undo = NSMenuItem(title: "Undo", action: #selector(AppDelegate.undoEdit(_:)), keyEquivalent: "")

        XCTAssertFalse(delegate.validateMenuItem(save))
        XCTAssertFalse(delegate.validateMenuItem(rename))
        XCTAssertFalse(delegate.validateMenuItem(undo))
    }

    func testMenuValidationKeepsGlobalCommandsEnabledWithoutAWindow() {
        let delegate = AppDelegate()

        let new = NSMenuItem(title: "New", action: #selector(AppDelegate.newDocument(_:)), keyEquivalent: "")
        let open = NSMenuItem(title: "Open", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "")
        let updates = NSMenuItem(title: "Check for Updates", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")

        XCTAssertTrue(delegate.validateMenuItem(new))
        XCTAssertTrue(delegate.validateMenuItem(open))
        XCTAssertTrue(delegate.validateMenuItem(updates))
    }

    func testMenuValidationChecksRecentItemsAndDefaults() {
        let delegate = AppDelegate()

        let recent = NSMenuItem(title: "Recent", action: #selector(AppDelegate.openRecent(_:)), keyEquivalent: "")
        XCTAssertFalse(delegate.validateMenuItem(recent))
        recent.representedObject = URL(fileURLWithPath: "/tmp/example.md")
        XCTAssertTrue(delegate.validateMenuItem(recent))

        let clearRecent = NSMenuItem(title: "Clear Recent", action: #selector(AppDelegate.clearRecentDocuments(_:)), keyEquivalent: "")
        XCTAssertEqual(delegate.validateMenuItem(clearRecent), !NSDocumentController.shared.recentDocumentURLs.isEmpty)

        let unknown = NSMenuItem(title: "Unknown", action: Selector(("unknownCommand:")), keyEquivalent: "")
        XCTAssertTrue(delegate.validateMenuItem(unknown))
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
    private var testUndoManager: UndoManager

    init(undoManager: UndoManager) {
        self.testUndoManager = undoManager
        super.init(frame: .zero, textContainer: nil)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        self.testUndoManager = UndoManager()
        super.init(frame: frameRect, textContainer: container)
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
