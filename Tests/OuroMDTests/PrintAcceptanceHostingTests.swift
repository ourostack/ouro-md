import Foundation
import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintAcceptanceHostingTests: XCTestCase {
    func testExplicitPrintAcceptanceDoesNotRequireEditorActivation() {
        withAcceptanceFile("/tmp/print-acceptance-hosting-fixture.md") {
            XCTAssertFalse(EditorSurfaceTester().requiresFocusedEditor, "A print-only acceptance run must not take focus from the operator's desktop.")
        }
    }

    func testGeneralSurfaceJourneyRetainsItsFocusedEditorRequirement() {
        withAcceptanceFile(nil) {
            XCTAssertTrue(EditorSurfaceTester().requiresFocusedEditor, "Focused editing scenarios remain assigned to the isolated native runner.")
        }
    }

    func testExplicitPrintAcceptanceProhibitsImplicitApplicationActivation() {
        withAcceptanceFile("/tmp/print-acceptance-hosting-fixture.md") {
            XCTAssertEqual(EditorSurfaceTester().activationPolicy, .prohibited, "Merely avoiding an explicit activate call does not prevent a sheet from activating the process.")
        }
    }

    private func withAcceptanceFile(_ value: String?, body: () -> Void) {
        let key = "OURO_PRINT_ACCEPTANCE_FILE"
        let previous = ProcessInfo.processInfo.environment[key]
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        if let value {
            XCTAssertEqual(setenv(key, value, 1), 0)
        } else {
            XCTAssertEqual(unsetenv(key), 0)
        }
        body()
    }
}
