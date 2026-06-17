import XCTest
@testable import OuroMD

/// The launch fallback must never spawn a blank window when a document has
/// already been opened (e.g. via `open file.md`, which arrives as a Finder
/// document event), and otherwise restore the session or open a new document.
final class AppDelegateLaunchTests: XCTestCase {
    func testSkipsFallbackWhenADocumentAlreadyOpened() {
        XCTAssertEqual(
            AppDelegate.resolveLaunchFallback(documentAlreadyOpen: true, hasRestorableSession: true),
            .openedDocument)
        XCTAssertEqual(
            AppDelegate.resolveLaunchFallback(documentAlreadyOpen: true, hasRestorableSession: false),
            .openedDocument)
    }

    func testRestoresSessionWhenOneExistsAndNoDocumentOpened() {
        XCTAssertEqual(
            AppDelegate.resolveLaunchFallback(documentAlreadyOpen: false, hasRestorableSession: true),
            .restoreSession)
    }

    func testOpensNewDocumentWhenNothingToRestore() {
        XCTAssertEqual(
            AppDelegate.resolveLaunchFallback(documentAlreadyOpen: false, hasRestorableSession: false),
            .newDocument)
    }
}
