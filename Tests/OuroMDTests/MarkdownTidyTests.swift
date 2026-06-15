import XCTest
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
