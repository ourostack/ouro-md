import XCTest
@testable import OuroMDCore

final class HTMLDocumentTests: XCTestCase {
    func testEscapeHandlesEveryReservedCharacterAndPassesOthersThrough() {
        XCTAssertEqual(HTMLDocument.escape("a & b < c > d \" e"),
                       "a &amp; b &lt; c &gt; d \" e")
        XCTAssertEqual(HTMLDocument.escape("plain text"), "plain text")
        XCTAssertEqual(HTMLDocument.escape(""), "")
    }

    func testEscapeAttrAlsoEscapesDoubleQuotes() {
        XCTAssertEqual(HTMLDocument.escapeAttr("he said \"<hi>\" & left"),
                       "he said &quot;&lt;hi&gt;&quot; &amp; left")
    }

    func testWrapProducesCompleteDocumentWithEscapedTitleAndEmbeddedCSS() {
        let html = HTMLDocument.wrap(body: "<p>hello</p>", css: ".x{color:red}", title: "A & B")
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<title>A &amp; B</title>"))
        XCTAssertTrue(html.contains(".x{color:red}"))
        XCTAssertTrue(html.contains(HTMLDocument.baseReset))
        XCTAssertTrue(html.contains("<article class=\"markdown-body\">\n<p>hello</p>"))
        XCTAssertTrue(html.hasSuffix("</html>"))
    }
}
