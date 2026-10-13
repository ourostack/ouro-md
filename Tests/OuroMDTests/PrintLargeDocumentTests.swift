import AppKit
import PDFKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintLargeDocumentTests: XCTestCase {
    func testSingleMultipageTableRetainsEveryRowExactlyOnce() async throws {
        let rows = (1...100).map {
            "<tr><td>ROW-\($0)-BEGIN</td><td>Readable table evidence for this row, with enough detail to wrap while keeping ROW-\($0)-END intact.</td></tr>"
        }.joined()
        let body = "<h1>Long table</h1><table><thead><tr><th>Row</th><th>Evidence</th></tr></thead><tbody>\(rows)</tbody><tfoot><tr><td colspan=\"2\">TABLE-FOOTER-NOTE</td></tr></tfoot></table><p>AFTER-TABLE-END</p>"
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Long table", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for row in 1...100 {
            XCTAssertEqual(text.components(separatedBy: "ROW-\(row)-BEGIN").count - 1, 1, "Missing or duplicated beginning of row \(row)")
            XCTAssertEqual(text.components(separatedBy: "ROW-\(row)-END").count - 1, 1, "Missing or duplicated end of row \(row)")
        }
        XCTAssertEqual(text.components(separatedBy: "AFTER-TABLE-END").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "TABLE-FOOTER-NOTE").count - 1, 1)
    }

    func testParagraphLongerThanOnePageRetainsEverySentenceExactlyOnce() async throws {
        let sentences = (1...180).map { "SENTENCE-\($0)-BEGIN contains readable prose that must survive page boundaries. SENTENCE-\($0)-END." }.joined(separator: " ")
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h1>Long paragraph</h1><p>\(sentences)</p><p>AFTER-PARAGRAPH-END</p>", title: "Long paragraph", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for sentence in 1...180 {
            XCTAssertEqual(text.components(separatedBy: "SENTENCE-\(sentence)-BEGIN").count - 1, 1, "Missing or duplicated beginning of sentence \(sentence)")
            XCTAssertEqual(text.components(separatedBy: "SENTENCE-\(sentence)-END").count - 1, 1, "Missing or duplicated end of sentence \(sentence)")
        }
        XCTAssertEqual(text.components(separatedBy: "AFTER-PARAGRAPH-END").count - 1, 1)
    }
}
