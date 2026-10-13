import AppKit
import PDFKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintPageFootnotesTests: XCTestCase {
    func testDefaultCitationsAreDeduplicatedAtBottomOfTheirReferencePage() async throws {
        let body = """
        <h2>Company Alpha</h2><p>ALPHA-REFERENCE <a href="https://example.com/shared">source</a> and <a href="https://example.com/shared"><code>code label</code></a> and <a href="https://example.com/shared"><img alt="linked image" width="16" height="16" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3C/svg%3E"></a>.</p>
        <div class="page-break"></div><h2>Company Beta</h2><p>BETA-REFERENCE <a href="https://example.com/shared">source again</a>.</p>
        """
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Page sources", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 2)
        for (index, token) in ["ALPHA-REFERENCE", "BETA-REFERENCE"].enumerated() {
            let page = try XCTUnwrap(pdf.page(at: index))
            let text = try XCTUnwrap(page.string)
            XCTAssertTrue(text.contains(token))
            XCTAssertEqual(text.components(separatedBy: "https://example.com/shared").count - 1, 1)
            XCTAssertEqual(text.components(separatedBy: "[S1]").count - 1, index == 0 ? 4 : 2, "Every linked label/image needs its own source marker")
            XCTAssertFalse(text.contains("Link sources (endnotes)"))
            let range = try XCTUnwrap(text.range(of: "https://example.com/shared"))
            let bounds = try XCTUnwrap(page.selection(for: NSRange(range, in: text))?.bounds(for: page))
            XCTAssertGreaterThanOrEqual(bounds.minY, 54)
            XCTAssertLessThan(bounds.maxY, 110, "Sources belong at the bottom, not after the body")
            XCTAssertTrue(page.annotations.contains { $0.url?.absoluteString == "https://example.com/shared" })
        }
    }

    func testSelectedHeadingLevelStartsEachCompanyWithoutBlankFirstPage() async throws {
        var settings = PrintLayoutSettings.default
        settings.headingBreakLevel = 2
        let prepared = try await PrintDocumentRenderer().prepareDocument(
            bodyHTML: "<h2>Company Alpha</h2><p>ALPHA-BODY</p><h3>Detail</h3><p>DETAIL-BODY</p><h2>Company Beta</h2><p>BETA-BODY</p><h2>Company Gamma</h2><p>GAMMA-BODY</p>",
            title: "Company sections", baseURL: nil, settings: settings
        )
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 3)
        for (index, name) in ["Company Alpha", "Company Beta", "Company Gamma"].enumerated() {
            let page = try XCTUnwrap(pdf.page(at: index))
            let text = try XCTUnwrap(page.string)
            let range = try XCTUnwrap(text.range(of: name))
            let bounds = try XCTUnwrap(page.selection(for: NSRange(range, in: text))?.bounds(for: page))
            XCTAssertGreaterThan(bounds.minY, 690)
        }
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("DETAIL-BODY") == true)
    }

    func testSplitTableAndRepeatedAuthoredNotesHaveUniqueDestinationIDs() async throws {
        let rows = (1...70).map { "<tr><td>ROW-\($0)</td><td>Evidence that wraps across lines.</td></tr>" }.joined()
        let body = "<h2 id=\"overview\">Overview</h2><p><a id=\"ref-earlier\" href=\"#fn-note\">1</a> EARLIER-REFERENCE</p><p><a id=\"ref-one\" href=\"#fn-note\">1</a> ORIGINAL-REFERENCE</p><table id=\"table\"><thead><tr><th id=\"column-heading\">Row</th><th>Evidence</th></tr></thead><tbody>\(rows)</tbody></table><div class=\"page-break\"></div><p><a id=\"ref-two\" href=\"#fn-note\">1</a></p><section class=\"footnotes\"><ol><li id=\"fn-note\">AUTHORED-TEXT <a href=\"#ref-one\" class=\"footnote-backref\">↩</a> <a href=\"#overview\">Other section</a> <a href=\"#ref-one\">See original reference</a></li></ol></section>"
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Unique destinations", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let duplicates = try await prepared.webView.evaluateJavaScript("(function(){var ids=Array.from(document.querySelectorAll('[id]')).map(n=>n.id); return ids.length-new Set(ids).size;})()") as? Int
        XCTAssertEqual(duplicates, 0)
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let first = try XCTUnwrap(pdf.page(at: 0))
        let last = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1))
        XCTAssertTrue(first.string?.contains("AUTHORED-TEXT") == true)
        XCTAssertTrue(last.string?.contains("AUTHORED-TEXT") == true)
        for index in [0, pdf.pageCount - 1] {
            let page = try XCTUnwrap(pdf.page(at: index))
            let text = try XCTUnwrap(page.string)
            let backlinkRange = try XCTUnwrap(text.range(of: "↩"))
            let backlinkBounds = try XCTUnwrap(page.selection(for: NSRange(backlinkRange, in: text))?.bounds(for: page))
            let backlinks = page.annotations.filter { $0.destination != nil && $0.bounds.intersects(backlinkBounds) }
            XCTAssertEqual(backlinks.count, 1, "Locate the footer BACKLINK, not merely any same-page destination")
            let backlinkPage = try XCTUnwrap(backlinks.first?.destination?.page)
            let backlinkDocument = try XCTUnwrap(backlinkPage.document)
            XCTAssertEqual(backlinkDocument.index(for: backlinkPage), index, "The repeated note's backlink must return to its reference page")
            if index == 0 {
                let originalRange = try XCTUnwrap(text.range(of: "ORIGINAL-REFERENCE"))
                let originalBounds = try XCTUnwrap(page.selection(for: NSRange(originalRange, in: text))?.bounds(for: page))
                XCTAssertEqual(try XCTUnwrap(backlinks.first?.destination).point.y, originalBounds.maxY, accuracy: 6, "Prefer the authored backlink's original target when it is on this page")
            }

            for label in ["Other section", "See original reference"] {
                let otherRange = try XCTUnwrap(text.range(of: label))
                let otherBounds = try XCTUnwrap(page.selection(for: NSRange(otherRange, in: text))?.bounds(for: page))
                let otherLink = try XCTUnwrap(page.annotations.first { $0.destination != nil && $0.bounds.intersects(otherBounds) })
                let otherPage = try XCTUnwrap(otherLink.destination?.page)
                let otherDocument = try XCTUnwrap(otherPage.document)
                XCTAssertEqual(otherDocument.index(for: otherPage), 0, "A genuine authored internal link must retain its original destination")
            }
        }
    }

    func testAuthoredNotesLocalSourcesAndCommentBreakRemainOnReferencePage() async throws {
        let body = """
        <p>FIRST-REFERENCE <a href="https://example.com/public">web</a><sup><a id="fnref-note" href="#fn-note">1</a></sup> <a href="file:///Users/example/Documents/report.pdf">local</a> <a href="relative/report.pdf">relative</a></p>
        <!-- pagebreak --><p>SECOND-BODY</p>
        <section class="footnotes"><ol><li id="fn-note"><p>AUTHORED-NOTE-CONTENT <a href="#fnref-note">↩</a></p></li><li id="fn-unused">UNREFERENCED-NOTE-CONTENT</li></ol></section>
        """
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Authored notes", baseURL: URL(string: "file:///Users/example/Documents/guide.md"), settings: .default)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 2)
        let first = try XCTUnwrap(pdf.page(at: 0))
        let text = try XCTUnwrap(first.string)
        for source in ["https://example.com/public", "file:///Users/example/Documents/report.pdf", "file:///Users/example/Documents/relative/report.pdf", "AUTHORED-NOTE-CONTENT"] {
            XCTAssertTrue(text.contains(source), source)
        }
        XCTAssertTrue(text.contains("[S1]"))
        XCTAssertTrue(text.contains("Note 1"))
        XCTAssertFalse(pdf.page(at: 1)?.string?.contains("AUTHORED-NOTE-CONTENT") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("UNREFERENCED-NOTE-CONTENT") == true)
        let range = try XCTUnwrap(text.range(of: "AUTHORED-NOTE-CONTENT"))
        XCTAssertLessThan(try XCTUnwrap(first.selection(for: NSRange(range, in: text))?.bounds(for: first)).maxY, 180)
        XCTAssertGreaterThanOrEqual(first.annotations.filter { $0.destination != nil }.count, 2)
    }

    func testExcessiveNoteReservationFailsWithActionableMessageInsteadOfCropping() async throws {
        let note = String(repeating: "Long authored note with every word retained. ", count: 400)
        do {
            let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Reference <a id=\"ref\" href=\"#fn-large\">1</a></p><section class=\"footnotes\"><ol><li id=\"fn-large\">\(note)</li></ol></section>", title: "Long note", baseURL: nil, settings: .default)
            prepared.releaseHold()
            XCTFail("Oversized notes must not be silently cropped")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Choose Endnotes or Original links"), error.localizedDescription)
        }
    }

    func testCitedLongTableAndParagraphKeepEveryTokenOnceAndNotesInsideMargins() async throws {
        let rows = (1...100).map { "<tr><td>ROW-\($0)-TOKEN</td><td>Readable evidence <a href=\"https://example.com/table\">source</a></td></tr>" }.joined()
        let prose = (1...180).map { "SENTENCE-\($0)-TOKEN readable prose must survive boundaries and footnote reservations." }.joined(separator: " ")
        let body = "<h2>Table</h2><table><thead><tr><th>Row</th><th>Evidence</th></tr></thead><tbody>\(rows)</tbody><tfoot><tr><td>TABLE-FOOTER-TOKEN</td></tr></tfoot></table><h2>Paragraph</h2><p><a href=\"https://example.com/paragraph\">source</a> \(prose)</p><p>FINAL-TOKEN</p>"
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Reservation proof", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = (pdf.string ?? "").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for token in (1...100).map({ "ROW-\($0)-TOKEN" }) + (1...180).map({ "SENTENCE-\($0)-TOKEN" }) + ["TABLE-FOOTER-TOKEN", "FINAL-TOKEN"] {
            XCTAssertEqual(text.components(separatedBy: token).count - 1, 1, token)
        }
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            for annotation in page.annotations {
                XCTAssertGreaterThanOrEqual(annotation.bounds.minY, 53)
                XCTAssertLessThanOrEqual(annotation.bounds.maxY, 739)
            }
        }
        if let directory = ProcessInfo.processInfo.environment["OURO_PRINT_FOOTNOTE_EVIDENCE_DIR"] {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try data.write(to: root.appendingPathComponent("page-footnotes-synthetic.pdf"))
            let metrics: [String: Any] = ["pages": pdf.pageCount, "rows": 100, "sentences": 180, "sourceAnnotations": (0..<pdf.pageCount).reduce(0) { $0 + (pdf.page(at: $1)?.annotations.count ?? 0) }, "allTokensExactlyOnce": true]
            try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]).write(to: root.appendingPathComponent("page-footnotes-synthetic-metrics.json"))
        }
    }

    func testInitialManualMarkerDoesNotInsertBlankHeadingPage() async throws {
        var settings = PrintLayoutSettings.default
        settings.headingBreakLevel = 2
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<div class=\"page-break\"></div><h2>First company</h2><p>FIRST-TOKEN</p><!-- pagebreak --><h2>Second company</h2><p>SECOND-TOKEN</p>", title: "Leading break", baseURL: nil, settings: settings)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("FIRST-TOKEN") == true)
    }

    func testUniqueTableSourcesReserveSpaceWithoutLosingRowContent() async throws {
        let rows = (1...80).map { "<tr><td>UNIQUE-ROW-\($0)-TOKEN</td><td>Evidence for this row <a href=\"https://example.com/source-\($0)\">citation</a></td></tr>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<table><thead><tr><th>Row</th><th>Evidence</th></tr></thead><tbody>\(rows)</tbody><tfoot><tr><td>UNIQUE-FOOTER-TOKEN</td></tr></tfoot></table>", title: "Dense sources", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let fullText = (pdf.string ?? "").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for row in 1...80 {
            XCTAssertEqual(fullText.components(separatedBy: "UNIQUE-ROW-\(row)-TOKEN").count - 1, 1)
            let page = try XCTUnwrap((0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.first { ($0.string ?? "").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).contains("UNIQUE-ROW-\(row)-TOKEN") })
            XCTAssertTrue(page.string?.contains("https://example.com/source-\(row)") == true)
        }
        XCTAssertEqual(fullText.components(separatedBy: "UNIQUE-FOOTER-TOKEN").count - 1, 1)
        XCTAssertLessThan(pdf.pageCount, 20)
    }

    func testLongURLAndAuthoredNoteWrapAndGeometryRecomputesPageCount() async throws {
        let path = (1...50).map { "path-\($0)-token" }.joined(separator: "/")
        let note = (1...45).map { "NOTE-\($0)-TOKEN" }.joined(separator: " ")
        let prose = (1...100).map { "Readable sentence \($0) with enough content to exercise changed paper geometry." }.joined(separator: " ")
        let body = "<p id=\"ref\">BODY-REFERENCE <a href=\"https://example.com/\(path)\">long source</a> <a href=\"#fn-long\">1</a></p><p>\(prose)</p><section class=\"footnotes\"><ol><li id=\"fn-long\">\(note) <a href=\"#ref\">↩</a></li></ol></section>"
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Wrapped notes", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let initialPages = prepared.layoutMetrics.pageCount
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let first = try XCTUnwrap(pdf.page(at: 0))
        let text = (first.string ?? "").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for token in (1...50).map({ "path-\($0)-token" }) + (1...45).map({ "NOTE-\($0)-TOKEN" }) {
            XCTAssertEqual(text.components(separatedBy: token).count - 1, 1, token)
        }
        var spacious = PrintLayoutSettings.default
        spacious.fontSize = 16
        spacious.lineSpacing = 2
        try await prepared.reload(with: spacious)
        XCTAssertGreaterThan(prepared.layoutMetrics.pageCount, initialPages)
        let current = try await prepared.createPDFData()
        XCTAssertEqual(PDFDocument(data: current)?.pageCount, prepared.layoutMetrics.pageCount)
    }
}
