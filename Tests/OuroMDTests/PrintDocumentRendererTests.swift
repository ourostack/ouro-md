import AppKit
import PDFKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintDocumentRendererTests: XCTestCase {
    func testRenderedPDFUsesSharedPrintLayoutAndDeduplicatedExternalReferences() async throws {
        let renderer = PrintDocumentRenderer(scriptProvider: {
            PrintLayoutScriptLoader.load() ?? ""
        })
        let settings = PrintLayoutSettings(
            margins: PrintPageMargins(top: 54, right: 54, bottom: 54, left: 54),
            fontSize: 12,
            lineSpacing: 1.5,
            includeExternalLinkReferences: true
        )
        let prepared = try await renderer.prepareDocument(
            bodyHTML: Self.syntheticBodyHTML,
            title: "print-proof.pdf",
            baseURL: URL(fileURLWithPath: "/Users/microsoft/code/ouro-md-print-layout"),
            settings: settings
        )
        defer { prepared.releaseHold() }
        XCTAssertEqual(prepared.printInfo.topMargin, 54)
        XCTAssertEqual(prepared.printInfo.leftMargin, 54)
        XCTAssertEqual(prepared.makePrintOperation().printInfo.topMargin, 54)
        let evidenceDirectory = URL(fileURLWithPath: "/Users/microsoft/.local/share/ms-desk/private-evidence/markdown-reading-and-printing/printing", isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        let pdfURL = evidenceDirectory.appendingPathComponent("print-layout-proof.pdf")
        try await prepared.writePDF(to: pdfURL)
        let pdf = try Data(contentsOf: pdfURL)

        guard let document = PDFDocument(data: pdf) else {
            return XCTFail("Expected a readable PDF document")
        }

        XCTAssertGreaterThan(document.pageCount, 1)
        let fullText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(fullText.contains("External links"))
        XCTAssertTrue(fullText.contains("https://example.com/repeated?query=1&value=2"))
        XCTAssertEqual(fullText.components(separatedBy: "https://example.com/repeated?query=1&value=2").count - 1, 2)
        XCTAssertTrue(fullText.contains("Author footnote text stays in place."))
        XCTAssertFalse(fullText.contains("https://example.com/code-only"))
        XCTAssertFalse(fullText.contains("https://example.com/image-only"))
        XCTAssertFalse(fullText.contains("#overview"))

        try Self.writeEvidence(pdf: pdf, document: document, fullText: fullText, in: evidenceDirectory)
    }

    private static let syntheticBodyHTML = {
        let lead = "<p id=\"overview\">Overview with <a href=\"https://example.com/repeated?query=1&amp;value=2\">an external reference</a>, <a href=\"#overview\">an internal anchor</a>, <a href=\"https://example.com/code-only\"><code>--flag</code></a>, and <a href=\"https://example.com/image-only\"><img alt=\"Diagram\" src=\"data:image/gif;base64,R0lGODlhAQABAAAAACw=\"></a>.</p>"
        let repeated = "<p>Repeated prose cites <a href=\"https://example.com/repeated?query=1&amp;value=2\">the same destination</a> so the printed endnotes must deduplicate it instead of listing it twice.</p>"
        let table = "<table><thead><tr><th>Column</th><th>Notes</th></tr></thead><tbody><tr><td>Wide content</td><td><a href=\"https://example.com/secondary\">Secondary destination</a> with a deliberately long paragraph that forces the table to wrap across multiple lines and pages when repeated enough times for the synthetic proof.</td></tr></tbody></table>"
        let footnote = "<section class=\"footnotes\"><hr><ol><li id=\"fn-note\">Author footnote text stays in place. <a href=\"#fnref-note\" class=\"footnote-backref\">↩</a></li></ol></section>"
        return (["<h1>Printable proof</h1>", lead] + Array(repeating: repeated + table, count: 40) + [footnote]).joined(separator: "\n")
    }()

    private static func writeEvidence(pdf: Data, document: PDFDocument, fullText: String, in evidenceDirectory: URL) throws {
        let pdfURL = evidenceDirectory.appendingPathComponent("print-layout-proof.pdf")
        try pdf.write(to: pdfURL, options: .atomic)

        if let page = document.page(at: 0) {
            let image = page.thumbnail(of: NSSize(width: 900, height: 1165), for: .mediaBox)
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: evidenceDirectory.appendingPathComponent("print-layout-proof-page-1.png"), options: .atomic)
            }
        }

        let summary = """
        pageCount=\(document.pageCount)
        repeatedURLCount=\(fullText.components(separatedBy: "https://example.com/repeated?query=1&value=2").count - 1)
        containsEndnotes=\(fullText.contains("External links"))
        containsFootnote=\(fullText.contains("Author footnote text stays in place."))
        """
        try summary.write(to: evidenceDirectory.appendingPathComponent("print-layout-proof-summary.txt"), atomically: true, encoding: .utf8)
    }
}
