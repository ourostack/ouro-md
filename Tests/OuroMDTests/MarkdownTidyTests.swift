import XCTest
@testable import OuroMD

final class MarkdownTidyTests: XCTestCase {
    func testExpandsTableSeparator() {
        let input = "| A | B |\n| - | - |\n| 1 | 2 |"
        let out = AppModel.tidyMarkdown(input)
        XCTAssertEqual(out, "| A | B |\n| --- | --- |\n| 1 | 2 |")
    }

    func testPreservesTableAlignment() {
        let out = AppModel.tidyMarkdown("| A | B | C |\n| :- | -: | :-: |\n| 1 | 2 | 3 |")
        XCTAssertEqual(out, "| A | B | C |\n| :--- | ---: | :---: |\n| 1 | 2 | 3 |")
    }

    func testCollapsesConsecutiveBlankLines() {
        XCTAssertEqual(AppModel.tidyMarkdown("a\n\n\n\nb"), "a\n\nb")
    }

    func testLeavesHorizontalRuleAlone() {
        // A thematic break has no pipe — must not be treated as a table separator.
        XCTAssertEqual(AppModel.tidyMarkdown("para\n\n---\n\nmore"), "para\n\n---\n\nmore")
    }

    func testDoesNotTouchFencedCode() {
        // Lines that look like separators, and blank lines, inside a code fence
        // must be preserved exactly.
        let input = "```\n| - | - |\n\n\nx\n```"
        XCTAssertEqual(AppModel.tidyMarkdown(input), input)
    }

    func testNonTableContentUnchanged() {
        let input = "# H\n\n- a\n- b\n\n> quote\n\ntext"
        XCTAssertEqual(AppModel.tidyMarkdown(input), input)
    }

    func testPreservesOriginalWhenOnlyKnownEditorNormalizationChanged() {
        let original = """
        ### Tables line up


        | Theme      | Mood             | Type  |
        | :--------- | :--------------- | :---- |
        | Quartz     | calm daylight    | sans  |
        """
        let editorOutput = """
        ### Tables line up

        | Theme      | Mood             | Type  |
        | :--- | :--- | :--- |
        | Quartz     | calm daylight    | sans  |
        """

        XCTAssertEqual(AppModel.tidyMarkdown(editorOutput, preserving: original), original)
    }
}
