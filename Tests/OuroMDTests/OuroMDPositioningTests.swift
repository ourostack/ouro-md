import XCTest
@testable import OuroMD
import OuroMDCore

final class OuroMDPositioningTests: XCTestCase {
    @MainActor
    func testShellAboutSubtitleUsesLocalWorkspacePositioning() throws {
        let subtitle = try XCTUnwrap(OuroMDShellContract.contract.about?.subtitle)

        XCTAssertEqual(subtitle, "Local Markdown workspace for Mac files.")
        XCTAssertFalse(subtitle.localizedCaseInsensitiveContains("Markdown editor"))
    }

    func testWelcomeCopyExplainsLocalWorkspaceWorkflow() {
        let markdown = Welcome.markdown

        XCTAssertTrue(markdown.localizedCaseInsensitiveContains("local Markdown workspace"))
        XCTAssertTrue(markdown.contains("Shift-Command-O"))
        XCTAssertTrue(markdown.contains("File Tree"))
        XCTAssertTrue(markdown.contains("Outline"))
        XCTAssertTrue(markdown.contains("Search"))
        XCTAssertTrue(markdown.contains("Command Palette"))
        XCTAssertTrue(markdown.contains("PDF"))
        XCTAssertTrue(markdown.contains("HTML"))
        XCTAssertTrue(markdown.localizedCaseInsensitiveContains("No account"))
        XCTAssertFalse(markdown.localizedCaseInsensitiveContains("minimalist"))
        XCTAssertFalse(markdown.localizedCaseInsensitiveContains("Markdown editor"))
    }

    func testReleaseHighlightsCarryReviewFacingDifferentiators() {
        let highlights = OuroMDRelease.releaseHighlights.joined(separator: "\n")

        for required in [
            "local Markdown workspace",
            "folder",
            "Search",
            "Outline",
            "Command Palette",
            "PDF",
            "HTML",
            "No account"
        ] {
            XCTAssertTrue(
                highlights.localizedCaseInsensitiveContains(required),
                "release highlights should mention \(required)"
            )
        }
        XCTAssertFalse(highlights.localizedCaseInsensitiveContains("Markdown editor"))
    }
}
