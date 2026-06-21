import XCTest
@testable import OuroMD
import OuroMDCore

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

    func testHeadingSlugCollapsesRuns() {
        XCTAssertTrue(render("## My  Section__Again").contains("id=\"my-section-again\""))
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

    func testCodeOnlyTableCellsAreMarkedForIntrinsicWidth() {
        let html = render("| Path | Notes |\n| --- | --- |\n| `Sources/OuroMD/MarkdownRenderer.swift` | Mixed prose with `shortCode` should wrap normally. |")

        XCTAssertTrue(html.contains("<td class=\"ouro-code-only-cell\"><code>Sources/OuroMD/MarkdownRenderer.swift</code></td>"))
        XCTAssertFalse(html.contains("class=\"ouro-code-only-cell\">Mixed prose"))
    }

    func testPathologicalTableCellsRenderAlignmentHTMLURLsAndEmptyCells() {
        let html = render("""
        | Left | Center | Right | HTML | URL | Empty | Code |
        | :--- | :---: | ---: | --- | --- | --- | --- |
        | alpha | beta | 42 | <kbd>Cmd</kbd><br><span>Span</span> | https://example.com/very/long/path |  | `Sources/OuroMD/LongPath.swift` |
        """)

        XCTAssertTrue(html.contains("<th style=\"text-align:left\">Left</th>"))
        XCTAssertTrue(html.contains("<th style=\"text-align:center\">Center</th>"))
        XCTAssertTrue(html.contains("<th style=\"text-align:right\">Right</th>"))
        XCTAssertTrue(html.contains("<kbd>Cmd</kbd>"))
        XCTAssertTrue(html.contains("<br>"))
        XCTAssertTrue(html.contains("https://example.com/very/long/path"))
        XCTAssertTrue(html.contains("<td></td>"))
        XCTAssertTrue(html.contains("<td style=\"text-align:right\">42</td>"))
        XCTAssertTrue(html.contains("<td class=\"ouro-code-only-cell\"><code>Sources/OuroMD/LongPath.swift</code></td>"))
    }

    func testImageAlt() {
        let html = render("![the alt](pic.png)")
        XCTAssertTrue(html.contains("<img"))
        XCTAssertTrue(html.contains("alt=\"the alt\""))
    }

    func testImageSourcesAreEscapedOrInlined() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-render-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for ext in ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "heic", "bin"] {
            try Data([0x41, 0x42]).write(to: root.appendingPathComponent("pic.\(ext)"))
        }

        let markdown = """
        ![remote](https://example.com/a.png)
        ![empty]()
        ![png](pic.png)
        ![jpg](pic.jpg)
        ![jpeg](pic.jpeg)
        ![gif](pic.gif)
        ![svg](pic.svg)
        ![webp](pic.webp)
        ![bmp](pic.bmp)
        ![heic](pic.heic)
        ![bin](pic.bin)
        """
        let html = MarkdownRenderer.renderHTMLBody(markdown, baseDirectory: root)

        XCTAssertTrue(html.contains("src=\"https://example.com/a.png\""))
        XCTAssertTrue(html.contains("src=\"\""))
        XCTAssertTrue(html.contains("data:image/png;base64"))
        XCTAssertTrue(html.contains("data:image/jpeg;base64"))
        XCTAssertTrue(html.contains("data:image/gif;base64"))
        XCTAssertTrue(html.contains("data:image/svg+xml;base64"))
        XCTAssertTrue(html.contains("data:image/webp;base64"))
        XCTAssertTrue(html.contains("data:image/bmp;base64"))
        XCTAssertTrue(html.contains("data:image/heic;base64"))
        XCTAssertTrue(html.contains("src=\"pic.bin\""))
    }

    func testFootnotesRenderAsBacklinkedSection() {
        let html = render("Body with note[^alpha].\n\n[^alpha]: Footnote **text**.")

        XCTAssertTrue(html.contains("class=\"footnote-ref\""))
        XCTAssertTrue(html.contains("href=\"#fn-alpha\""))
        XCTAssertTrue(html.contains("<section class=\"footnotes\">"))
        XCTAssertTrue(html.contains("<li id=\"fn-alpha\"><p>Footnote <strong>text</strong>.</p>"))
        XCTAssertFalse(html.contains("[^alpha]:"))
    }

    func testRepeatedFootnoteReferencesUseUniqueAnchorIDs() {
        let html = render("One[^a] two[^a].\n\n[^a]: footnote")

        XCTAssertTrue(html.contains("id=\"fnref-a\""))
        XCTAssertTrue(html.contains("id=\"fnref-a-2\""))
        XCTAssertEqual(html.components(separatedBy: "class=\"footnote-ref\"").count - 1, 2)
        XCTAssertTrue(html.contains("href=\"#fnref-a\""))
        XCTAssertTrue(html.contains("href=\"#fnref-a-2\""))
    }

    func testFootnoteContinuationsAreRendered() {
        let html = render("Body[^a].\n\n[^a]: first\n    second\n\tthird")

        XCTAssertTrue(html.contains("first\nsecond\nthird"))
        XCTAssertFalse(html.contains("[^a]:"))
    }

    func testFootnoteMultiParagraphContinuationRendersInsideFootnote() {
        let html = render("Body[^a].\n\n[^a]: first\n\n    second paragraph\n\nBody after.")

        XCTAssertTrue(html.contains("<li id=\"fn-a\"><p>first</p>\n<p>second paragraph</p>"))
        XCTAssertTrue(html.contains("<p>Body after.</p>"))
        XCTAssertFalse(html.contains("[^a]:"))
    }

    func testBrokenOrUnknownFootnoteReferencesAreLeftAsText() {
        let html = render("Known[^a] unknown[^missing] broken[^oops\n\n[^a]: ok")

        XCTAssertTrue(html.contains("class=\"footnote-ref\""))
        XCTAssertTrue(html.contains("unknown[^missing]"))
        XCTAssertTrue(html.contains("broken[^oops"))
    }

    func testDuplicateFootnoteDefinitionsDoNotCrash() {
        let html = render("Body[^a].\n\n[^a]: first\n[^a]: second")

        XCTAssertTrue(html.contains("<li id=\"fn-a\"><p>first</p>"))
        XCTAssertFalse(html.contains("second</p>"))
    }

    func testFootnoteDefinitionsInsideCodeBlocksRemainCode() {
        let html = render("```md\n[^a]: literal\n```\n\n    [^b]: indented code\n\nBody[^real].\n\n[^real]: ok")

        XCTAssertTrue(html.contains("[^a]: literal"))
        XCTAssertTrue(html.contains("[^b]: indented code"))
        XCTAssertTrue(html.contains("<li id=\"fn-real\"><p>ok</p>"))
        XCTAssertFalse(html.contains("id=\"fn-a\""))
        XCTAssertFalse(html.contains("id=\"fn-b\""))
    }

    func testLongFencesCanContainShorterFenceExamples() {
        let markdown = """
        ````markdown
        ```md
        [^a]: literal
        ```
        literal[^a]
        ````

        Body[^real].

        [^real]: ok
        """
        let html = render(markdown)

        XCTAssertTrue(html.contains("[^a]: literal"))
        XCTAssertTrue(html.contains("literal[^a]"))
        XCTAssertTrue(html.contains("<li id=\"fn-real\"><p>ok</p>"))
        XCTAssertFalse(html.contains("id=\"fn-a\""))
    }

    func testFootnoteReferencesInsideInlineCodeOrEscapesAreLeftAlone() {
        let html = render("Real[^a] code `[^a]` escaped \\[^a].\n\n[^a]: ok")

        XCTAssertTrue(html.contains("Real<sup"))
        XCTAssertTrue(html.contains("<code>[^a]</code>"))
        XCTAssertTrue(html.contains("escaped [^a]."))
        XCTAssertEqual(html.components(separatedBy: "class=\"footnote-ref\"").count - 1, 1)
    }

    func testFootnoteReferencesInsideFencedCodeAreLeftAlone() {
        let html = render("```md\nliteral[^a]\n```\n\n[^a]: footnote")

        XCTAssertTrue(html.contains("literal[^a]"))
        XCTAssertFalse(html.contains("<sup id=\"fnref-a\""))
    }

    func testFootnoteReferencesInsideIndentedCodeAreLeftAlone() {
        let html = render("    literal[^a]\n\nBody[^a].\n\n[^a]: footnote")

        XCTAssertTrue(html.contains("literal[^a]"))
        XCTAssertTrue(html.contains("Body<sup"))
        XCTAssertEqual(html.components(separatedBy: "class=\"footnote-ref\"").count - 1, 1)
    }

    func testDocumentWrap() {
        let html = HTMLDocument.wrap(body: "<p>x</p>", css: "body{}", title: "t")
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("class=\"markdown-body\""))
        XCTAssertTrue(html.contains("<p>x</p>"))
    }

    func testLineBreaksAndRawHTMLPassThrough() {
        let html = render("a  \nb\n\n<div>raw</div>")

        XCTAssertTrue(html.contains("<br>"))
        XCTAssertTrue(html.contains("<div>raw</div>"))
    }

    func testThemeStore() {
        XCTAssertGreaterThanOrEqual(ThemeStore.shared.themes.count, 4)
        XCTAssertEqual(ThemeStore.shared.theme(id: "quartz").id, "quartz")
        XCTAssertEqual(ThemeStore.shared.theme(id: "does-not-exist").id, "quartz")
        XCTAssertFalse(ThemeStore.shared.theme(id: "graphite").editorCSS.isEmpty)
    }
}
