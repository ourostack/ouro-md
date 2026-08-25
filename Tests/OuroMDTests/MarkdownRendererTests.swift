import XCTest
@testable import OuroMD
import OuroMDCore

final class MarkdownRendererTests: XCTestCase {
    private struct AnchorContract: Decodable {
        struct Case: Decodable {
            let text: String
            let expected: String
        }
        let cases: [Case]
    }

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

    func testHeadingIDsReserveAuthoredRawHTMLIDs() {
        let html = render("<div id=\"same\"></div>\n\n# Same")

        XCTAssertTrue(html.contains("<div id=\"same\"></div>"))
        XCTAssertTrue(html.contains("<h1 id=\"same-1\">Same</h1>"))
        XCTAssertEqual(html.components(separatedBy: "id=\"same\"").count - 1, 1)
    }

    func testAuthoredRawHTMLHeadingsUseSharedSemanticIDs() {
        let html = render("""
        <h1 class="kept" id="legacy">Raw &amp; <em>Heading</em></h1>

        # Raw & Heading
        """)

        XCTAssertTrue(html.contains("<h1 class=\"kept\" id=\"raw-heading\">"))
        XCTAssertTrue(html.contains("<h1 id=\"raw-heading-1\">Raw &amp; Heading</h1>"))
        XCTAssertFalse(html.contains("id=\"legacy\""))
    }

    func testRawHTMLHeadingNormalizerHonorsForeignContentAndImageAltText() {
        var slugger = HeadingAnchorSlugger(reserving: RawHTMLHeadingNormalizer.nonHeadingIDs(
            in: #"<svg><g id="svg-heading">SVG fake</g><script /></svg>"#
        ))
        let html = RawHTMLHeadingNormalizer.normalize(
            #"<svg><g id="svg-heading">SVG fake</g><script /></svg><h2><img alt="Image Alt" src="ignored.png">Line<br>Break &copy;</h2><h2>SVG Heading</h2>"#,
            slugger: &slugger
        )

        XCTAssertTrue(html.contains(#"<svg><g id="svg-heading">SVG fake</g><script /></svg>"#), html)
        XCTAssertTrue(html.contains(#"<h2 id="image-altline-break">"#), html)
        XCTAssertTrue(html.contains(#"<h2 id="svg-heading-1">SVG Heading</h2>"#), html)
    }

    func testRawHTMLHeadingNormalizerHandlesIntegrationPointScripts() {
        let samples = [
            "<svg><desc><script /></desc></svg><h1>Fake</h1></script><h1>Real</h1>",
            "<svg><title><script /></title></svg><h1>Fake</h1></script><h1>Real</h1>",
            "<math><mtext><script /></mtext></math><h1>Fake</h1></script><h1>Real</h1>",
        ]

        for sample in samples {
            var slugger = HeadingAnchorSlugger()
            let html = RawHTMLHeadingNormalizer.normalize(sample, slugger: &slugger)
            XCTAssertTrue(html.contains("<h1>Fake</h1></script><h1 id=\"real\">Real</h1>"), html)
        }
    }

    func testRawHTMLHeadingNormalizerScopesIntegrationPointsByNamespace() {
        let samples = [
            "<svg><mtext><textarea><h1>Fake</h1></textarea></mtext></svg><h1>Real</h1>",
            "<math><desc><textarea><h1>Fake</h1></textarea></desc></math><h1>Real</h1>",
        ]

        for sample in samples {
            var slugger = HeadingAnchorSlugger()
            let html = RawHTMLHeadingNormalizer.normalize(sample, slugger: &slugger)
            XCTAssertTrue(html.contains("<h1 id=\"fake\">Fake</h1>"), html)
            XCTAssertTrue(html.contains("<h1 id=\"real\">Real</h1>"), html)
        }
    }

    func testRawHTMLHeadingNormalizerTracksHTMLDescendantsOfMathIntegrationPoints() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            "<math><mtext><div><mglyph><textarea><h1>Same</h1></textarea></mglyph></div></mtext></math><h1>Same</h1>",
            slugger: &slugger
        )

        XCTAssertTrue(html.contains("<h1>Same</h1></textarea>"), html)
        XCTAssertTrue(html.contains("<h1 id=\"same\">Same</h1>"), html)
        XCTAssertEqual(html.components(separatedBy: "id=\"same\"").count - 1, 1)
    }

    func testRawHTMLHeadingSemanticTextHonorsSVGTitleNamespace() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            "<h1><svg><title><span>Text</span></title></svg>After</h1>",
            slugger: &slugger
        )

        XCTAssertTrue(html.contains("<h1 id=\"textafter\">"), html)
    }

    func testRawHTMLHeadingNormalizerHandlesConditionalFontBreakout() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            "<svg><font color=x><textarea><h1>Fake</h1></textarea></font></svg><h1>Real</h1>",
            slugger: &slugger
        )

        XCTAssertTrue(html.contains("<h1>Fake</h1></textarea>"), html)
        XCTAssertTrue(html.contains("<h1 id=\"real\">Real</h1>"), html)
    }

    func testRawHTMLHeadingNormalizerDecodesAnnotationEncoding() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            "<math><annotation-xml encoding=\"text&#x2F;html\"><textarea><h1>Fake</h1></textarea></annotation-xml></math><h1>Real</h1>",
            slugger: &slugger
        )

        XCTAssertTrue(html.contains("<h1>Fake</h1></textarea>"), html)
        XCTAssertTrue(html.contains("<h1 id=\"real\">Real</h1>"), html)
    }

    func testRawHTMLHeadingNormalizerUsesHTMLCharacterReferences() {
        let reserved = RawHTMLHeadingNormalizer.nonHeadingIDs(
            in: #"<div id="same&#45;1"></div>"#
        )
        XCTAssertEqual(reserved, ["same-1"])

        var slugger = HeadingAnchorSlugger(reserving: reserved)
        let html = RawHTMLHeadingNormalizer.normalize(
            "<h1>A &amp B</h1><h2>Same</h2><h2>Same</h2>",
            slugger: &slugger
        )
        XCTAssertTrue(html.contains("<h1 id=\"a-b\">A &amp B</h1>"), html)
        XCTAssertTrue(html.contains("<h2 id=\"same\">Same</h2>"), html)
        XCTAssertTrue(html.contains("<h2 id=\"same-2\">Same</h2>"), html)
    }

    func testRawHTMLHeadingNormalizerUsesWHATWGNumericReferences() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            "<h1>&#00000000065</h1><h2>&#131</h2>",
            slugger: &slugger
        )

        XCTAssertTrue(html.contains("<h1 id=\"a\">"), html)
        XCTAssertTrue(html.contains("<h2 id=\"ƒ\">"), html)
    }

    func testRawHTMLHeadingNormalizerClosesOnMismatchedHeadingEndTag() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            "<h1>Alpha</h2>tail",
            slugger: &slugger
        )

        XCTAssertEqual(html, "<h1 id=\"alpha\">Alpha</h2>tail")
    }

    func testRawHTMLHeadingNormalizerReprocessesForeignHeadingEndTag() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            "<h1>Alpha<svg></h2>tail",
            slugger: &slugger
        )

        XCTAssertEqual(html, "<h1 id=\"alpha\">Alpha<svg></h2>tail")
    }

    func testRawHTMLHeadingNormalizerAcceptsQuoteInUnquotedAttribute() {
        var slugger = HeadingAnchorSlugger()
        let html = RawHTMLHeadingNormalizer.normalize(
            #"<h1 data=x">Alpha</h1><h2>Beta</h2>"#,
            slugger: &slugger
        )

        XCTAssertTrue(html.contains(#"<h1 data=x" id="alpha">Alpha</h1>"#), html)
        XCTAssertTrue(html.contains("<h2 id=\"beta\">Beta</h2>"), html)
    }

    func testHeadingAnchorContractMatchesSharedFixture() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = root.appendingPathComponent("Sources/OuroMD/web/heading-anchor-contract.json")
        let contract = try JSONDecoder().decode(AnchorContract.self, from: Data(contentsOf: fixture))
        let html = render(contract.cases.map {
            $0.text.contains("\n") ? "\($0.text)\n---" : "# \($0.text)"
        }.joined(separator: "\n\n"))

        for item in contract.cases {
            XCTAssertTrue(html.contains("id=\"\(item.expected)\""), "missing heading id \(item.expected)")
        }
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

    func testReferenceStyleLinksResolveWithoutChangingUnresolvedSource() {
        let html = render("""
        [Full][full]

        [Collapsed][]

        [Shortcut]

        [Missing][absent]

        [full]: https://example.com/full
        [Collapsed]: https://example.com/collapsed
        [Shortcut]: https://example.com/shortcut
        """)

        XCTAssertTrue(html.contains("<a href=\"https://example.com/full\">Full</a>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com/collapsed\">Collapsed</a>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com/shortcut\">Shortcut</a>"))
        XCTAssertTrue(html.contains("[Missing][absent]"))
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

    func testShortCellsStayFreeWhileLongAndCodeBearingCellsGetAReadableFloor() {
        let html = render("| A | Long | Code |\n| --- | --- | --- |\n| hi | This description is definitely longer than the threshold | see `runStep()` here |")

        // A short plain cell gets no sizing class, so a narrow table shrinks to its
        // content and sits flush-left instead of being padded to a fixed width.
        XCTAssertTrue(html.contains("<td>hi</td>"))
        // A long-text cell keeps a readable floor.
        XCTAssertTrue(html.contains("<td class=\"ouro-long-cell\">This description"))
        // A cell that merely *contains* code (not code-only) also keeps the floor,
        // so the nowrap code can't be squeezed into a ribbon when the table narrows.
        XCTAssertTrue(html.contains("ouro-long-cell\">see <code>runStep()</code> here</td>"))
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

    func testHeadingIDsRemainUniqueAcrossBodyAndFootnotes() {
        let html = render("# Same\n\nBody[^a].\n\n[^a]: first\n\n    # Same")

        XCTAssertEqual(html.components(separatedBy: "id=\"same\"").count - 1, 1)
        XCTAssertEqual(html.components(separatedBy: "id=\"same-1\"").count - 1, 1)
    }

    func testHeadingIDsReserveFootnoteAndBackReferenceIDs() {
        let html = render(
            "# Fn A\n\n# Fnref A\n\n# Footnotes Def 1\n\n# Footnotes Ref 1\n\n# Footnotes Ref 1 2\n\nBody[^a] and again[^a].\n\n[^a]: first"
        )

        XCTAssertTrue(html.contains("<h1 id=\"fn-a-1\">Fn A</h1>"))
        XCTAssertTrue(html.contains("<h1 id=\"fnref-a-1\">Fnref A</h1>"))
        XCTAssertTrue(html.contains("<h1 id=\"footnotes-def-1-1\">Footnotes Def 1</h1>"))
        XCTAssertTrue(html.contains("<h1 id=\"footnotes-ref-1-1\">Footnotes Ref 1</h1>"))
        XCTAssertTrue(html.contains("<h1 id=\"footnotes-ref-1-2\">Footnotes Ref 1 2</h1>"))
        XCTAssertTrue(html.contains("<li id=\"fn-a\">"))
        XCTAssertTrue(html.contains("<sup id=\"fnref-a\">"))
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

    func testDistinctFootnoteLabelsWithCollidingSlugsReceiveUniqueIDs() {
        let html = render("One[^a!] two[^a?].\n\n[^a!]: first\n[^a?]: second")

        XCTAssertTrue(html.contains("href=\"#fn-a\""))
        XCTAssertTrue(html.contains("href=\"#fn-a-1\""))
        XCTAssertTrue(html.contains("<li id=\"fn-a\">"))
        XCTAssertTrue(html.contains("<li id=\"fn-a-1\">"))
    }

    func testFootnoteIDsAvoidAuthoredRawHTMLIDs() {
        let html = render("""
        <div id="fn-a"></div>
        <div id="fnref-b"></div>

        One[^a] two[^b].

        [^a]: first
        [^b]: second
        """)

        XCTAssertTrue(html.contains("<li id=\"fn-a-1\">"), html)
        XCTAssertTrue(html.contains("<sup id=\"fnref-a-1\">"), html)
        XCTAssertTrue(html.contains("<li id=\"fn-b-1\">"), html)
        XCTAssertTrue(html.contains("<sup id=\"fnref-b-1\">"), html)
        XCTAssertEqual(html.components(separatedBy: "id=\"fn-a\"").count - 1, 1)
        XCTAssertEqual(html.components(separatedBy: "id=\"fnref-b\"").count - 1, 1)
    }

    func testFootnoteIDsAvoidRawHTMLIDsInDeindentedDefinitions() {
        let html = render("""
        Body[^a].

        [^a]:

            <div id="fn-a"></div>
        """)

        XCTAssertTrue(html.contains("<li id=\"fn-a-1\">"), html)
        XCTAssertTrue(html.contains("<div id=\"fn-a\"></div>"), html)
        XCTAssertEqual(html.components(separatedBy: "id=\"fn-a\"").count - 1, 1)
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
