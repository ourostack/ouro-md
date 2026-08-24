import Foundation
import XCTest
@testable import OuroMDAppSupport

final class DocumentLinkTests: XCTestCase {
    private let current = URL(fileURLWithPath: "/tmp/ouro/project/notes/current.md")

    func testExternalWebAndMailSchemesStayExternal() {
        for raw in ["https://ouro.bot/path", "HTTP://example.com/a", "mailto:ari@example.com"] {
            guard case .external(let url) = DocumentLinkResolver.resolve(raw, relativeTo: current) else {
                return XCTFail("expected external target for \(raw)")
            }
            XCTAssertEqual(url.absoluteString.lowercased(), raw.lowercased())
        }
    }

    func testRelativeMarkdownResolvesBesideCurrentDocument() {
        XCTAssertEqual(
            DocumentLinkResolver.resolve("next.md", relativeTo: current),
            .markdownFile(URL(fileURLWithPath: "/tmp/ouro/project/notes/next.md"), fragment: nil)
        )
        XCTAssertEqual(
            DocumentLinkResolver.resolve("../plans/launch%20notes.MARKDOWN?mode=read#today", relativeTo: current),
            .markdownFile(URL(fileURLWithPath: "/tmp/ouro/project/plans/launch notes.MARKDOWN"), fragment: "today")
        )
        XCTAssertEqual(
            DocumentLinkResolver.resolve("%ZZ.md", relativeTo: current),
            .markdownFile(URL(fileURLWithPath: "/tmp/ouro/project/notes/%ZZ.md"), fragment: nil)
        )
    }

    func testAbsoluteAndFileMarkdownTargetsAreSupported() {
        XCTAssertEqual(
            DocumentLinkResolver.resolve("/Users/ari/Documents/readme.mdown#top", relativeTo: current),
            .markdownFile(URL(fileURLWithPath: "/Users/ari/Documents/readme.mdown"), fragment: "top")
        )
        XCTAssertEqual(
            DocumentLinkResolver.resolve("file:///Users/ari/Documents/readme.mkd?x=1#top", relativeTo: nil),
            .markdownFile(URL(fileURLWithPath: "/Users/ari/Documents/readme.mkd"), fragment: "top")
        )
        XCTAssertEqual(
            DocumentLinkResolver.resolve(" <../brief.md> ", relativeTo: current),
            .markdownFile(URL(fileURLWithPath: "/tmp/ouro/project/brief.md"), fragment: nil)
        )
    }

    func testAnchorsAndUnsupportedTargetsDoNotBecomeFiles() {
        XCTAssertEqual(DocumentLinkResolver.resolve("#decisions", relativeTo: current), .inDocumentAnchor("decisions"))
        XCTAssertEqual(DocumentLinkResolver.resolve("", relativeTo: current), .unsupported)
        XCTAssertEqual(DocumentLinkResolver.resolve("  ", relativeTo: current), .unsupported)
        XCTAssertEqual(DocumentLinkResolver.resolve("<>", relativeTo: current), .unsupported)
        XCTAssertEqual(DocumentLinkResolver.resolve("javascript:alert(1)", relativeTo: current), .unsupported)
        XCTAssertEqual(DocumentLinkResolver.resolve("file:///tmp/image.png", relativeTo: current), .unsupported)
        XCTAssertEqual(DocumentLinkResolver.resolve("image.png", relativeTo: current), .unsupported)
        XCTAssertEqual(DocumentLinkResolver.resolve("//server/share/readme.md", relativeTo: current), .unsupported)
        XCTAssertEqual(DocumentLinkResolver.resolve("next.md", relativeTo: nil), .unsupported)
        XCTAssertEqual(
            DocumentLinkResolver.resolve("next.md", relativeTo: URL(string: "https://example.com/current.md")),
            .unsupported
        )
        XCTAssertEqual(DocumentLinkResolver.resolve("?query=only", relativeTo: current), .unsupported)
    }
}
