import XCTest
@testable import OuroMD

final class MarkdownRendererTests: XCTestCase {
    private func render(_ markdown: String) -> String {
        MarkdownRenderer.renderHTMLBody(markdown)
    }

    func testHeading() {
        let html = render("# Hello")
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains(">Hello</h1>"))
    }

    func testHeadingHasSlugID() {
        XCTAssertTrue(render("## My Section!").contains("id=\"my-section\""))
    }

    func testBoldAndItalic() {
        let html = render("**bold** and *italic*")
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
    }

    func testInlineCode() {
        XCTAssertTrue(render("`code`").contains("<code>code</code>"))
    }

    func testLink() {
        XCTAssertTrue(render("[text](https://example.com)").contains("<a href=\"https://example.com\">text</a>"))
    }

    func testUnorderedList() {
        let html = render("- a\n- b\n- c")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertEqual(html.components(separatedBy: "<li>").count - 1, 3)
    }

    func testOrderedList() {
        XCTAssertTrue(render("1. one\n2. two").contains("<ol>"))
    }

    func testTaskList() {
        let html = render("- [x] done\n- [ ] todo")
        XCTAssertTrue(html.contains("type=\"checkbox\""))
        XCTAssertTrue(html.contains("checked"))
    }

    func testBlockQuote() {
        XCTAssertTrue(render("> quoted").contains("<blockquote>"))
    }

    func testThematicBreak() {
        XCTAssertTrue(render("---").contains("<hr>"))
    }

    func testStrikethrough() {
        XCTAssertTrue(render("~~gone~~").contains("<del>gone</del>"))
    }

    func testFencedCodeBlock() {
        let html = render("```swift\nlet x = 1\n```")
        XCTAssertTrue(html.contains("<pre>"))
        XCTAssertTrue(html.contains("class=\"language-swift\""))
        XCTAssertTrue(html.contains("let x = 1"))
    }

    func testHTMLEscaping() {
        let html = render("a < b & c")
        XCTAssertTrue(html.contains("&lt;"))
        XCTAssertTrue(html.contains("&amp;"))
    }

    func testTable() {
        let html = render("| A | B |\n|:--|--:|\n| 1 | 2 |")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th"))
        XCTAssertTrue(html.contains("<td"))
        XCTAssertTrue(html.contains("text-align"))
    }

    func testImageAlt() {
        let html = render("![the alt](pic.png)")
        XCTAssertTrue(html.contains("<img"))
        XCTAssertTrue(html.contains("alt=\"the alt\""))
    }

    func testDocumentWrap() {
        let html = HTMLDocument.wrap(body: "<p>x</p>", css: "body{}", title: "t")
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("class=\"markdown-body\""))
        XCTAssertTrue(html.contains("<p>x</p>"))
    }

    func testThemeStore() {
        XCTAssertGreaterThanOrEqual(ThemeStore.shared.themes.count, 4)
        XCTAssertEqual(ThemeStore.shared.theme(id: "quartz").id, "quartz")
        XCTAssertEqual(ThemeStore.shared.theme(id: "does-not-exist").id, "quartz")
        XCTAssertFalse(ThemeStore.shared.theme(id: "graphite").editorCSS.isEmpty)
    }
}
