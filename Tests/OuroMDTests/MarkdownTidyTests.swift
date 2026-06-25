import XCTest
@testable import OuroMDCore
@testable import OuroMD

final class MarkdownTidyTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-roundtrip-\(UUID().uuidString).md")
    }

    func testRoundTripperReadsExistingInput() throws {
        let url = tempFile()
        try "# Existing\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try RoundTripper.readInput(url), "# Existing\n")
    }

    func testRoundTripperRejectsMissingInput() {
        let url = tempFile()

        XCTAssertThrowsError(try RoundTripper.readInput(url))
    }

    func testExpandsTableSeparator() {
        let input = "| A | B |\n| - | - |\n| 1 | 2 |"
        let out = MarkdownTidy.tidy(input)
        XCTAssertEqual(out, "| A | B |\n| --- | --- |\n| 1 | 2 |")
    }

    func testPreservesTableAlignment() {
        let out = MarkdownTidy.tidy("| A | B | C |\n| :- | -: | :-: |\n| 1 | 2 | 3 |")
        XCTAssertEqual(out, "| A | B | C |\n| :--- | ---: | :---: |\n| 1 | 2 | 3 |")
    }

    func testCollapsesConsecutiveBlankLines() {
        XCTAssertEqual(MarkdownTidy.tidy("a\n\n\n\nb"), "a\n\nb")
    }

    func testLeavesHorizontalRuleAlone() {
        // A thematic break has no pipe — must not be treated as a table separator.
        XCTAssertEqual(MarkdownTidy.tidy("para\n\n---\n\nmore"), "para\n\n---\n\nmore")
    }

    func testDoesNotRewriteNonTableLinesThatMerelyUseSeparatorCharacters() {
        // AN-003: a bullet list item whose content is a pipe (only `|:- ` chars,
        // a pipe and a dash) must NOT be classified as a table separator and
        // rewritten — that would silently corrupt content on save.
        XCTAssertEqual(MarkdownTidy.tidy("- |"), "- |")
        XCTAssertEqual(MarkdownTidy.tidy("- | -"), "- | -")
        // AN-002 negative control: an alignment-only line (pipes + colons, no
        // dash) is not a delimiter row — pins the "every cell is :?-+:?" guard.
        XCTAssertEqual(MarkdownTidy.tidy("| : | : |"), "| : | : |")
        // Empty cells aren't a delimiter row either.
        XCTAssertEqual(MarkdownTidy.tidy("| |"), "| |")
        XCTAssertEqual(MarkdownTidy.tidy("||"), "||")
    }

    func testExpandsCompactAndNoSpaceSeparators() {
        // Real delimiter rows must still expand, including the no-space form.
        XCTAssertEqual(MarkdownTidy.tidy("| A |\n|---|\n| 1 |"), "| A |\n| --- |\n| 1 |")
        XCTAssertEqual(MarkdownTidy.tidy("| A | B |\n|-|:-:|\n| 1 | 2 |"),
                       "| A | B |\n| --- | :---: |\n| 1 | 2 |")
    }

    func testTidyIsIdempotent() {
        // tidy must be a fixed point: applying it twice equals applying it once.
        // Negative control — any non-idempotent normalization (e.g. an expanded
        // separator the classifier no longer recognizes, or blank-collapse that
        // keeps eating blanks) makes the second application differ and fails here.
        let inputs = [
            "| A | B |\n| - | - |\n| 1 | 2 |",                 // separator expansion
            "a\n\n\n\nb",                                       // blank-run collapse
            "---\ntitle: x\nstatus: done\n---\n# H\n\nBody",    // front-matter blank restore
            "```\n| - | - |\n\n\nx\n```",                       // fenced content untouched
            "# H\n\n- a\n- b\n\n> quote\n\ntext",               // mixed prose
            "| A |\n|---|\n| 1 |",                              // no-space separator
            "- |\n- list item",                                // non-table lines (left as-is)
            "",                                                 // empty input
        ]
        for input in inputs {
            let once = MarkdownTidy.tidy(input)
            XCTAssertEqual(MarkdownTidy.tidy(once), once,
                           "tidy is not idempotent for \(input.debugDescription)")
        }
    }

    func testDoesNotTouchFencedCode() {
        // Lines that look like separators, and blank lines, inside a code fence
        // must be preserved exactly.
        let input = "```\n| - | - |\n\n\nx\n```"
        XCTAssertEqual(MarkdownTidy.tidy(input), input)
    }

    func testNonTableContentUnchanged() {
        let input = "# H\n\n- a\n- b\n\n> quote\n\ntext"
        XCTAssertEqual(MarkdownTidy.tidy(input), input)
    }

    func testRestoresBlankLineAfterFrontMatter() {
        // Vditor drops the conventional blank line between front matter and the
        // body; tidy restores it so agent-authored docs round-trip cleanly.
        let dropped = "---\ntitle: x\nstatus: done\n---\n# Heading\n\nBody"
        let expected = "---\ntitle: x\nstatus: done\n---\n\n# Heading\n\nBody"
        XCTAssertEqual(MarkdownTidy.tidy(dropped), expected)
    }

    func testFrontMatterWithExistingBlankLineUnchanged() {
        let input = "---\ntitle: x\n---\n\n# Heading\n\nBody"
        XCTAssertEqual(MarkdownTidy.tidy(input), input)
    }

    func testFrontMatterOnlyNoBodyUnchanged() {
        let input = "---\ntitle: x\n---\n"
        XCTAssertEqual(MarkdownTidy.tidy(input), input)
    }

    func testMidDocumentTripleDashNotTreatedAsFrontMatter() {
        // A `---` that isn't at the very top is a thematic break, untouched.
        let input = "# Title\n\nText.\n\n---\n\nMore."
        XCTAssertEqual(MarkdownTidy.tidy(input), input)
    }
    func testUnclosedFrontMatterFenceLeftUnchanged() {
        // Opening `---` with no closing fence is not front matter; leave it be.
        let input = "---\ntitle: x\nbody with no closing fence"
        XCTAssertEqual(MarkdownTidy.tidy(input), input)
    }
    func testFrontMatterClosingFenceAtEndOfDocumentUnchanged() {
        // Closing `---` is the final line (no trailing newline, nothing after):
        // there is no body to separate, so nothing is inserted.
        let input = "---\ntitle: x\n---"
        XCTAssertEqual(MarkdownTidy.tidy(input), input)
    }

    func testRoundTripProbePreservesOriginalWhenOnlyKnownEditorNormalizationChanged() {
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

        XCTAssertEqual(MarkdownTidy.roundTripProbeOutput(editorOutput, preserving: original), original)
    }

    func testRoundTripProbeReturnsTidiedOutputWhenContentChanged() {
        XCTAssertEqual(
            MarkdownTidy.roundTripProbeOutput("changed", preserving: "original"),
            "changed"
        )
    }

    func testNormalTidyDoesNotConsultOriginalForDirtySave() {
        let dirtyEditorOutput = """
        ### Tables line up

        | Theme      | Mood             | Type  |
        | :--- | :--- | :--- |
        | Quartz     | calm daylight    | sans  |
        """

        XCTAssertEqual(MarkdownTidy.tidy(dirtyEditorOutput), dirtyEditorOutput)
    }
}
