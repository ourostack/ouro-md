import WebKit
import XCTest
@testable import OuroMD

final class EditorWritingToolsTests: XCTestCase {
    /// The editor asks for the complete inline Writing Tools experience, not
    /// WebKit's default overlay panel.
    func testEditorConfigurationRequestsCompleteWritingTools() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Writing Tools needs macOS 15") }
        let configuration = WKWebViewConfiguration()
        // Stored as "default", which WebKit resolves to the limited overlay panel.
        XCTAssertNotEqual(EditorWritingTools.behavior(of: configuration), NSWritingToolsBehavior.complete.rawValue)
        EditorWritingTools.enableInlineEditing(on: configuration)
        XCTAssertEqual(EditorWritingTools.behavior(of: configuration), NSWritingToolsBehavior.complete.rawValue)
    }
}
